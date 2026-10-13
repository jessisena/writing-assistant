"""Tests for the heartbeat auto-shutdown logic in assistant/session."""
from __future__ import annotations

import asyncio
import signal
import time
from unittest.mock import patch

import pytest

import assistant.session as session_mod


def _reset() -> None:
    session_mod._last_seen = None


@pytest.fixture(autouse=True)
def reset_state() -> None:  # type: ignore[return]
    _reset()
    yield  # type: ignore[misc]
    _reset()


@pytest.mark.asyncio
async def test_no_heartbeat_never_signals() -> None:
    """Server started without a browser window: watcher never fires."""
    with patch("signal.raise_signal") as mock_sig, \
         patch("assistant.session._POLL", 0.01), \
         patch("assistant.session.IDLE_LIMIT", 0.05):
        task = asyncio.create_task(session_mod.watch())
        await asyncio.sleep(0.2)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    mock_sig.assert_not_called()


@pytest.mark.asyncio
async def test_heartbeat_then_idle_signals() -> None:
    """Beat received, then silence beyond IDLE_LIMIT: SIGTERM raised."""
    with patch("signal.raise_signal") as mock_sig, \
         patch("assistant.session._POLL", 0.01), \
         patch("assistant.session.IDLE_LIMIT", 0.05):
        session_mod.touch()
        # Fake last_seen to be far in the past
        session_mod._last_seen = time.monotonic() - 1.0
        task = asyncio.create_task(session_mod.watch())
        await asyncio.sleep(0.2)
        try:
            task.cancel()
            await task
        except (asyncio.CancelledError, Exception):
            pass
    mock_sig.assert_called_once_with(signal.SIGTERM)


@pytest.mark.asyncio
async def test_recent_heartbeat_does_not_signal() -> None:
    """Beat within IDLE_LIMIT: watcher does not fire."""
    with patch("signal.raise_signal") as mock_sig, \
         patch("assistant.session._POLL", 0.01), \
         patch("assistant.session.IDLE_LIMIT", 10.0):
        session_mod.touch()
        task = asyncio.create_task(session_mod.watch())
        await asyncio.sleep(0.1)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
    mock_sig.assert_not_called()
