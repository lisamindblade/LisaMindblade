from dataclasses import dataclass, field
from datetime import datetime, timezone
from uuid import uuid4


@dataclass(frozen=True)
class AssistantTurn:
    """Represents one user -> assistant turn within a session."""

    session_id: str
    user_text: str
    assistant_text: str
    turn_id: str = field(default_factory=lambda: str(uuid4()))
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
