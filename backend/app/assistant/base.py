from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator

from app.domain.protocol import ClientEvent, ServerEvent


class AssistantEngine(ABC):
    """Surface-agnostic assistant interface for backend orchestration."""

    @abstractmethod
    async def handle_event(self, event: ClientEvent) -> AsyncIterator[ServerEvent]:
        """Consume one client event and stream server events."""
        raise NotImplementedError
