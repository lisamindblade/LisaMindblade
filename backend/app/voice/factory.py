from __future__ import annotations

from app.voice.transcript_ingestion import (
    BasicTranscriptIngestionService,
    StubTranscriptIngestionService,
    TranscriptIngestionService,
)
from app.voice.tts import MacOSSayTTSService, StubTTSService, TTSService


def build_transcript_ingestion_service(engine_name: str) -> TranscriptIngestionService:
    normalized = engine_name.strip().lower()

    if normalized == "basic":
        return BasicTranscriptIngestionService()
    if normalized == "stub":
        return StubTranscriptIngestionService()

    raise ValueError(
        "Unsupported transcript ingestion engine. Expected one of: "
        "'basic', 'stub'. "
        f"Got: '{engine_name}'."
    )


def build_tts_service(
    engine_name: str,
    *,
    voice: str | None,
    rate: int,
    speak_partials: bool,
) -> TTSService:
    normalized = engine_name.strip().lower()

    if normalized == "say":
        return MacOSSayTTSService(
            voice=voice,
            rate=rate,
            speak_partials=speak_partials,
        )
    if normalized == "stub":
        return StubTTSService()

    raise ValueError(
        "Unsupported TTS engine. Expected one of: 'say', 'stub'. "
        f"Got: '{engine_name}'."
    )
