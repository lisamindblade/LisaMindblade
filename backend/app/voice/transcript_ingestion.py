from __future__ import annotations

from abc import ABC, abstractmethod
import re


class TranscriptIngestionService(ABC):
    """Boundary for transcript normalization/ingestion before assistant handling."""

    @abstractmethod
    async def ingest(self, *, session_id: str, text: str, is_final: bool) -> str:
        """Return normalized transcript text for downstream assistant processing."""
        raise NotImplementedError


class BasicTranscriptIngestionService(TranscriptIngestionService):
    """Minimal real transcript ingestion normalization pipeline."""

    async def ingest(self, *, session_id: str, text: str, is_final: bool) -> str:
        _ = session_id

        normalized = re.sub(r"\s+", " ", text).strip()
        if is_final and normalized and normalized[-1] not in ".!?":
            normalized = f"{normalized}."
        return normalized


class StubTranscriptIngestionService(TranscriptIngestionService):
    """No-op transcript ingestion implementation for local development."""

    async def ingest(self, *, session_id: str, text: str, is_final: bool) -> str:
        _ = session_id
        _ = is_final
        return text.strip()
