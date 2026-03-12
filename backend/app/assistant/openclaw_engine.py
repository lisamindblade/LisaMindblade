from __future__ import annotations

from collections.abc import AsyncIterator

from app.assistant.base import AssistantEngine
from app.assistant.openclaw_client import OpenClawClient, OpenClawClientError
from app.domain.assistant_turn import AssistantTurn
from app.domain.protocol import (
    AssistantResponseChunkPayload,
    AssistantResponseChunkResponse,
    AssistantResponseFinalPayload,
    AssistantResponseFinalResponse,
    AssistantThinkingPayload,
    AssistantThinkingResponse,
    ClientEvent,
    ServerEvent,
    TranscriptFinalRequest,
    build_error_response,
)


class OpenClawAssistantEngine(AssistantEngine):
    """OpenClaw-backed engine boundary behind the AssistantEngine interface."""

    def __init__(self, client: OpenClawClient, *, chunk_chars: int = 160) -> None:
        self.client = client
        self.chunk_chars = max(40, chunk_chars)

    async def handle_event(self, event: ClientEvent) -> AsyncIterator[ServerEvent]:
        if not isinstance(event, TranscriptFinalRequest):
            return

        yield AssistantThinkingResponse(
            session_id=event.session_id,
            surface=event.surface,
            payload=AssistantThinkingPayload(message="Lisa is thinking..."),
        )

        try:
            completion = await self.client.complete(
                session_id=event.session_id,
                user_text=event.payload.text,
            )
        except OpenClawClientError as exc:
            yield build_error_response(
                session_id=event.session_id,
                surface=event.surface,
                code="openclaw_request_failed",
                message=str(exc),
                details={"engine": "openclaw"},
            )
            return

        turn = AssistantTurn(
            session_id=event.session_id,
            user_text=event.payload.text,
            assistant_text=completion,
        )

        for chunk_text in _chunk_text(completion, max_chars=self.chunk_chars):
            yield AssistantResponseChunkResponse(
                session_id=event.session_id,
                surface=event.surface,
                payload=AssistantResponseChunkPayload(
                    turn_id=turn.turn_id,
                    text=chunk_text,
                ),
            )

        yield AssistantResponseFinalResponse(
            session_id=event.session_id,
            surface=event.surface,
            payload=AssistantResponseFinalPayload(
                turn_id=turn.turn_id,
                text=completion,
            ),
        )


def _chunk_text(text: str, *, max_chars: int) -> list[str]:
    normalized = " ".join(text.split())
    if len(normalized) <= max_chars:
        return [normalized]

    chunks: list[str] = []
    cursor = 0
    target_soft_boundary = max(20, int(max_chars * 0.6))

    while cursor < len(normalized):
        end = min(cursor + max_chars, len(normalized))
        if end < len(normalized):
            split_at = normalized.rfind(" ", cursor + target_soft_boundary, end)
            if split_at > cursor:
                end = split_at

        chunk = normalized[cursor:end].strip()
        if chunk:
            chunks.append(chunk)

        cursor = end
        while cursor < len(normalized) and normalized[cursor] == " ":
            cursor += 1

    return chunks or [normalized]
