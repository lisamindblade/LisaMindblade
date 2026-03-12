import asyncio
import subprocess

import pytest

from app.assistant.openclaw_client import CLIOpenClawClient, OpenClawCLIConfig, OpenClawClientError


def test_cli_client_extracts_text_from_json_output() -> None:
    def runner(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout='{"payloads":[{"text":"hello from openclaw"}]}',
            stderr="gateway connect failed: pairing required",
        )

    client = CLIOpenClawClient(OpenClawCLIConfig(), runner=runner)
    result = asyncio.run(client.complete(session_id="session-1", user_text="hello"))
    assert result == "hello from openclaw"


def test_cli_client_parses_json_with_leading_logs() -> None:
    def runner(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            args=command,
            returncode=0,
            stdout='notice: fallback used\n{"payloads":[{"text":"final answer"}]}',
            stderr="",
        )

    client = CLIOpenClawClient(OpenClawCLIConfig(), runner=runner)
    result = asyncio.run(client.complete(session_id="session-1", user_text="hello"))
    assert result == "final answer"


def test_cli_client_raises_when_json_missing() -> None:
    def runner(command: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(args=command, returncode=1, stdout="", stderr="boom")

    client = CLIOpenClawClient(OpenClawCLIConfig(), runner=runner)
    with pytest.raises(OpenClawClientError):
        asyncio.run(client.complete(session_id="session-1", user_text="hello"))
