"""Desktop entry point — wraps the FastAPI app in a native macOS window via pywebview."""
from __future__ import annotations

import logging
import socket
import sys
import threading
import time
from pathlib import Path

import uvicorn
import webview

logging.basicConfig(
    filename=Path.home() / "Library/Logs/writing-assistant.log",
    level=logging.WARNING,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

_HOST = "127.0.0.1"
_PORT = 8765
_URL = f"http://{_HOST}:{_PORT}"


def _port_open(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((host, port)) == 0


def main() -> None:
    server: uvicorn.Server | None = None
    server_thread: threading.Thread | None = None

    if not _port_open(_HOST, _PORT):
        config = uvicorn.Config(
            "assistant.main:app",
            host=_HOST,
            port=_PORT,
            log_level="warning",
        )
        server = uvicorn.Server(config)
        server_thread = threading.Thread(target=server.run, daemon=True)
        server_thread.start()

        deadline = time.monotonic() + 20.0
        while not server.started:
            if time.monotonic() > deadline:
                print("ERROR: server did not start within 20 s", file=sys.stderr)
                sys.exit(1)
            time.sleep(0.05)

    window = webview.create_window(
        "Writing Assistant",
        _URL,
        width=820,
        height=780,
        min_size=(600, 500),
    )

    def _on_closed() -> None:
        if server is not None:
            server.should_exit = True

    window.events.closed += _on_closed
    webview.start()

    if server_thread is not None:
        server_thread.join(timeout=5)


if __name__ == "__main__":
    main()
