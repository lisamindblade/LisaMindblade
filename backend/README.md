# Backend Service (Mac mini)

Python service that orchestrates assistant sessions for all client surfaces.

## Responsibilities
- Accept WebSocket client sessions
- Process typed protocol events
- Stream `assistant.thinking`, `assistant.response.chunk`, and `assistant.response.final`
- Gate side-effect actions with explicit confirmations
- Optionally enforce a shared session password from `session.start.payload.auth_token`

## Assistant engine boundary
- Interface: `app/assistant/base.py` (`AssistantEngine`)
- Local stub: `app/assistant/stub.py` (`StubAssistantEngine`)
- OpenClaw engine: `app/assistant/openclaw_engine.py` (`OpenClawAssistantEngine`)
- OpenClaw client boundary (CLI + HTTP): `app/assistant/openclaw_client.py`
- DI factory: `app/assistant/factory.py` (`build_assistant_engine`)

The transport layer only depends on `AssistantEngine`, so backend flow is not coupled
to OpenClaw internals.

## Voice pipeline boundaries
- Transcript ingestion interface: `app/voice/transcript_ingestion.py`
- TTS interface: `app/voice/tts.py`
- Voice DI factory: `app/voice/factory.py`

Current real/default choices:
- Transcript ingestion: `basic`
- TTS: `stub` (default; iPhone app handles playback)

## Swapping engines
Use `LISAMINDBLADE_ASSISTANT_ENGINE`:
- `stub` (default)
- `openclaw` (real provider call through OpenClaw client boundary)

Example:
```bash
export LISAMINDBLADE_ASSISTANT_ENGINE=openclaw
export LISAMINDBLADE_OPENCLAW_CLIENT_MODE=cli
python -m app.main
```

OpenClaw CLI configuration env vars:
- `LISAMINDBLADE_OPENCLAW_CLIENT_MODE` (`cli` default, `http` optional)
- `LISAMINDBLADE_OPENCLAW_CLI_COMMAND` (default: `openclaw`)
- `LISAMINDBLADE_OPENCLAW_CLI_AGENT` (default: `main`)
- `LISAMINDBLADE_OPENCLAW_CLI_TIMEOUT_SECONDS` (default: `120`)
- `LISAMINDBLADE_OPENCLAW_CLI_USE_LOCAL` (`true|false`, default: `false`)

OpenClaw HTTP configuration env vars (when `LISAMINDBLADE_OPENCLAW_CLIENT_MODE=http`):
- `LISAMINDBLADE_OPENCLAW_BASE_URL` (default: `http://127.0.0.1:8000`)
- `LISAMINDBLADE_OPENCLAW_CHAT_PATH` (default: `/v1/chat/completions`)
- `LISAMINDBLADE_OPENCLAW_MODEL` (default: `openclaw`)
- `LISAMINDBLADE_OPENCLAW_API_KEY` (optional)
- `LISAMINDBLADE_OPENCLAW_TIMEOUT_SECONDS` (default: `45`)
- `LISAMINDBLADE_OPENCLAW_SYSTEM_PROMPT` (optional override)
- `LISAMINDBLADE_OPENCLAW_CHUNK_CHARS` (default: `160`)

## STT/TTS configuration
- `LISAMINDBLADE_TRANSCRIPT_INGESTION_ENGINE=basic|stub`
- `LISAMINDBLADE_TTS_ENGINE=say|stub`
- `LISAMINDBLADE_TTS_VOICE=<macOS voice name>`
- `LISAMINDBLADE_TTS_RATE=185`
- `LISAMINDBLADE_TTS_SPEAK_PARTIALS=false`
- `LISAMINDBLADE_SHARED_TOKEN=<your_shared_password>` (default: `mindblade`)

## Local run (after installing dependencies)
- Start backend: `python -m app.main` (from `backend/`)
- Run sample client: `python -m examples.ws_test_client` (from `backend/`)
- Override sample client target: `LISAMINDBLADE_WS_URL=ws://127.0.0.1:8766 python -m examples.ws_test_client`
- If shared token is enabled, set the same value for the sample client:
  `LISAMINDBLADE_SHARED_TOKEN=<your_shared_password> python -m examples.ws_test_client`
