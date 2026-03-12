import asyncio

from app.assistant.openclaw_client import OpenClawClientError, extract_assistant_text
from app.assistant.openclaw_engine import OpenClawAssistantEngine
from app.domain.protocol import (
    AssistantResponseChunkResponse,
    AssistantResponseFinalResponse,
    AssistantThinkingResponse,
    ErrorResponse,
    Surface,
    TranscriptFinalRequest,
    TranscriptPayload,
)


class _FakeSuccessClient:
    async def complete(self, *, session_id: str, user_text: str) -> str:
        return f"Lisa response for: {user_text}"


class _FakeFailingClient:
    async def complete(self, *, session_id: str, user_text: str) -> str:
        raise OpenClawClientError("simulated provider failure")


def _run_engine(engine: OpenClawAssistantEngine, text: str) -> list[object]:
    async def run() -> list[object]:
        event = TranscriptFinalRequest(
            session_id="session-1",
            surface=Surface.IPHONE,
            payload=TranscriptPayload(text=text),
        )
        return [item async for item in engine.handle_event(event)]

    return asyncio.run(run())


def test_openclaw_engine_streams_thinking_chunk_and_final() -> None:
    engine = OpenClawAssistantEngine(client=_FakeSuccessClient(), chunk_chars=24)
    output = _run_engine(engine, "hello lisa")

    assert any(isinstance(item, AssistantThinkingResponse) for item in output)
    assert any(isinstance(item, AssistantResponseChunkResponse) for item in output)
    assert any(isinstance(item, AssistantResponseFinalResponse) for item in output)


def test_openclaw_engine_emits_error_when_provider_fails() -> None:
    engine = OpenClawAssistantEngine(client=_FakeFailingClient())
    output = _run_engine(engine, "hello lisa")

    error_event = next(item for item in output if isinstance(item, ErrorResponse))
    assert error_event.payload.code == "openclaw_request_failed"


def test_extract_assistant_text_accepts_openai_compatible_shape() -> None:
    response_obj = {
        "choices": [
            {
                "message": {
                    "content": [
                        {"type": "text", "text": "Hello "},
                        {"type": "text", "text": "from Lisa"},
                    ]
                }
            }
        ]
    }
    assert extract_assistant_text(response_obj) == "Hello from Lisa"


def test_extract_assistant_text_accepts_output_text_shape() -> None:
    response_obj = {"output_text": "Short answer"}
    assert extract_assistant_text(response_obj) == "Short answer"
