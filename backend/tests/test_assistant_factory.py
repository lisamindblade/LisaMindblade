import pytest

from app.assistant.factory import build_assistant_engine
from app.assistant.openclaw_client import OpenClawClient
from app.assistant.openclaw_engine import OpenClawAssistantEngine
from app.assistant.stub import StubAssistantEngine


def test_factory_builds_stub_engine() -> None:
    engine = build_assistant_engine("stub")
    assert isinstance(engine, StubAssistantEngine)


def test_factory_builds_openclaw_engine() -> None:
    engine = build_assistant_engine("openclaw")
    assert isinstance(engine, OpenClawAssistantEngine)


def test_factory_builds_openclaw_engine_with_http_mode() -> None:
    engine = build_assistant_engine("openclaw", openclaw_client_mode="http")
    assert isinstance(engine, OpenClawAssistantEngine)


def test_factory_uses_injected_openclaw_client() -> None:
    class FakeClient(OpenClawClient):
        async def complete(self, *, session_id: str, user_text: str) -> str:
            return "ok"

    engine = build_assistant_engine("openclaw", openclaw_client=FakeClient())
    assert isinstance(engine, OpenClawAssistantEngine)


def test_factory_rejects_unknown_openclaw_client_mode() -> None:
    with pytest.raises(ValueError):
        build_assistant_engine("openclaw", openclaw_client_mode="unsupported")


def test_factory_rejects_unknown_engine() -> None:
    with pytest.raises(ValueError):
        build_assistant_engine("unknown")
