# Writing Assistant

A local macOS writing tool that polishes text for different channels (Slack, formal, talking points,
AI prompts) and produces an English learning summary when you write directly in English.

**Stack:** Swift 6, SwiftUI, Swift Package Manager, claude CLI for model calls.

**Privacy note:** the text you paste is sent to Anthropic's Claude model via your local `claude`
CLI subscription. No `ANTHROPIC_API_KEY` is needed or used (the app removes it from the CLI's
environment). Input is bounded to 20,000 characters. Like any LLM tool, the model output can be
steered by crafted input (prompt injection); the `was_translated` invariant is enforced in the app
regardless of model output.

---

## Prerequisites

- macOS 14 or later
- Command Line Tools: `xcode-select --install` (Xcode itself is not needed)
- [claude CLI](https://claude.ai/download) installed and authenticated (`claude --version` passes)

---

## Build and install

```sh
scripts/build_app.sh
```

The script builds a release binary, assembles `build/Writing Assistant.app`, signs it ad hoc, and
installs it to `~/Applications/Writing Assistant.app`. A previous install there is moved to the
Trash first. Set `INSTALL_DIR` to install somewhere else:

```sh
INSTALL_DIR=/tmp/wa-test scripts/build_app.sh
```

Drag `~/Applications/Writing Assistant.app` to the Dock to pin it. Rerun the script after pulling
changes.

---

## Using the app

Paste text, pick a channel (Formal is the default), and press **Process** or **⌘↩**. The Polished
Text card shows the result, the detected language (or "Translated from X") and the model used,
with a Copy button. When you wrote in English, the Learning Summary card lists corrections, a
grammar insight and vocabulary. Translated input has no learning summary.

---

## Prompts

The global rules and the per-channel rules are plain-text files in:

```
~/Library/Application Support/Writing Assistant/prompts/
  polish.txt           global rules and the 4-step pipeline
  channels/*.txt       one file per channel
```

On first launch the app copies the bundled defaults there. It only copies files that are missing,
so your edits are never overwritten. Deleting a file and relaunching restores just that file.

Edit them in **Settings (⌘,)** or in any text editor. The app reads the files on every request, so
a change applies to the next request with no restart. In Settings:

- **Save (⌘S)** writes the file. `polish.txt` must keep the `{{CHANNEL_GUIDELINES}}` placeholder,
  and no file can be empty; the editor shows the error and does not save.
- **Revert** discards unsaved changes.
- **Restore Default** replaces the selected file with the bundled version, after a confirmation.
- **Reveal in Finder** opens the prompts folder.

The bundled defaults live in `Sources/WritingAssistantCore/Resources/Prompts/`.

---

## Logs

The app logs CLI errors and unexpected responses with the subsystem `local.writing-assistant`:

```sh
log stream --predicate 'subsystem == "local.writing-assistant"'
```

Or open Console.app and filter on that subsystem. Errors that say "Check the logs" refer to these.

---

## Troubleshooting

### "claude CLI not found"

Apps launched from Finder or the Dock get a minimal `PATH`, so the app looks for `claude` in
`~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, then asks your login shell
(`zsh -lc 'command -v claude'`). Check:

```sh
command -v claude
claude --version
```

If `claude` is installed somewhere else, make sure that directory is on the `PATH` set by your
login shell profile (`~/.zprofile` or `~/.zshrc`), then relaunch the app.

### "Claude returned an error" after a reboot

The CLI's subscription auth may need to be confirmed again. Run `claude` once in a terminal to
re-authenticate, then retry in the app.

### "Claude took longer than 120 seconds"

Each request has a 120 s timeout and is not retried after a timeout. This can happen under heavy
subscription load. Try again; if it keeps happening, check your Claude subscription status.

---

## Development

```sh
swift build                        # debug build
swift run WritingAssistant         # run the app from the terminal
scripts/test.sh                    # run the test suite
swift format lint -r Sources Tests # lint
```

`scripts/test.sh` wraps `swift test`. With only the Command Line Tools installed, SwiftPM does not
find the Swift Testing framework on its own, so the script passes its framework and library paths
to the compiler and linker. Extra arguments go through to `swift test` (for example
`scripts/test.sh --filter Routing`).

The code is split into `WritingAssistantCore` (logic, no UI, unit-tested) and `WritingAssistant`
(the SwiftUI app). See [docs/architecture.md](docs/architecture.md).

---

## Model routing

Text of 60 words or fewer that looks like English goes to Haiku (faster, uses less quota);
everything else goes to Sonnet. The model name is shown in the Polished Text card header.

The model IDs are constants in `Sources/WritingAssistantCore/ModelRouting.swift`:

```swift
public static let haikuModel = "claude-haiku-4-5-20251001"
public static let sonnetModel = "claude-sonnet-4-6"
```

Update `sonnetModel` when a newer Sonnet is available to your CLI, then rebuild.
