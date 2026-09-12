"""Heartbeat-based auto-shutdown.

The frontend POSTs /api/heartbeat every 15 s while the window is open.
When no beat has arrived for IDLE_LIMIT seconds *after the first one*,
the server exits gracefully with SIGTERM.

The watcher never fires if no beat has ever been received, so plain
`uv run uvicorn ...` during development never exits on its own.
"""

from __future__ import annotations

import asyncio
import signal
import time

IDLE_LIMIT: float = 120.0
_POLL: float = 5.0

_last_seen: float | None = None


def touch() -> None:
    """Record that the window is alive. Called by POST /api/heartbeat."""
    global _last_seen  # noqa: PLW0603
    _last_seen = time.monotonic()


async def watch() -> None:
    """Background task: exit via SIGTERM when the window goes away."""
    while True:
        await asyncio.sleep(_POLL)
        if _last_seen is not None and time.monotonic() - _last_seen > IDLE_LIMIT:
            signal.raise_signal(signal.SIGTERM)
            break
