from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass
class SessionState:
    session_id: str
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    is_active: bool = True
    awaiting_confirmation: bool = False
