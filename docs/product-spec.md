# LisaMindblade Product Spec (v1)

## Vision
LisaMindblade is a voice-first personal assistant where:
- Mac mini hosts assistant core logic
- iPhone is a thin voice client
- Future surfaces (CarPlay, Watch) reuse the same backend protocol and logic

## Non-goals for v1
- No CarPlay implementation yet
- No Watch implementation yet
- No fully production-hardened OpenClaw rollout yet (basic provider integration only)

## User flow (voice-first)
1. User presses push-to-talk on iPhone
2. iPhone streams user audio/transcript events to backend
3. Backend streams transcript state + assistant response chunks back
4. User can interrupt/cancel at any time
5. Side-effecting actions require explicit confirmation

## Product requirements
- Low-latency conversational loop
- Streamed partial updates for UX responsiveness
- Surface-agnostic protocol envelopes
- Strict separation of UI from business logic
- Safe execution for side-effecting actions via confirmation gates

## v1 deliverables
- Backend service skeleton in Python
- iOS thin-client skeleton in SwiftUI
- Shared event schema and typed contracts
- Architecture + API documentation
