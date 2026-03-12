from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any
from uuid import uuid4

from pydantic import BaseModel, Field


class ActionRisk(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class ActionType(StrEnum):
    NAVIGATE_TO_DESTINATION = "navigate_to_destination"
    SEND_MESSAGE = "send_message"
    CREATE_REMINDER = "create_reminder"
    SUMMARIZE_NOTIFICATIONS = "summarize_notifications"
    CALL_CONTACT = "call_contact"
    OPEN_GARAGE = "open_garage"


class NavigateToDestinationParameters(BaseModel):
    destination: str = Field(min_length=1, max_length=200)


class SendMessageParameters(BaseModel):
    recipient: str = Field(min_length=1, max_length=120)
    message: str = Field(min_length=1, max_length=500)


class CreateReminderParameters(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    due_at_iso: str | None = Field(default=None, max_length=64)


class SummarizeNotificationsParameters(BaseModel):
    window_minutes: int = Field(default=120, ge=1, le=1440)


class CallContactParameters(BaseModel):
    contact_name: str = Field(min_length=1, max_length=120)


class OpenGarageParameters(BaseModel):
    door_id: str = Field(default="main", min_length=1, max_length=64)


ActionParameters = (
    NavigateToDestinationParameters
    | SendMessageParameters
    | CreateReminderParameters
    | SummarizeNotificationsParameters
    | CallContactParameters
    | OpenGarageParameters
)


ACTION_PARAMETER_MODEL: dict[ActionType, type[BaseModel]] = {
    ActionType.NAVIGATE_TO_DESTINATION: NavigateToDestinationParameters,
    ActionType.SEND_MESSAGE: SendMessageParameters,
    ActionType.CREATE_REMINDER: CreateReminderParameters,
    ActionType.SUMMARIZE_NOTIFICATIONS: SummarizeNotificationsParameters,
    ActionType.CALL_CONTACT: CallContactParameters,
    ActionType.OPEN_GARAGE: OpenGarageParameters,
}


ACTION_DEFAULTS: dict[ActionType, tuple[ActionRisk, bool]] = {
    ActionType.NAVIGATE_TO_DESTINATION: (ActionRisk.LOW, False),
    ActionType.SEND_MESSAGE: (ActionRisk.MEDIUM, True),
    ActionType.CREATE_REMINDER: (ActionRisk.LOW, False),
    ActionType.SUMMARIZE_NOTIFICATIONS: (ActionRisk.LOW, False),
    ActionType.CALL_CONTACT: (ActionRisk.MEDIUM, True),
    ActionType.OPEN_GARAGE: (ActionRisk.HIGH, True),
}


def action_defaults(action_type: ActionType) -> tuple[ActionRisk, bool]:
    return ACTION_DEFAULTS[action_type]


def parameters_match_action_type(action_type: ActionType, parameters: Any) -> bool:
    model = ACTION_PARAMETER_MODEL[action_type]
    return isinstance(parameters, model)


@dataclass(frozen=True)
class ProposedAction:
    """Structured action proposal from assistant to client."""

    action_type: ActionType
    parameters: ActionParameters
    title: str
    summary: str
    risk: ActionRisk
    requires_confirmation: bool
    action_id: str = field(default_factory=lambda: str(uuid4()))

    @classmethod
    def build(
        cls,
        *,
        action_type: ActionType,
        parameters: ActionParameters,
        title: str,
        summary: str,
        risk: ActionRisk | None = None,
        requires_confirmation: bool | None = None,
    ) -> "ProposedAction":
        default_risk, default_requires_confirmation = action_defaults(action_type)
        return cls(
            action_type=action_type,
            parameters=parameters,
            title=title,
            summary=summary,
            risk=risk or default_risk,
            requires_confirmation=(
                requires_confirmation
                if requires_confirmation is not None
                else default_requires_confirmation
            ),
        )
