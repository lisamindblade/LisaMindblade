from __future__ import annotations

import asyncio
import logging
import secrets
from dataclasses import dataclass, field
from typing import Any

import websockets
from pydantic import ValidationError
from websockets.exceptions import ConnectionClosed

from app.assistant.base import AssistantEngine
from app.core.config import AppConfig
from app.domain.protocol import (
    AssistantResponseChunkResponse,
    AssistantResponseFinalResponse,
    ClientEvent,
    SessionEndPayload,
    SessionEndRequest,
    SessionEndResponse,
    SessionStartRequest,
    Surface,
    TranscriptFinalRequest,
    TranscriptPartialRequest,
    build_error_response,
    parse_client_event,
    serialize_server_event,
)
from app.voice.transcript_ingestion import TranscriptIngestionService
from app.voice.tts import TTSService


def tokens_match(expected_token: str | None, provided_token: str | None) -> bool:
    expected = (expected_token or "").strip()
    if not expected:
        return True
    provided = (provided_token or "").strip()
    if not provided:
        return False
    return secrets.compare_digest(provided, expected)


@dataclass
class WebSocketServer:
    config: AppConfig
    assistant: AssistantEngine
    transcript_ingestion: TranscriptIngestionService
    tts_service: TTSService
    logger: logging.Logger = field(default_factory=lambda: logging.getLogger(__name__))

    async def run(self) -> None:
        self.logger.info(
            "Starting WebSocket server",
            extra={"host": self.config.host, "port": self.config.port},
        )
        async with websockets.serve(self._handle_connection, self.config.host, self.config.port):
            await asyncio.Future()

    async def _handle_connection(self, websocket: Any) -> None:
        session_id: str | None = None
        surface = Surface.IPHONE
        session_ended = False

        try:
            async for raw_message in websocket:
                if not isinstance(raw_message, str):
                    await self._send_error(
                        websocket,
                        session_id=session_id or "unknown",
                        surface=surface,
                        code="invalid_frame",
                        message="Expected a text WebSocket frame.",
                    )
                    continue

                try:
                    event = parse_client_event(raw_message)
                except ValidationError as exc:
                    await self._send_error(
                        websocket,
                        session_id=session_id or "unknown",
                        surface=surface,
                        code="validation_error",
                        message="Invalid client event payload.",
                        details={"errors": exc.errors(include_url=False)},
                    )
                    continue

                if session_id is None:
                    if not isinstance(event, SessionStartRequest):
                        await self._send_error(
                            websocket,
                            session_id="unknown",
                            surface=surface,
                            code="session_not_started",
                            message="First event must be session.start.",
                        )
                        continue

                    session_id = event.session_id
                    surface = event.surface
                    if not tokens_match(self.config.shared_token, event.payload.auth_token):
                        self.logger.warning(
                            "Rejected connection because auth token is invalid",
                            extra={"session_id": session_id, "surface": surface.value},
                        )
                        await self._send_error(
                            websocket,
                            session_id=session_id,
                            surface=surface,
                            code="auth_failed",
                            message="Authentication failed. Check backend password.",
                        )
                        session_ended = True
                        await websocket.close(code=1008, reason="auth_failed")
                        break
                    continue

                if event.session_id != session_id:
                    await self._send_error(
                        websocket,
                        session_id=session_id,
                        surface=surface,
                        code="session_mismatch",
                        message="Event session_id does not match active session.",
                    )
                    continue

                if isinstance(event, SessionStartRequest):
                    await self._send_error(
                        websocket,
                        session_id=session_id,
                        surface=surface,
                        code="duplicate_session_start",
                        message="session.start already received for this connection.",
                    )
                    continue

                if isinstance(event, SessionEndRequest):
                    await self._send_event(
                        websocket,
                        SessionEndResponse(
                            session_id=session_id,
                            surface=surface,
                            payload=SessionEndPayload(
                                reason=event.payload.reason or "client_requested_end"
                            ),
                        ),
                    )
                    session_ended = True
                    break

                await self._handle_assistant_event(websocket, event, session_id, surface)
        except ConnectionClosed:
            self.logger.info("Connection closed", extra={"session_id": session_id})
        finally:
            if session_id and not session_ended:
                await self._close_session(websocket, session_id, surface)

    async def _handle_assistant_event(
        self,
        websocket: Any,
        event: ClientEvent,
        session_id: str,
        surface: Surface,
    ) -> None:
        if not isinstance(event, (TranscriptPartialRequest, TranscriptFinalRequest)):
            await self._send_error(
                websocket,
                session_id=session_id,
                surface=surface,
                code="unsupported_event",
                message=f"Event '{event.type}' is not supported after session.start.",
            )
            return

        normalized_text = await self.transcript_ingestion.ingest(
            session_id=session_id,
            text=event.payload.text,
            is_final=isinstance(event, TranscriptFinalRequest),
        )

        if isinstance(event, TranscriptPartialRequest):
            event = TranscriptPartialRequest(
                version=event.version,
                event_id=event.event_id,
                timestamp=event.timestamp,
                session_id=event.session_id,
                surface=event.surface,
                payload=event.payload.model_copy(update={"text": normalized_text}),
            )
        else:
            event = TranscriptFinalRequest(
                version=event.version,
                event_id=event.event_id,
                timestamp=event.timestamp,
                session_id=event.session_id,
                surface=event.surface,
                payload=event.payload.model_copy(update={"text": normalized_text}),
            )

        if isinstance(event, TranscriptPartialRequest):
            return

        try:
            async for response in self.assistant.handle_event(event):
                await self._send_event(websocket, response)
                await self._maybe_send_tts(response)
        except Exception as exc:  # pragma: no cover
            self.logger.exception("Assistant processing failure")
            await self._send_error(
                websocket,
                session_id=session_id,
                surface=surface,
                code="assistant_failure",
                message="Assistant failed to process transcript.",
                details={"error": str(exc)},
            )

    async def _maybe_send_tts(self, response: Any) -> None:
        if isinstance(response, AssistantResponseChunkResponse):
            await self.tts_service.speak(
                session_id=response.session_id,
                text=response.payload.text,
                is_final=False,
            )
        elif isinstance(response, AssistantResponseFinalResponse):
            await self.tts_service.speak(
                session_id=response.session_id,
                text=response.payload.text,
                is_final=True,
            )

    async def _close_session(self, websocket: Any, session_id: str, surface: Surface) -> None:
        try:
            await self._send_event(
                websocket,
                SessionEndResponse(
                    session_id=session_id,
                    surface=surface,
                    payload=SessionEndPayload(reason="connection_closed"),
                ),
            )
        except Exception:
            return

    async def _send_event(self, websocket: Any, event: Any) -> None:
        await websocket.send(serialize_server_event(event))

    async def _send_error(
        self,
        websocket: Any,
        *,
        session_id: str,
        surface: Surface,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
    ) -> None:
        error_event = build_error_response(
            session_id=session_id,
            surface=surface,
            code=code,
            message=message,
            details=details,
        )
        await self._send_event(websocket, error_event)
