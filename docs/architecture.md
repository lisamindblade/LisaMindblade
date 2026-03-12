# LisaMindblade Architecture (v1)

## High-level components
- `backend` (Mac mini): session orchestration, assistant abstraction, event routing
- `ios` (iPhone): thin UI client for push-to-talk and transcript rendering
- `shared`: event contracts/schemas consumed by every client surface

## Design principles
- Surface-agnostic core: backend never depends on iPhone-only assumptions
- Transport/event decoupling: business logic consumes typed events, not UI controls
- Explicit safety: side-effect actions require confirmation events
- Provider abstraction: OpenClaw sits behind an assistant engine interface
- Optional shared-token gate: connection authorization is validated on `session.start`

## Logical flow
1. iPhone opens a session over WebSocket (`session.start`)
   - optional `auth_token` can be included for shared-password validation
2. iPhone emits streaming transcript events (`transcript.partial`, `transcript.final`)
3. Backend emits `assistant.thinking`, then `assistant.response.chunk` and `assistant.response.final`
4. For side effects, backend emits structured `action.proposed` with typed parameters, risk, and confirmation metadata
5. Confirmation-sensitive actions emit `action.confirmation_required`
6. Session closes with `session.end` from either client or backend

## Module map
- `backend/app/core`: config and logging
- `backend/app/transport`: WebSocket adapter boundary
- `backend/app/domain`: session, turn, and action models
- `backend/app/assistant`: engine interface + implementations + DI factory
- `backend/app/voice`: transcript ingestion + TTS service interfaces
- `ios/LisaMindbladeApp`: app shell, state model, UI placeholders, connection manager
- `ios/LisaMindbladeApp/Infrastructure/Audio`: audio capture + playback abstractions
- `shared/contracts` + `shared/schemas`: canonical protocol docs and examples

## OpenClaw boundary and dependency injection
The backend depends on `AssistantEngine` only:
- `AssistantEngine` interface defines streaming behavior for assistant turns.
- `StubAssistantEngine` supports local development.
- `OpenClawAssistantEngine` calls OpenClaw through an HTTP client boundary.
- `build_assistant_engine(...)` resolves the implementation from config.

This keeps transport/session orchestration independent of OpenClaw SDK internals.

## How to swap engines
1. Set `LISAMINDBLADE_ASSISTANT_ENGINE=stub` or `openclaw`.
2. Start backend (`python -m app.main`).
3. No transport or API layer changes are required.

## Voice pipeline seams (future STT/TTS)
- Backend transcript ingestion boundary: `TranscriptIngestionService` in `backend/app/voice/transcript_ingestion.py`.
- Backend TTS boundary: `TTSService` in `backend/app/voice/tts.py`.
- iOS microphone boundary: `AudioCapturing` in `ios/LisaMindbladeApp/Infrastructure/Audio/AudioCaptureService.swift`.
- iOS playback boundary: `AudioPlaying` in `ios/LisaMindbladeApp/Infrastructure/Audio/AudioPlaybackService.swift`.

Current defaults:
- iOS STT uses `AppleSpeechAudioCaptureService` (Speech + AVAudioEngine).
- iOS TTS uses `AVSpeechAudioPlaybackService` (AVSpeechSynthesizer) and is the default playback path for iPhone.
- Backend TTS is optional (`MacOSSayTTSService` via `LISAMINDBLADE_TTS_ENGINE=say`) and defaults to `stub` to avoid duplicate/off-device speech.

Future providers can be connected by implementing these interfaces and injecting
them, without changing protocol contracts, transport handlers, or view code.

## Current transport status
- iOS `WebSocketVoiceClient` uses a real `URLSessionWebSocketTask` receive loop.
- Backend `WebSocketServer` is the canonical protocol endpoint.
- iOS and backend remain decoupled through shared protocol envelopes and a transport interface.

## How CarPlay support is preserved (future)
CarPlay can be added as another client surface that speaks the same shared events.
Because backend logic depends only on event contracts and assistant interfaces, CarPlay
integration should require no backend business-logic rewrite.

Expected CarPlay work later:
- Add new CarPlay UI + interaction layer
- Reuse existing WebSocket protocol and backend orchestrator
- Keep confirmation and cancellation semantics unchanged
