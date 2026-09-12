import json
import shutil
import subprocess
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from assistant.main import app

client = TestClient(app)


# ─── /api/health ─────────────────────────────────────────────────────────────

class TestHealth:
    def test_health_ok_when_claude_on_path(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(shutil, "which", lambda _: "/usr/local/bin/claude")
        resp = client.get("/api/health")
        assert resp.status_code == 200
        assert resp.json() == {"status": "ok"}

    def test_health_503_when_claude_missing(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(shutil, "which", lambda _: None)
        resp = client.get("/api/health")
        assert resp.status_code == 503
        assert "claude CLI not found" in resp.json()["detail"]


# ─── /api/polish — validation ─────────────────────────────────────────────────

class TestPolishValidation:
    def test_empty_text_returns_422(self) -> None:
        resp = client.post("/api/polish", json={"text": "", "channel": "slack"})
        assert resp.status_code == 422

    def test_invalid_channel_returns_422(self) -> None:
        resp = client.post("/api/polish", json={"text": "Hello", "channel": "invalid_channel"})
        assert resp.status_code == 422

    def test_missing_channel_returns_422(self) -> None:
        resp = client.post("/api/polish", json={"text": "Hello"})
        assert resp.status_code == 422


# ─── /api/polish — error propagation ─────────────────────────────────────────

class TestPolishErrors:
    def test_timeout_returns_504(self) -> None:
        with patch(
            "assistant.pipeline.run_claude",
            side_effect=subprocess.TimeoutExpired(cmd="claude", timeout=120),
        ):
            resp = client.post("/api/polish", json={"text": "Hello", "channel": "slack"})
        assert resp.status_code == 504
        assert "120" in resp.json()["detail"]

    def test_cli_failure_returns_502(self) -> None:
        with patch(
            "assistant.pipeline.run_claude",
            side_effect=RuntimeError("claude CLI failed: not signed in"),
        ):
            resp = client.post("/api/polish", json={"text": "Hello", "channel": "slack"})
        assert resp.status_code == 502

    def test_cli_not_found_returns_503(self) -> None:
        with patch(
            "assistant.pipeline.run_claude",
            side_effect=FileNotFoundError("claude CLI not found on PATH"),
        ):
            resp = client.post("/api/polish", json={"text": "Hello", "channel": "slack"})
        assert resp.status_code == 503

    def test_unparsable_json_returns_502(self) -> None:
        with patch("assistant.pipeline.run_claude", return_value="not json at all"):
            resp = client.post("/api/polish", json={"text": "Hello", "channel": "slack"})
        assert resp.status_code == 502


# ─── /api/polish — successful responses ──────────────────────────────────────

class TestPolishSuccess:
    def test_english_input_returns_polished_text_and_summary(self) -> None:
        mock_response = json.dumps({
            "detected_language": "English",
            "was_translated": False,
            "polished_text": "Please send me the report by end of day.",
            "learning_summary": {
                "corrections": [],
                "grammar_insight": "Good use of imperative mood.",
                "vocabulary": [],
            },
        })
        with patch("assistant.pipeline.run_claude", return_value=mock_response):
            resp = client.post(
                "/api/polish", json={"text": "Send me report pls", "channel": "formal"}
            )
        assert resp.status_code == 200
        data = resp.json()
        assert data["polished_text"] == "Please send me the report by end of day."
        assert data["was_translated"] is False
        assert data["learning_summary"] is not None

    def test_spanish_input_returns_no_summary(self) -> None:
        mock_response = json.dumps({
            "detected_language": "Spanish",
            "was_translated": True,
            "polished_text": "Please send me the report by end of day.",
            "learning_summary": None,
        })
        with patch("assistant.pipeline.run_claude", return_value=mock_response):
            resp = client.post(
                "/api/polish",
                json={"text": "Por favor envíame el informe.", "channel": "slack"},
            )
        assert resp.status_code == 200
        data = resp.json()
        assert data["was_translated"] is True
        assert data["learning_summary"] is None

    @pytest.mark.parametrize(
        "channel", ["slack", "slack_informal", "talking_points", "formal", "ai_prompt", "other"]
    )
    def test_all_channels_accepted(self, channel: str) -> None:
        mock_response = json.dumps({
            "detected_language": "English",
            "was_translated": False,
            "polished_text": "Test.",
            "learning_summary": {"corrections": [], "grammar_insight": "", "vocabulary": []},
        })
        with patch("assistant.pipeline.run_claude", return_value=mock_response):
            resp = client.post("/api/polish", json={"text": "Test text.", "channel": channel})
        assert resp.status_code == 200


# ─── /api/heartbeat ───────────────────────────────────────────────────────────

class TestHeartbeat:
    def test_heartbeat_returns_204(self) -> None:
        resp = client.post("/api/heartbeat")
        assert resp.status_code == 204

    def test_heartbeat_get_not_found(self) -> None:
        # GET /api/heartbeat is not defined; the catch-all StaticFiles mount
        # returns 404 (not 405) because it swallows unmatched paths.
        resp = client.get("/api/heartbeat")
        assert resp.status_code == 404
