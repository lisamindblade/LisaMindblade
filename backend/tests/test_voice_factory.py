import pytest

from app.voice.factory import (
    build_transcript_ingestion_service,
    build_tts_service,
)
from app.voice.transcript_ingestion import (
    BasicTranscriptIngestionService,
    StubTranscriptIngestionService,
)
from app.voice.tts import MacOSSayTTSService, StubTTSService


def test_build_transcript_ingestion_service_basic() -> None:
    service = build_transcript_ingestion_service("basic")
    assert isinstance(service, BasicTranscriptIngestionService)


def test_build_transcript_ingestion_service_stub() -> None:
    service = build_transcript_ingestion_service("stub")
    assert isinstance(service, StubTranscriptIngestionService)


def test_build_transcript_ingestion_service_rejects_unknown() -> None:
    with pytest.raises(ValueError):
        build_transcript_ingestion_service("unknown")


def test_build_tts_service_say() -> None:
    service = build_tts_service("say", voice=None, rate=185, speak_partials=False)
    assert isinstance(service, MacOSSayTTSService)


def test_build_tts_service_stub() -> None:
    service = build_tts_service("stub", voice=None, rate=185, speak_partials=False)
    assert isinstance(service, StubTTSService)


def test_build_tts_service_rejects_unknown() -> None:
    with pytest.raises(ValueError):
        build_tts_service("unknown", voice=None, rate=185, speak_partials=False)
