import asyncio

import pytest

from app.assistant.stub import StubAssistantService
from app.domain.proposed_action import ActionType
from app.domain.protocol import (
    ActionConfirmationRequiredResponse,
    ActionProposedResponse,
    AssistantResponseFinalResponse,
    AssistantThinkingResponse,
    Surface,
    TranscriptFinalRequest,
    TranscriptPayload,
)


def _run_event(text: str) -> list[object]:
    assistant = StubAssistantService()

    async def run() -> list[object]:
        event = TranscriptFinalRequest(
            session_id="test-session",
            surface=Surface.IPHONE,
            payload=TranscriptPayload(text=text),
        )
        return [item async for item in assistant.handle_event(event)]

    return asyncio.run(run())


def test_stub_assistant_streams_final_response() -> None:
    output = _run_event("Hello Lisa")
    assert any(isinstance(item, AssistantThinkingResponse) for item in output)
    assert any(isinstance(item, AssistantResponseFinalResponse) for item in output)


@pytest.mark.parametrize(
    ("text", "expected_action_type", "requires_confirmation"),
    [
        ("Navigate to 1 Infinite Loop", ActionType.NAVIGATE_TO_DESTINATION, False),
        ("Send a message to Alex", ActionType.SEND_MESSAGE, True),
        ("Remind me to pick up milk", ActionType.CREATE_REMINDER, False),
        ("Summarize notifications", ActionType.SUMMARIZE_NOTIFICATIONS, False),
        ("Call Jordan", ActionType.CALL_CONTACT, True),
        ("Open garage", ActionType.OPEN_GARAGE, True),
    ],
)
def test_stub_assistant_infers_structured_actions(
    text: str,
    expected_action_type: ActionType,
    requires_confirmation: bool,
) -> None:
    output = _run_event(text)

    action_event = next(
        item for item in output if isinstance(item, ActionProposedResponse)
    )
    assert action_event.payload.action_type == expected_action_type
    assert action_event.payload.requires_confirmation is requires_confirmation

    has_confirmation_event = any(
        isinstance(item, ActionConfirmationRequiredResponse) for item in output
    )
    assert has_confirmation_event is requires_confirmation
