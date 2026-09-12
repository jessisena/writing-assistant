import json
from unittest.mock import patch

import pytest

from assistant.models import Channel
from assistant.pipeline import _load_prompt, polish

# ─── Fixture responses ────────────────────────────────────────────────────────

def _english_response() -> str:
    return json.dumps({
        "detected_language": "English",
        "was_translated": False,
        "polished_text": "Please send me the report by end of day.",
        "learning_summary": {
            "corrections": [
                {
                    "original": "send me the report pls",
                    "corrected": "please send me the report by end of day",
                    "why": "Avoid informal abbreviations in written professional communication.",
                },
            ],
            "grammar_insight": "Spelling out polite words like 'please' signals professionalism.",
            "vocabulary": [
                {
                    "term": "by end of day",
                    "meaning": "before the working day ends",
                    "example": "Please submit your feedback by end of day.",
                }
            ],
        },
    })


def _translated_response(lang: str = "Spanish") -> str:
    return json.dumps({
        "detected_language": lang,
        "was_translated": True,
        "polished_text": "Please send me the report by end of day.",
        "learning_summary": None,
    })


def _disobedient_translated_response() -> str:
    """Model returns a summary despite was_translated=True. pipeline.py must strip it."""
    return json.dumps({
        "detected_language": "Spanish",
        "was_translated": True,
        "polished_text": "Please send me the report by end of day.",
        "learning_summary": {
            "corrections": [],
            "grammar_insight": "This summary should be stripped by the server.",
            "vocabulary": [],
        },
    })


# ─── was_translated gate ──────────────────────────────────────────────────────

class TestWasTranslatedGate:
    @pytest.mark.parametrize("lang", ["Spanish", "Portuguese", "French"])
    def test_translated_input_has_no_summary(self, lang: str) -> None:
        with patch("assistant.pipeline.run_claude", return_value=_translated_response(lang)):
            result = polish("some text", Channel.slack)
        assert result.was_translated is True
        assert result.learning_summary is None

    def test_disobedient_model_summary_is_stripped(self) -> None:
        """Server-side enforcement: summary is stripped even if model includes one."""
        with patch(
            "assistant.pipeline.run_claude",
            return_value=_disobedient_translated_response(),
        ):
            result = polish("Texto en español", Channel.slack)
        assert result.learning_summary is None

    def test_english_input_keeps_summary(self) -> None:
        with patch("assistant.pipeline.run_claude", return_value=_english_response()):
            result = polish("Send me the report pls", Channel.slack)
        assert result.was_translated is False
        assert result.learning_summary is not None

    def test_invariant_summary_not_none_implies_not_translated(self) -> None:
        with patch("assistant.pipeline.run_claude", return_value=_english_response()):
            result = polish("Send me the report.", Channel.slack)
        if result.learning_summary is not None:
            assert result.was_translated is False


# ─── extract_json tolerance ───────────────────────────────────────────────────

class TestExtractJson:
    def test_fenced_json_response(self) -> None:
        from assistant.claude_cli import extract_json
        raw = '```json\n{"key": "value"}\n```'
        assert extract_json(raw) == {"key": "value"}

    def test_plain_json_response(self) -> None:
        from assistant.claude_cli import extract_json
        assert extract_json('{"key": "value"}') == {"key": "value"}

    def test_preamble_before_json(self) -> None:
        from assistant.claude_cli import extract_json
        raw = "Now I will compile the result:\n\n{\"key\": \"value\"}"
        assert extract_json(raw) == {"key": "value"}

    def test_garbage_raises(self) -> None:
        from assistant.claude_cli import extract_json
        with pytest.raises(ValueError):
            extract_json("this is not json at all")


# ─── Channel prompt substitution ─────────────────────────────────────────────

class TestChannelSubstitution:
    @pytest.mark.parametrize("channel", list(Channel))
    def test_each_channel_loads_without_placeholder(self, channel: Channel) -> None:
        prompt = _load_prompt(channel)
        assert "{{CHANNEL_GUIDELINES}}" not in prompt
        assert len(prompt) > 200

    @pytest.mark.parametrize("channel", list(Channel))
    def test_em_dash_not_in_channel_guidelines(self, channel: Channel) -> None:
        prompt = _load_prompt(channel)
        assert "—" not in prompt, f"em dash found in prompt for channel {channel}"


# ─── Error conditions ─────────────────────────────────────────────────────────

class TestPipelineErrors:
    def test_unparsable_json_raises_value_error(self) -> None:
        with patch("assistant.pipeline.run_claude", return_value="not json"):
            with pytest.raises(ValueError, match="unexpected format"):
                polish("Hello", Channel.slack)

    def test_missing_polished_text_raises_value_error(self) -> None:
        broken = json.dumps({
            "detected_language": "English",
            "was_translated": False,
            # missing "polished_text"
        })
        with patch("assistant.pipeline.run_claude", return_value=broken):
            with pytest.raises(ValueError, match="missing required field"):
                polish("Hello", Channel.slack)
