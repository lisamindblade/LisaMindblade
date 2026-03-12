from __future__ import annotations

from app.assistant.base import AssistantEngine
from app.assistant.openclaw_client import (
    CLIOpenClawClient,
    HTTPOpenClawClient,
    OpenClawClient,
    OpenClawCLIConfig,
    OpenClawClientConfig,
)
from app.assistant.openclaw_engine import OpenClawAssistantEngine
from app.assistant.stub import StubAssistantEngine


def build_assistant_engine(
    engine_name: str,
    *,
    openclaw_config: OpenClawClientConfig | None = None,
    openclaw_cli_config: OpenClawCLIConfig | None = None,
    openclaw_client_mode: str = "cli",
    openclaw_client: OpenClawClient | None = None,
    openclaw_chunk_chars: int = 160,
) -> AssistantEngine:
    normalized = engine_name.strip().lower()

    if normalized == "stub":
        return StubAssistantEngine()
    if normalized == "openclaw":
        if openclaw_client is not None:
            client = openclaw_client
        else:
            mode = openclaw_client_mode.strip().lower()
            if mode == "cli":
                client = CLIOpenClawClient(
                    openclaw_cli_config
                    or OpenClawCLIConfig(
                        command="openclaw",
                        agent_id="main",
                        timeout_seconds=120,
                        use_local=False,
                    )
                )
            elif mode == "http":
                client = HTTPOpenClawClient(
                    openclaw_config
                    or OpenClawClientConfig(
                        base_url="http://127.0.0.1:8000",
                        chat_path="/v1/chat/completions",
                        model="openclaw",
                    )
                )
            else:
                raise ValueError(
                    "Unsupported OpenClaw client mode. Expected 'cli' or 'http'. "
                    f"Got: '{openclaw_client_mode}'."
                )

        return OpenClawAssistantEngine(client=client, chunk_chars=openclaw_chunk_chars)

    raise ValueError(
        "Unsupported assistant engine. Expected one of: 'stub', 'openclaw'. "
        f"Got: '{engine_name}'."
    )
