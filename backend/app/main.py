import asyncio

from app.assistant.base import AssistantEngine
from app.assistant.openclaw_client import OpenClawCLIConfig, OpenClawClientConfig
from app.assistant.factory import build_assistant_engine
from app.core.config import AppConfig
from app.core.logging import configure_logging
from app.transport.websocket_server import WebSocketServer
from app.voice.factory import build_transcript_ingestion_service, build_tts_service
from app.voice.transcript_ingestion import TranscriptIngestionService
from app.voice.tts import TTSService


def create_app(
    assistant_engine: AssistantEngine | None = None,
    transcript_ingestion: TranscriptIngestionService | None = None,
    tts_service: TTSService | None = None,
) -> WebSocketServer:
    config = AppConfig.from_env()
    configure_logging(config.log_level)

    resolved_engine = assistant_engine or build_assistant_engine(
        config.assistant_engine,
        openclaw_config=OpenClawClientConfig(
            base_url=config.openclaw_base_url,
            chat_path=config.openclaw_chat_path,
            model=config.openclaw_model,
            api_key=config.openclaw_api_key,
            timeout_seconds=config.openclaw_timeout_seconds,
            system_prompt=config.openclaw_system_prompt,
        ),
        openclaw_cli_config=OpenClawCLIConfig(
            command=config.openclaw_cli_command,
            agent_id=config.openclaw_cli_agent,
            timeout_seconds=config.openclaw_cli_timeout_seconds,
            use_local=config.openclaw_cli_use_local,
        ),
        openclaw_client_mode=config.openclaw_client_mode,
        openclaw_chunk_chars=config.openclaw_chunk_chars,
    )
    resolved_ingestion = transcript_ingestion or build_transcript_ingestion_service(
        config.transcript_ingestion_engine
    )
    resolved_tts = tts_service or build_tts_service(
        config.tts_engine,
        voice=config.tts_voice,
        rate=config.tts_rate,
        speak_partials=config.tts_speak_partials,
    )
    server = WebSocketServer(
        config=config,
        assistant=resolved_engine,
        transcript_ingestion=resolved_ingestion,
        tts_service=resolved_tts,
    )
    return server


if __name__ == "__main__":
    app = create_app()
    asyncio.run(app.run())
