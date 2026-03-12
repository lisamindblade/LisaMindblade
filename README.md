# LisaMindblade

Voice-first personal assistant system for Lisa.

## Phase 1 scope
- Production-style repository structure
- Surface-agnostic event protocol (`iphone`, future `carplay`, future `watch`)
- Backend skeleton (Python, WebSocket-first)
- iOS thin-client skeleton (SwiftUI, no business logic in UI)
- Shared contracts/schemas and architecture docs
- Clear integration boundary for OpenClaw

## Repository layout
- `backend/` Python assistant service intended to run on Mac mini
- `ios/` iPhone client app (thin voice interface)
- `shared/` cross-surface contracts/schemas
- `docs/` product, architecture, and API specs

## Quick start (skeleton)
1. Read [docs/product-spec.md](docs/product-spec.md)
2. Read [docs/architecture.md](docs/architecture.md)
3. Read [docs/api-spec.md](docs/api-spec.md)
4. Start backend from `backend/`: `python -m app.main`
5. Switch assistant engine with `LISAMINDBLADE_ASSISTANT_ENGINE` (`stub` or `openclaw`)

## Status
This is **v1 in-progress** with typed protocols, real iOS WebSocket transport,
STT/TTS wiring, and an OpenClaw-backed engine path behind the assistant interface.
