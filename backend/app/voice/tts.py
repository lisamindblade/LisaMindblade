from __future__ import annotations

from abc import ABC, abstractmethod
import asyncio


class TTSService(ABC):
    """Boundary for converting assistant text into speech output."""

    @abstractmethod
    async def speak(self, *, session_id: str, text: str, is_final: bool) -> None:
        """Synthesize or queue speech for a text chunk."""
        raise NotImplementedError


class MacOSSayTTSService(TTSService):
    """Real TTS adapter for macOS using the built-in `say` command."""

    def __init__(
        self,
        *,
        voice: str | None = None,
        rate: int = 185,
        speak_partials: bool = False,
    ) -> None:
        self.voice = voice
        self.rate = rate
        self.speak_partials = speak_partials
        self._lock = asyncio.Lock()

    async def speak(self, *, session_id: str, text: str, is_final: bool) -> None:
        _ = session_id
        cleaned = text.strip()
        if not cleaned:
            return
        if not is_final and not self.speak_partials:
            return

        asyncio.create_task(self._run_say(cleaned))

    async def _run_say(self, text: str) -> None:
        cmd = ["say", "-r", str(self.rate)]
        if self.voice:
            cmd.extend(["-v", self.voice])
        cmd.append(text)

        async with self._lock:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await process.communicate()


class StubTTSService(TTSService):
    """No-op TTS implementation for protocol and architecture scaffolding."""

    async def speak(self, *, session_id: str, text: str, is_final: bool) -> None:
        _ = session_id
        _ = text
        _ = is_final
