from __future__ import annotations

from collections.abc import AsyncIterator

from app.assistant.base import AssistantEngine
from app.domain.assistant_turn import AssistantTurn
from app.domain.proposed_action import (
    ActionType,
    CallContactParameters,
    CreateReminderParameters,
    NavigateToDestinationParameters,
    OpenGarageParameters,
    ProposedAction,
    SendMessageParameters,
    SummarizeNotificationsParameters,
)
from app.domain.protocol import (
    ActionConfirmationRequiredPayload,
    ActionConfirmationRequiredResponse,
    ActionProposedPayload,
    ActionProposedResponse,
    AssistantResponseChunkPayload,
    AssistantResponseChunkResponse,
    AssistantResponseFinalPayload,
    AssistantResponseFinalResponse,
    AssistantThinkingPayload,
    AssistantThinkingResponse,
    ClientEvent,
    ServerEvent,
    TranscriptFinalRequest,
)


class StubAssistantEngine(AssistantEngine):
    """Stub engine used for local development and protocol testing."""

    async def handle_event(self, event: ClientEvent) -> AsyncIterator[ServerEvent]:
        if not isinstance(event, TranscriptFinalRequest):
            return

        text = event.payload.text
        turn = AssistantTurn(
            session_id=event.session_id,
            user_text=text,
            assistant_text=text,
        )

        yield AssistantThinkingResponse(
            session_id=event.session_id,
            surface=event.surface,
            payload=AssistantThinkingPayload(message="Processing transcript..."),
        )

        action = self._infer_action(text)
        if action is not None:
            yield ActionProposedResponse(
                session_id=event.session_id,
                surface=event.surface,
                payload=ActionProposedPayload(
                    action_id=action.action_id,
                    action_type=action.action_type,
                    parameters=action.parameters,
                    title=action.title,
                    summary=action.summary,
                    risk=action.risk,
                    requires_confirmation=action.requires_confirmation,
                ),
            )
            if action.requires_confirmation:
                yield ActionConfirmationRequiredResponse(
                    session_id=event.session_id,
                    surface=event.surface,
                    payload=ActionConfirmationRequiredPayload(
                        action_id=action.action_id,
                        reason="This action requires explicit confirmation.",
                    ),
                )

        yield AssistantResponseChunkResponse(
            session_id=event.session_id,
            surface=event.surface,
            payload=AssistantResponseChunkPayload(
                turn_id=turn.turn_id,
                text=turn.assistant_text,
            ),
        )

        yield AssistantResponseFinalResponse(
            session_id=event.session_id,
            surface=event.surface,
            payload=AssistantResponseFinalPayload(
                turn_id=turn.turn_id,
                text=text,
            ),
        )

    def _infer_action(self, text: str) -> ProposedAction | None:
        lowered = text.lower()

        if "garage" in lowered:
            return ProposedAction.build(
                action_type=ActionType.OPEN_GARAGE,
                parameters=OpenGarageParameters(),
                title="Open garage",
                summary="Open the main garage door.",
            )

        if "call" in lowered:
            contact = self._extract_after_token(text, "call", fallback="Unknown contact")
            return ProposedAction.build(
                action_type=ActionType.CALL_CONTACT,
                parameters=CallContactParameters(contact_name=contact),
                title="Call contact",
                summary=f"Call {contact}.",
            )

        if "notification" in lowered and "summar" in lowered:
            return ProposedAction.build(
                action_type=ActionType.SUMMARIZE_NOTIFICATIONS,
                parameters=SummarizeNotificationsParameters(window_minutes=120),
                title="Summarize notifications",
                summary="Summarize recent notifications from the last 2 hours.",
            )

        if "remind" in lowered:
            reminder_title = self._extract_after_token(text, "remind me to", fallback=text)
            return ProposedAction.build(
                action_type=ActionType.CREATE_REMINDER,
                parameters=CreateReminderParameters(title=reminder_title),
                title="Create reminder",
                summary=f"Create reminder: {reminder_title}",
            )

        if "message" in lowered or "text" in lowered:
            recipient = self._extract_after_token(text, "to", fallback="Unknown recipient")
            return ProposedAction.build(
                action_type=ActionType.SEND_MESSAGE,
                parameters=SendMessageParameters(
                    recipient=recipient,
                    message=text,
                ),
                title="Send message",
                summary=f"Send message to {recipient}.",
            )

        if "navigate" in lowered or "directions" in lowered:
            destination = self._extract_after_token(text, "to", fallback="Unknown destination")
            return ProposedAction.build(
                action_type=ActionType.NAVIGATE_TO_DESTINATION,
                parameters=NavigateToDestinationParameters(destination=destination),
                title="Navigate to destination",
                summary=f"Start navigation to {destination}.",
            )

        return None

    @staticmethod
    def _extract_after_token(text: str, token: str, fallback: str) -> str:
        lowered = text.lower()
        index = lowered.find(token)
        if index == -1:
            return fallback

        extracted = text[index + len(token) :].strip(" :,-")
        return extracted or fallback


# Backward-compatible alias for older imports.
StubAssistantService = StubAssistantEngine
