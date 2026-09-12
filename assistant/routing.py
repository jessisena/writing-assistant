from __future__ import annotations

# Model IDs — verify these are available to your CLI before deploying.
# To check: claude --print --model claude-sonnet-5 "hi"
# If that returns a model-not-found error, use "claude-sonnet-4-6" instead.
HAIKU_MODEL = "claude-haiku-4-5-20251001"
SONNET_MODEL = "claude-sonnet-4-6"

# Route to Haiku only for short text. 60 words is the threshold: long enough to cover
# a typical Slack message, short enough to stay well within Haiku's quality range.
_MAX_HAIKU_WORDS = 60

# Common stopwords from Spanish and Portuguese to detect non-English short text.
# Only used for routing — the prompt does the actual language detection and translation.
_ROMANCE_STOPWORDS = frozenset(
    """
    el la los las un una de del en que por para con su sus al
    o es son hay como también pero si no yo lo le se mi tu
    da do em por para com se não mas ou também já
    """.split()
)


def _looks_like_english(text: str) -> bool:
    """Return True when the text is very likely English.

    Two cheap heuristics:
    1. Non-ASCII ratio below 2% (accented Spanish/Portuguese chars push this up).
    2. Fewer than two Romance-language stopword hits.

    Ambiguity resolves to False so model selection defaults to Sonnet.
    This is a routing hint only — the prompt performs the real language detection.
    """
    if not text:
        return False
    non_ascii = sum(1 for c in text if ord(c) > 127)
    if non_ascii / len(text) > 0.02:
        return False
    words = [w.strip(".,!?;:\"'") for w in text.lower().split()]
    romance_hits = sum(1 for w in words if w in _ROMANCE_STOPWORDS)
    return romance_hits < 2


def pick_model(text: str) -> str:
    """Return the model ID to use for this text.

    Haiku only when the text is short AND confidently English.
    Everything else — including ambiguous cases — gets Sonnet.

    A wrong Haiku routing (short Spanish → Haiku for translation) is worse than a wrong
    Sonnet routing (long English → Sonnet for polish), so ambiguity resolves upward.
    """
    words = text.split()
    if len(words) <= _MAX_HAIKU_WORDS and _looks_like_english(text):
        return HAIKU_MODEL
    return SONNET_MODEL
