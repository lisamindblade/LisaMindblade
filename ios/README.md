# iOS Client (thin surface)

SwiftUI client for Lisa voice interactions.

## Architecture notes
- Views are intent-only and contain no backend/business logic.
- `ConnectionManager` maps protocol events to UI state transitions.
- `AppState` + `LisaClientStateMachine` model the client lifecycle.
- Transport is behind `VoiceTransport`, so future surfaces can reuse the flow.
- Audio input is behind `AudioCapturing`.
- Audio output is behind `AudioPlaying`.

## Client states
- `idle`
- `listening`
- `transcribing`
- `thinking`
- `speaking`
- `awaitingConfirmation`
- `error`

## CarPlay readiness
CarPlay can be added as another surface by creating a CarPlay UI layer that uses
the same `ConnectionManager`/protocol models with `surface: .carplay`.

## STT/TTS implementation status
- STT: `AppleSpeechAudioCaptureService` (Speech + AVAudioEngine)
- TTS: `AVSpeechAudioPlaybackService` (AVSpeechSynthesizer)
- TTS voice selection: app automatically picks the highest-quality installed voice
  for preferred language (Enhanced/Premium when available).
- Default app-preferred voice is `Ava` (if installed). Override via
  `UserDefaults` key `LisaMindbladePreferredVoiceName`.
- Permissions are declared in `LisaMindbladeApp/Info.plist`.

For better free voice quality, install Enhanced/Premium voices in iOS:
`Settings > Accessibility > Spoken Content > Voices`.

## Transport implementation status
- WebSocket transport is real (`WebSocketVoiceClient` + `URLSessionWebSocketTask`).
- Default backend URL: `wss://lisa.taild3cb8f.ts.net` (MagicDNS over Tailscale).
- This build hardcodes `session.start.payload.auth_token = "mindblade"`.
- Connect screen no longer asks for URL/password.
- Override URL by setting `LISAMINDBLADE_BACKEND_WS_URL` or `UserDefaults` key
  `LisaMindbladeBackendWSURL`.

## Future integration points
- You can swap `AudioCapturing` and `AudioPlaying` implementations without changing views.
- No view changes are needed when moving from local STT/TTS to production adapters.
