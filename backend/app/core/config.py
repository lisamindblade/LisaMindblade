from dataclasses import dataclass
import os


@dataclass(frozen=True)
class AppConfig:
    host: str
    port: int
    log_level: str
    shared_token: str | None
    assistant_engine: str
    transcript_ingestion_engine: str
    tts_engine: str
    tts_voice: str | None
    tts_rate: int
    tts_speak_partials: bool
    openclaw_base_url: str
    openclaw_chat_path: str
    openclaw_model: str
    openclaw_api_key: str | None
    openclaw_timeout_seconds: float
    openclaw_system_prompt: str
    openclaw_chunk_chars: int
    openclaw_client_mode: str
    openclaw_cli_command: str
    openclaw_cli_agent: str
    openclaw_cli_timeout_seconds: float
    openclaw_cli_use_local: bool

    @classmethod
    def from_env(cls) -> "AppConfig":
        speak_partials = os.getenv("LISAMINDBLADE_TTS_SPEAK_PARTIALS", "false").strip().lower()
        cli_use_local = os.getenv("LISAMINDBLADE_OPENCLAW_CLI_USE_LOCAL", "true").strip().lower()
        shared_token = os.getenv("LISAMINDBLADE_SHARED_TOKEN")
        normalized_shared_token = (shared_token or "mindblade").strip()
        return cls(
            host=os.getenv("LISAMINDBLADE_HOST", "0.0.0.0"),
            port=int(os.getenv("LISAMINDBLADE_PORT", "8765")),
            log_level=os.getenv("LISAMINDBLADE_LOG_LEVEL", "INFO"),
            shared_token=normalized_shared_token or "mindblade",
            assistant_engine=os.getenv("LISAMINDBLADE_ASSISTANT_ENGINE", "stub"),
            transcript_ingestion_engine=os.getenv(
                "LISAMINDBLADE_TRANSCRIPT_INGESTION_ENGINE",
                "basic",
            ),
            tts_engine=os.getenv("LISAMINDBLADE_TTS_ENGINE", "stub"),
            tts_voice=os.getenv("LISAMINDBLADE_TTS_VOICE"),
            tts_rate=int(os.getenv("LISAMINDBLADE_TTS_RATE", "185")),
            tts_speak_partials=speak_partials in {"1", "true", "yes", "on"},
            openclaw_base_url=os.getenv("LISAMINDBLADE_OPENCLAW_BASE_URL", "http://127.0.0.1:8000"),
            openclaw_chat_path=os.getenv(
                "LISAMINDBLADE_OPENCLAW_CHAT_PATH",
                "/v1/chat/completions",
            ),
            openclaw_model=os.getenv("LISAMINDBLADE_OPENCLAW_MODEL", "openclaw"),
            openclaw_api_key=os.getenv("LISAMINDBLADE_OPENCLAW_API_KEY"),
            openclaw_timeout_seconds=float(
                os.getenv("LISAMINDBLADE_OPENCLAW_TIMEOUT_SECONDS", "45")
            ),
            openclaw_system_prompt=os.getenv(
                "LISAMINDBLADE_OPENCLAW_SYSTEM_PROMPT",
                "You are Lisa, a concise and practical voice assistant.",
            ),
            openclaw_chunk_chars=int(os.getenv("LISAMINDBLADE_OPENCLAW_CHUNK_CHARS", "160")),
            openclaw_client_mode=os.getenv("LISAMINDBLADE_OPENCLAW_CLIENT_MODE", "cli"),
            openclaw_cli_command=os.getenv("LISAMINDBLADE_OPENCLAW_CLI_COMMAND", "openclaw"),
            openclaw_cli_agent=os.getenv("LISAMINDBLADE_OPENCLAW_CLI_AGENT", "main"),
            openclaw_cli_timeout_seconds=float(
                os.getenv("LISAMINDBLADE_OPENCLAW_CLI_TIMEOUT_SECONDS", "120")
            ),
            openclaw_cli_use_local=cli_use_local in {"1", "true", "yes", "on"},
        )
