# LisaMindblade API Spec (v1)

## Transport
- Protocol: WebSocket
- Message format: JSON envelope

## Envelope (all events)
```json
{
  "version": "1.0",
  "event_id": "uuid",
  "timestamp": "2026-03-12T17:00:00Z",
  "session_id": "uuid",
  "surface": "iphone",
  "type": "session.start",
  "payload": {}
}
```

## Surface values
- `iphone`
- `carplay` (reserved)
- `watch` (reserved)

## Client -> Backend events
- `session.start`
  - payload: `{ "client_version"?: string, "device_id"?: string, "auth_token"?: string }`
- `transcript.partial`
  - payload: `{ "text": string }` (required, non-blank)
- `transcript.final`
  - payload: `{ "text": string }` (required, non-blank)
- `session.end`
  - payload: `{ "reason"?: string }`

## Backend -> Client events
- `assistant.thinking`
  - payload: `{ "message": string }`
- `assistant.response.chunk`
  - payload: `{ "turn_id": string, "text": string }`
- `assistant.response.final`
  - payload: `{ "turn_id": string, "text": string }`
- `action.proposed`
  - payload:
    - `action_id`: string
    - `action_type`: `navigate_to_destination | send_message | create_reminder | summarize_notifications | call_contact | open_garage`
    - `parameters`: object (shape depends on `action_type`)
    - `title`: string
    - `summary`: string
    - `risk`: `low | medium | high`
    - `requires_confirmation`: boolean
- `action.confirmation_required`
  - payload: `{ "action_id": string, "reason": string }`
- `session.end`
  - payload: `{ "reason"?: string }`
- `error`
  - payload: `{ "code": string, "message": string, "details"?: object }`

## Structured action types
- `navigate_to_destination`
  - parameters: `{ "destination": string }`
  - default risk: `low`
  - default confirmation: `false`
- `send_message`
  - parameters: `{ "recipient": string, "message": string }`
  - default risk: `medium`
  - default confirmation: `true`
- `create_reminder`
  - parameters: `{ "title": string, "due_at_iso"?: string }`
  - default risk: `low`
  - default confirmation: `false`
- `summarize_notifications`
  - parameters: `{ "window_minutes": integer }`
  - default risk: `low`
  - default confirmation: `false`
- `call_contact`
  - parameters: `{ "contact_name": string }`
  - default risk: `medium`
  - default confirmation: `true`
- `open_garage`
  - parameters: `{ "door_id": string }`
  - default risk: `high`
  - default confirmation: `true`

## Validation rules
- First client message must be `session.start`
- `session_id` must stay consistent per connection
- Transcript text is trimmed; blank text is rejected
- Unknown or invalid envelopes return `error`
- `action.proposed.parameters` must match `action_type`
- `session.start` establishes context; it does not guarantee an immediate backend event
- If backend `LISAMINDBLADE_SHARED_TOKEN` is configured, `session.start.payload.auth_token`
  must match or backend emits `error` (`code=auth_failed`) and closes the connection.

## Voice-first behavior
1. Client opens session (`session.start`)
2. Client streams `transcript.partial` and `transcript.final`
3. Backend emits `assistant.thinking`
4. Backend streams `assistant.response.chunk` then terminal `assistant.response.final`
5. Side effects emit structured `action.proposed`
6. Confirmation-sensitive actions emit `action.confirmation_required`
7. Session is closed by either side with `session.end`

## Example structured action payloads
See:
- `shared/schemas/samples/actions/action-proposed-navigate_to_destination.sample.json`
- `shared/schemas/samples/actions/action-proposed-send_message.sample.json`
- `shared/schemas/samples/actions/action-proposed-create_reminder.sample.json`
- `shared/schemas/samples/actions/action-proposed-summarize_notifications.sample.json`
- `shared/schemas/samples/actions/action-proposed-call_contact.sample.json`
- `shared/schemas/samples/actions/action-proposed-open_garage.sample.json`
