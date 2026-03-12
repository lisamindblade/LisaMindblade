from __future__ import annotations

import asyncio
import json
import subprocess
from dataclasses import dataclass
from typing import Any, Callable, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen


class OpenClawClientError(RuntimeError):
    """Raised when OpenClaw request/response processing fails."""


@dataclass(frozen=True)
class OpenClawClientConfig:
    base_url: str
    chat_path: str
    model: str
    api_key: str | None = None
    timeout_seconds: float = 45.0
    system_prompt: str = "You are Lisa, a concise and practical voice assistant."


class OpenClawClient(Protocol):
    async def complete(self, *, session_id: str, user_text: str) -> str:
        """Generate one assistant completion from user text."""


@dataclass(frozen=True)
class OpenClawCLIConfig:
    command: str = "openclaw"
    agent_id: str = "main"
    timeout_seconds: float = 120.0
    use_local: bool = False


Runner = Callable[[list[str], float], subprocess.CompletedProcess[str]]


class CLIOpenClawClient(OpenClawClient):
    """Adapter that invokes `openclaw agent --json` for one turn."""

    def __init__(self, config: OpenClawCLIConfig, runner: Runner | None = None):
        self.config = config
        self.runner = runner or _default_runner

    async def complete(self, *, session_id: str, user_text: str) -> str:
        return await asyncio.to_thread(
            self._complete_sync,
            session_id=session_id,
            user_text=user_text,
        )

    def _complete_sync(self, *, session_id: str, user_text: str) -> str:
        command = [
            self.config.command,
            "agent",
            "--agent",
            self.config.agent_id,
            "--session-id",
            session_id,
            "--message",
            user_text,
            "--json",
            "--timeout",
            str(int(self.config.timeout_seconds)),
        ]
        if self.config.use_local:
            command.append("--local")

        completed = self.runner(command, self.config.timeout_seconds)
        merged_output = "\n".join(
            part for part in [completed.stdout.strip(), completed.stderr.strip()] if part
        ).strip()
        if not merged_output:
            raise OpenClawClientError("OpenClaw CLI returned no output.")

        response_obj = _extract_json_document(merged_output)
        text = _extract_cli_text(response_obj)
        if text:
            return text

        raise OpenClawClientError("OpenClaw CLI returned JSON without a text payload.")


class HTTPOpenClawClient(OpenClawClient):
    """Thin HTTP client for OpenClaw-compatible chat completion APIs."""

    def __init__(self, config: OpenClawClientConfig):
        self.config = config

    async def complete(self, *, session_id: str, user_text: str) -> str:
        return await asyncio.to_thread(
            self._complete_sync,
            session_id=session_id,
            user_text=user_text,
        )

    def _complete_sync(self, *, session_id: str, user_text: str) -> str:
        endpoint = _resolve_endpoint(self.config.base_url, self.config.chat_path)

        request_body = {
            "model": self.config.model,
            "messages": [
                {"role": "system", "content": self.config.system_prompt},
                {"role": "user", "content": user_text},
            ],
            "stream": False,
            "metadata": {"session_id": session_id},
        }

        headers = {"Content-Type": "application/json"}
        if self.config.api_key:
            headers["Authorization"] = f"Bearer {self.config.api_key}"

        request = Request(
            endpoint,
            data=json.dumps(request_body).encode("utf-8"),
            headers=headers,
            method="POST",
        )

        try:
            with urlopen(request, timeout=self.config.timeout_seconds) as response:
                raw_response = response.read().decode("utf-8")
        except HTTPError as exc:
            body = ""
            try:
                body = exc.read().decode("utf-8", errors="ignore")
            except Exception:
                body = ""
            message = body[:350] if body else str(exc.reason)
            raise OpenClawClientError(f"OpenClaw HTTP {exc.code}: {message}") from exc
        except (URLError, OSError) as exc:
            raise OpenClawClientError(f"OpenClaw request failed: {exc}") from exc

        try:
            response_obj = json.loads(raw_response)
        except json.JSONDecodeError as exc:
            raise OpenClawClientError("OpenClaw returned non-JSON payload.") from exc

        completion = extract_assistant_text(response_obj).strip()
        if not completion:
            raise OpenClawClientError("OpenClaw returned an empty assistant response.")
        return completion


def _resolve_endpoint(base_url: str, path: str) -> str:
    normalized_base = base_url.strip()
    if not normalized_base:
        raise OpenClawClientError("OpenClaw base URL is empty.")

    normalized_path = path.strip() or "/v1/chat/completions"
    return urljoin(normalized_base.rstrip("/") + "/", normalized_path.lstrip("/"))


def _default_runner(command: list[str], timeout_seconds: float) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
    )


def _extract_json_document(raw_output: str) -> dict[str, Any]:
    text = raw_output.strip()
    if not text:
        raise OpenClawClientError("Cannot parse JSON from empty output.")

    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise OpenClawClientError("Could not find JSON object in OpenClaw CLI output.")

    fragment = text[start : end + 1]
    try:
        parsed = json.loads(fragment)
    except json.JSONDecodeError as exc:
        raise OpenClawClientError("Failed to parse JSON from OpenClaw CLI output.") from exc

    if not isinstance(parsed, dict):
        raise OpenClawClientError("Expected top-level JSON object from OpenClaw CLI.")
    return parsed


def _extract_cli_text(response_obj: dict[str, Any]) -> str | None:
    payloads = response_obj.get("payloads")
    if isinstance(payloads, list):
        for payload in payloads:
            if isinstance(payload, dict):
                text = payload.get("text")
                if isinstance(text, str) and text.strip():
                    return text.strip()

    # Fallback in case CLI output shape changes toward OpenAI-compatible format.
    try:
        return extract_assistant_text(response_obj)
    except OpenClawClientError:
        return None


def extract_assistant_text(response_obj: dict[str, Any]) -> str:
    """Extract assistant text from OpenAI-compatible and similar response shapes."""
    output_text = response_obj.get("output_text")
    if isinstance(output_text, str) and output_text.strip():
        return output_text

    response_text = response_obj.get("response")
    text = _coerce_to_text(response_text)
    if text:
        return text

    choices = response_obj.get("choices")
    if isinstance(choices, list) and choices:
        first_choice = choices[0]
        if isinstance(first_choice, dict):
            message = first_choice.get("message")
            if isinstance(message, dict):
                text = _coerce_to_text(message.get("content"))
                if text:
                    return text

            text = _coerce_to_text(first_choice.get("text"))
            if text:
                return text

    raise OpenClawClientError("Could not extract assistant text from OpenClaw response.")


def _coerce_to_text(value: Any) -> str | None:
    if isinstance(value, str):
        cleaned = value.strip()
        return cleaned or None

    if isinstance(value, list):
        parts: list[str] = []
        for item in value:
            if isinstance(item, dict):
                direct_text = item.get("text")
                if isinstance(direct_text, str):
                    parts.append(direct_text)
                    continue

                if isinstance(direct_text, dict):
                    nested_value = direct_text.get("value")
                    if isinstance(nested_value, str):
                        parts.append(nested_value)
                        continue

                content_value = item.get("content")
                if isinstance(content_value, str):
                    parts.append(content_value)

        merged = "".join(parts).strip()
        return merged or None

    return None
