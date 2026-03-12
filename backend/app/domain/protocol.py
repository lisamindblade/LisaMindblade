from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Annotated, Any, Literal, TypeAlias
from uuid import uuid4

from pydantic import BaseModel, Field, TypeAdapter, field_validator, model_validator

from app.domain.proposed_action import (
    ActionParameters,
    ActionRisk,
    ActionType,
    parameters_match_action_type,
)


class Surface(StrEnum):
    IPHONE = "iphone"
    CARPLAY = "carplay"
    WATCH = "watch"


class ClientEventType(StrEnum):
    SESSION_START = "session.start"
    TRANSCRIPT_PARTIAL = "transcript.partial"
    TRANSCRIPT_FINAL = "transcript.final"
    SESSION_END = "session.end"


class ServerEventType(StrEnum):
    ASSISTANT_THINKING = "assistant.thinking"
    ASSISTANT_RESPONSE_CHUNK = "assistant.response.chunk"
    ASSISTANT_RESPONSE_FINAL = "assistant.response.final"
    ACTION_PROPOSED = "action.proposed"
    ACTION_CONFIRMATION_REQUIRED = "action.confirmation_required"
    SESSION_END = "session.end"
    ERROR = "error"


class SessionStartPayload(BaseModel):
    client_version: str | None = Field(default=None, max_length=32)
    device_id: str | None = Field(default=None, max_length=128)
    auth_token: str | None = Field(default=None, max_length=256)

    @field_validator("auth_token")
    @classmethod
    def normalize_auth_token(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None


class TranscriptPayload(BaseModel):
    text: str = Field(min_length=1, max_length=4000)

    @field_validator("text")
    @classmethod
    def validate_text(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("text must not be blank")
        return normalized


class SessionEndPayload(BaseModel):
    reason: str | None = Field(default=None, max_length=200)


class AssistantThinkingPayload(BaseModel):
    message: str = Field(default="Thinking...", max_length=200)


class AssistantResponseChunkPayload(BaseModel):
    turn_id: str = Field(min_length=1)
    text: str = Field(min_length=1, max_length=4000)


class AssistantResponseFinalPayload(BaseModel):
    turn_id: str = Field(min_length=1)
    text: str = Field(min_length=1, max_length=4000)


class ActionProposedPayload(BaseModel):
    action_id: str = Field(min_length=1)
    action_type: ActionType
    parameters: ActionParameters
    title: str = Field(min_length=1, max_length=120)
    summary: str = Field(min_length=1, max_length=1000)
    risk: ActionRisk = ActionRisk.MEDIUM
    requires_confirmation: bool = True

    @model_validator(mode="after")
    def validate_parameters_shape(self) -> "ActionProposedPayload":
        if not parameters_match_action_type(self.action_type, self.parameters):
            raise ValueError("parameters do not match action_type")
        return self


class ActionConfirmationRequiredPayload(BaseModel):
    action_id: str = Field(min_length=1)
    reason: str = Field(min_length=1, max_length=500)


class ErrorPayload(BaseModel):
    code: str = Field(min_length=1, max_length=64)
    message: str = Field(min_length=1, max_length=500)
    details: dict[str, Any] | None = None


class BaseEnvelope(BaseModel):
    version: Literal["1.0"] = "1.0"
    event_id: str = Field(default_factory=lambda: str(uuid4()), min_length=1)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    session_id: str = Field(min_length=1)
    surface: Surface


class SessionStartRequest(BaseEnvelope):
    type: Literal["session.start"] = "session.start"
    payload: SessionStartPayload = Field(default_factory=SessionStartPayload)


class TranscriptPartialRequest(BaseEnvelope):
    type: Literal["transcript.partial"] = "transcript.partial"
    payload: TranscriptPayload


class TranscriptFinalRequest(BaseEnvelope):
    type: Literal["transcript.final"] = "transcript.final"
    payload: TranscriptPayload


class SessionEndRequest(BaseEnvelope):
    type: Literal["session.end"] = "session.end"
    payload: SessionEndPayload = Field(default_factory=SessionEndPayload)


class AssistantThinkingResponse(BaseEnvelope):
    type: Literal["assistant.thinking"] = "assistant.thinking"
    payload: AssistantThinkingPayload


class AssistantResponseChunkResponse(BaseEnvelope):
    type: Literal["assistant.response.chunk"] = "assistant.response.chunk"
    payload: AssistantResponseChunkPayload


class AssistantResponseFinalResponse(BaseEnvelope):
    type: Literal["assistant.response.final"] = "assistant.response.final"
    payload: AssistantResponseFinalPayload


class ActionProposedResponse(BaseEnvelope):
    type: Literal["action.proposed"] = "action.proposed"
    payload: ActionProposedPayload


class ActionConfirmationRequiredResponse(BaseEnvelope):
    type: Literal["action.confirmation_required"] = "action.confirmation_required"
    payload: ActionConfirmationRequiredPayload


class SessionEndResponse(BaseEnvelope):
    type: Literal["session.end"] = "session.end"
    payload: SessionEndPayload = Field(default_factory=SessionEndPayload)


class ErrorResponse(BaseEnvelope):
    type: Literal["error"] = "error"
    payload: ErrorPayload


ClientEvent: TypeAlias = Annotated[
    SessionStartRequest
    | TranscriptPartialRequest
    | TranscriptFinalRequest
    | SessionEndRequest,
    Field(discriminator="type"),
]

ServerEvent: TypeAlias = Annotated[
    AssistantThinkingResponse
    | AssistantResponseChunkResponse
    | AssistantResponseFinalResponse
    | ActionProposedResponse
    | ActionConfirmationRequiredResponse
    | SessionEndResponse
    | ErrorResponse,
    Field(discriminator="type"),
]

_CLIENT_EVENT_ADAPTER = TypeAdapter(ClientEvent)


def parse_client_event(raw_json: str) -> ClientEvent:
    return _CLIENT_EVENT_ADAPTER.validate_json(raw_json)


def parse_client_event_obj(raw_obj: dict[str, Any]) -> ClientEvent:
    return _CLIENT_EVENT_ADAPTER.validate_python(raw_obj)


def serialize_server_event(event: ServerEvent) -> str:
    return event.model_dump_json()


def build_error_response(
    *,
    session_id: str,
    surface: Surface,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
) -> ErrorResponse:
    return ErrorResponse(
        session_id=session_id,
        surface=surface,
        payload=ErrorPayload(code=code, message=message, details=details),
    )
