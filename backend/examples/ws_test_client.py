"""Minimal manual WebSocket client for Lisa protocol testing.

Usage:
  python -m examples.ws_test_client

Run backend first:
  python -m app.main
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import json
import os
from uuid import uuid4

import websockets


def make_event(session_id: str, event_type: str, payload: dict[str, str]) -> str:
    return json.dumps(
        {
            "version": "1.0",
            "event_id": str(uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "session_id": session_id,
            "surface": "iphone",
            "type": event_type,
            "payload": payload,
        }
    )


async def main() -> None:
    uri = os.getenv("LISAMINDBLADE_WS_URL", "ws://127.0.0.1:8765")
    auth_token = os.getenv("LISAMINDBLADE_SHARED_TOKEN")
    session_id = str(uuid4())

    async with websockets.connect(uri) as ws:
        session_start_payload: dict[str, str] = {"client_version": "0.1.0"}
        if auth_token and auth_token.strip():
            session_start_payload["auth_token"] = auth_token.strip()

        await ws.send(make_event(session_id, "session.start", session_start_payload))
        await drain_responses(ws, "session.start")

        await ws.send(make_event(session_id, "transcript.partial", {"text": "Send"}))
        await drain_responses(ws, "transcript.partial")

        await ws.send(
            make_event(
                session_id,
                "transcript.final",
                {"text": "Send a message to Alex saying I will be late"},
            )
        )
        await drain_responses(ws, "transcript.final")

        await ws.send(make_event(session_id, "session.end", {"reason": "demo_complete"}))
        await drain_responses(ws, "session.end")


async def drain_responses(ws: websockets.WebSocketClientProtocol, label: str) -> None:
    while True:
        try:
            message = await asyncio.wait_for(ws.recv(), timeout=0.25)
        except TimeoutError:
            break
        else:
            print(f"<- [{label}] {message}")


if __name__ == "__main__":
    asyncio.run(main())
