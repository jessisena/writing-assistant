from __future__ import annotations

import asyncio
import logging
import shutil
import subprocess
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles

from assistant import session
from assistant.models import PolishRequest, PolishResponse
from assistant.pipeline import polish

_log = logging.getLogger(__name__)


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncGenerator[None, None]:  # noqa: ARG001
    task = asyncio.create_task(session.watch())
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Writing Assistant", version="0.1.0", lifespan=_lifespan)


@app.get("/api/health")
async def health() -> dict[str, str]:
    """Check that the claude CLI is reachable. Returns 503 if not found."""
    if shutil.which("claude") is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "claude CLI not found on PATH. "
                "Install it from https://claude.ai/download and restart the server."
            ),
        )
    return {"status": "ok"}


@app.post("/api/polish", response_model=PolishResponse)
async def polish_text(body: PolishRequest) -> PolishResponse:
    """Polish the given text for the selected channel and return both outputs."""
    try:
        return await run_in_threadpool(polish, text=body.text, channel=body.channel)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(
            status_code=504,
            detail="Claude took longer than 120 seconds. Please try again.",
        ) from exc
    except RuntimeError as exc:
        _log.error("claude CLI error: %s", exc)
        raise HTTPException(
            status_code=502, detail="Claude returned an error. Check the logs."
        ) from exc
    except ValueError as exc:
        _log.error("pipeline error: %s", exc)
        raise HTTPException(
            status_code=502,
            detail="Unexpected response format from Claude. Check the logs.",
        ) from exc


@app.post("/api/heartbeat", status_code=204)
async def heartbeat() -> Response:
    """Record that the frontend window is alive."""
    session.touch()
    return Response(status_code=204)


# Serve the static frontend — no build step required.
_static_dir = Path(__file__).parent.parent / "static"
if _static_dir.exists():
    app.mount("/", StaticFiles(directory=str(_static_dir), html=True), name="static")


def run() -> None:
    uvicorn.run("assistant.main:app", host="127.0.0.1", port=8765, reload=False)
