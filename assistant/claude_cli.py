from __future__ import annotations

import functools
import json
import os
import re
import shutil
import subprocess

# Headless calls: each invocation is throwaway text-in / JSON-out.
# - MCP disabled (no tools needed); loading servers per-invocation caused
#   120s subprocess timeouts (servers block on init in the background process).
# - Session persistence off so we don't write a resumable session per call.
_CLI_FLAGS = [
    "--strict-mcp-config",
    "--mcp-config",
    '{"mcpServers":{}}',
    "--no-session-persistence",
]

_JSON_FENCE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


@functools.lru_cache(maxsize=1)
def _get_claude_bin() -> str:
    """Resolve the claude CLI to an absolute path (cached after first call).

    launchd provides a minimal PATH that rarely includes ~/.local/bin or Homebrew,
    so we must resolve the absolute path rather than relying on the bare "claude" string.
    """
    resolved = shutil.which("claude")
    if resolved is None:
        raise FileNotFoundError(
            "claude CLI not found on PATH. "
            "Install it from https://claude.ai/download and ensure its directory is on your PATH."
        )
    return resolved


def run_claude(system_prompt: str, content: str, model: str, timeout: int) -> str:
    """Run a prompt through the local claude CLI (subscription auth) and return stdout.

    ANTHROPIC_API_KEY is stripped so the CLI always authenticates via the logged-in
    Claude subscription, not a pay-as-you-go key.

    One retry on RuntimeError only — retrying a TimeoutExpired would double the wait.
    """
    binary = _get_claude_bin()
    prompt = f"{system_prompt}\n\n---\n\n{content}"
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    # Disable extended thinking: bounded polish tasks don't need it, and the CLI's default
    # thinking budget turns an ~8s call into 75-99s (analysis-pipeline.md:107-120).
    env["MAX_THINKING_TOKENS"] = "0"
    env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
    cmd = [binary, "--print", "--output-format", "text", "--model", model, *_CLI_FLAGS]

    for attempt in range(2):
        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=env,
            )
            if result.returncode != 0:
                raise RuntimeError(f"claude CLI failed: {result.stderr.strip()}")
            return result.stdout.strip()
        except RuntimeError:
            if attempt < 1:
                continue
            raise
    raise AssertionError("unreachable")  # satisfy mypy


def extract_json(raw: str) -> dict[str, object]:
    """Extract a JSON object from a model response that may have preamble or fencing.

    With thinking disabled the model sometimes emits a preamble before the JSON
    (usually wrapped in a ```json fence), so locate the JSON object rather than
    assuming the whole response is pure JSON.
    """
    text = raw.strip()
    fenced = _JSON_FENCE.search(text)
    if fenced:
        text = fenced.group(1).strip()
    else:
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end > start:
            text = text[start : end + 1]
    result: dict[str, object] = json.loads(text)
    return result
