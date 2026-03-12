# Shared Event Schema Documentation (v1)

This contract is surface-agnostic and shared by iPhone now, with CarPlay and Watch reserved.

## Envelope
- `version`: protocol version (`1.0`)
- `event_id`: unique id per event
- `timestamp`: ISO-8601 UTC
- `session_id`: stable conversation id
- `surface`: `iphone | carplay | watch`
- `type`: event name
- `payload`: event-specific object

## Event categories
- Session: `session.start`, `session.end`
- Transcript stream: `transcript.partial`, `transcript.final`
- Assistant stream: `assistant.thinking`, `assistant.response.chunk`, `assistant.response.final`
- Safety: `action.proposed`, `action.confirmation_required`
- Error: `error`

## Session auth (optional)
- `session.start.payload.auth_token` can carry a shared password.
- Backend validates it when `LISAMINDBLADE_SHARED_TOKEN` is configured.

## Structured action requirements
Every `action.proposed` payload includes:
- `action_type`
- `parameters`
- `risk`
- `requires_confirmation`

Supported `action_type` values:
- `navigate_to_destination`
- `send_message`
- `create_reminder`
- `summarize_notifications`
- `call_contact`
- `open_garage`

## Decoupling rule
Surfaces only emit and consume these events. They do not embed backend business logic.
The backend only depends on event contracts, not surface-specific UI details.
