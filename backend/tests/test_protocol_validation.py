import pytest
from pydantic import ValidationError

from app.domain.proposed_action import (
    ActionType,
    NavigateToDestinationParameters,
    SendMessageParameters,
)
from app.domain.protocol import (
    ActionProposedPayload,
    SessionStartRequest,
    Surface,
    parse_client_event,
    parse_client_event_obj,
)


def test_parse_session_start_valid_json() -> None:
    payload = """
    {
      "version": "1.0",
      "event_id": "evt-1",
      "timestamp": "2026-03-12T18:00:00Z",
      "session_id": "session-1",
      "surface": "iphone",
      "type": "session.start",
      "payload": {
        "client_version": "0.1.0"
      }
    }
    """

    event = parse_client_event(payload)
    assert isinstance(event, SessionStartRequest)
    assert event.surface == Surface.IPHONE


def test_parse_session_start_normalizes_auth_token() -> None:
    event = parse_client_event_obj(
        {
            "version": "1.0",
            "event_id": "evt-auth",
            "timestamp": "2026-03-12T18:00:00Z",
            "session_id": "session-1",
            "surface": "iphone",
            "type": "session.start",
            "payload": {"client_version": "0.1.0", "auth_token": "  secret  "},
        }
    )
    assert isinstance(event, SessionStartRequest)
    assert event.payload.auth_token == "secret"


def test_parse_transcript_partial_rejects_blank_text() -> None:
    with pytest.raises(ValidationError):
        parse_client_event_obj(
            {
                "version": "1.0",
                "event_id": "evt-2",
                "timestamp": "2026-03-12T18:00:00Z",
                "session_id": "session-1",
                "surface": "iphone",
                "type": "transcript.partial",
                "payload": {"text": "   "},
            }
        )


def test_action_payload_validates_matching_parameters() -> None:
    payload = ActionProposedPayload(
        action_id="action-1",
        action_type=ActionType.SEND_MESSAGE,
        parameters=SendMessageParameters(recipient="Alex", message="Running late"),
        title="Send message",
        summary="Send a message to Alex",
    )

    assert payload.action_type == ActionType.SEND_MESSAGE


def test_action_payload_rejects_parameter_type_mismatch() -> None:
    with pytest.raises(ValidationError):
        ActionProposedPayload(
            action_id="action-2",
            action_type=ActionType.SEND_MESSAGE,
            parameters=NavigateToDestinationParameters(destination="Home"),
            title="Bad action",
            summary="Mismatched parameters",
        )
