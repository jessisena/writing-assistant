from __future__ import annotations

import json
from pathlib import Path

from pydantic import ValidationError

from assistant.claude_cli import extract_json, run_claude
from assistant.models import Channel, LearningSummary, PolishResponse
from assistant.routing import pick_model

_PROMPTS_DIR = Path(__file__).parent / "prompts"
_CHANNELS_DIR = _PROMPTS_DIR / "channels"

_TIMEOUT = 120  # seconds — generous ceiling for a single polish call


def _load_prompt(channel: Channel) -> str:
    """Assemble the full system prompt for the given channel."""
    if not isinstance(channel, Channel):
        raise ValueError(f"Invalid channel: {channel!r}")
    template = (_PROMPTS_DIR / "polish.txt").read_text().strip()
    channel_guidelines = (_CHANNELS_DIR / f"{channel.value}.txt").read_text().strip()
    return template.replace("{{CHANNEL_GUIDELINES}}", channel_guidelines)


def polish(text: str, channel: Channel) -> PolishResponse:
    """Run the full 4-step pipeline and return the structured response.

    Enforces the was_translated invariant at the server layer:
    learning_summary is always None when was_translated is True, regardless of
    what the model returns. This is the guarantee the UI relies on.
    """
    model = pick_model(text)
    system_prompt = _load_prompt(channel)

    raw = run_claude(system_prompt=system_prompt, content=text, model=model, timeout=_TIMEOUT)

    try:
        data = extract_json(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Claude returned an unexpected format: {exc}") from exc

    was_translated = bool(data.get("was_translated", False))
    raw_summary = data.get("learning_summary")

    # Server-side invariant: strip the summary whenever the input was translated,
    # regardless of what the model returned. The prompt instructs it, but this
    # enforcement layer exists because prompt instructions are not a guarantee.
    if was_translated:
        summary: LearningSummary | None = None
    elif raw_summary is not None:
        try:
            summary = LearningSummary.model_validate(raw_summary)
        except ValidationError as exc:
            raise ValueError(
                f"Claude returned an unexpected format in learning_summary: {exc}"
            ) from exc
    else:
        summary = None

    try:
        return PolishResponse(
            polished_text=str(data["polished_text"]),
            learning_summary=summary,
            detected_language=str(data.get("detected_language", "Unknown")),
            was_translated=was_translated,
            model_used=model,
        )
    except KeyError as exc:
        raise ValueError(f"Claude response missing required field: {exc}") from exc
