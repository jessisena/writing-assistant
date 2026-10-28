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

Drag `~/Applications/Writing Assistant.app` to the Dock to pin it.

To update the installed app after changing or pulling code, rerun the script with `--relaunch`:

```sh
scripts/build_app.sh --relaunch
```

It quits the running app before replacing it and opens the new build afterwards. Without the
flag, a running app keeps the old version until you quit and reopen it. The app is only quit
after the build succeeds, so a broken build leaves the running app alone.

---

## Using the app

Paste text, pick a channel (Formal is the default), and press **Process** or **⌘↩**. The Polished
Text card shows the result, the detected language (or "Translated from X") and the model used.
When you wrote in English, the Learning Summary card lists corrections, a grammar insight and
vocabulary. Translated input has no learning summary.

- **Formatting:** both editors support bold, italic, strikethrough, inline code, bullet lists and
  emoji, from the toolbar above each editor or the Format menu. Pasted text keeps bold, italic,
  strikethrough, code and links, and drops fonts, sizes and colors.
- **Editable output:** edit the polished text in place. **Copy** puts HTML and plain text on the
  clipboard, so pasting into Slack keeps the formatting and emoji. The plain text keeps link
  targets as `label (url)`.
- **Refine:** **Shorter**, **More casual** and **More formal** rewrite the current (edited)
  output for the channel it was polished for, and keep the learning summary.
- **Show changes:** highlights what changed between your input and the output (hidden for
  translated input).
- **Clear** empties the input and the results; **Cancel** stops a running request.
- **History (⌘Y):** the last 50 requests. Selecting one restores the input, your edited output
  and the learning summary.
- **Learning log:** each learning summary is also appended to `learning-log.md`. Open it with
  **Writing Assistant → Open Learning Log**.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘↩ | Process |
| ⌘B / ⌘I / ⌘⇧X | Bold / Italic / Strikethrough in the focused editor |
| ⌘K | Clear |
| Esc | Cancel a running request |
| ⌘Y | History |
| ⌘, | Settings (prompts and appearance) |

### Polish from any app

You can polish text where you write it, without copying it into the app first. Select text in
another app and choose **Services → Polish with Writing Assistant** from that app's menu (or the
right-click menu). Writing Assistant comes forward, loads the selection as input and processes it
with the selected channel. If the app isn't running, the service launches it.

#### Set up a shortcut (once)

The Services menu is slow to reach, so give the service a key combination:

1. Open **System Settings → Keyboard → Keyboard Shortcuts… → Services**.
2. Under **Text**, find **Polish with Writing Assistant** and make sure it's checked.
3. Double-click the right side of the row and press a combination, for example **⌃⌥⌘P**.

Pick a combination that apps don't already use: when an app has a menu shortcut with the same keys,
the app's shortcut wins and the service doesn't run. Combinations with three modifiers rarely
clash.

If the entry is missing after installing, log out and back in (the build script already runs
`pbs -update`).

#### Everyday flow

1. **Pick the channel first.** The service uses the channel selected in the main window, and the
   app remembers it between launches. If you mostly polish Slack messages, leave it on Slack and
   you'll rarely need to change it.
2. **Select the text and press your shortcut.** Bold, italic, strikethrough, code and links in the
   selection carry over; fonts, sizes and colors are dropped.
3. **Review the result.** Use **Show changes** to see what was edited, and **Shorter**, **More
   casual** or **More formal** to adjust it. You can also edit the output directly.
4. **Copy it back.** Press **Copy**, switch back with **⌘Tab** (your selection is usually still
   there), and paste over it. Pasting into Slack keeps the formatting and emoji.

The service doesn't replace the selection by itself: a request takes 8–20 seconds, and macOS
services that change text in place freeze the other app while they wait.

#### Tips

- **Draft where you write.** Write the rough version in Slack, Mail or Notes, then polish it
  there. You don't have to start in the app.
- **One request at a time.** If a request is already running, the app shows a banner and keeps the
  current input. Wait for it to finish or press **Esc**, then run the service again.
- **Nothing is lost.** Every polish from the service is saved to History (**⌘Y**) and its learning
  summary goes to the learning log, so you can come back to it later.
- **If the service isn't listed** in an app, the app may not support macOS Services (some apps
  built on Electron or other cross-platform toolkits don't). Copy the text into Writing Assistant
  instead.
- **Empty or whitespace-only selections** are rejected, and the other app shows a short message.

### Data files

```
~/Library/Application Support/Writing Assistant/
  prompts/             live prompts (see below)
  history.json         the last 50 requests
  learning-log.md      learning summaries
```

If `history.json` is damaged, the app moves it to `history.corrupt.json`, starts with empty
history and shows a banner. If the file can't be read at all (or can't be moved aside), the app
leaves it as it is and doesn't save new history until you relaunch.

---

## Prompts

The global rules and the per-channel rules are plain-text files in:

```
~/Library/Application Support/Writing Assistant/prompts/
  polish.txt           global rules and the 4-step pipeline
  channels/*.txt       one file per channel
  refinements/*.txt    one instruction per Refine button
  .defaults.json       hashes of the bundled defaults each file came from
```

On first launch the app copies the bundled defaults there. Deleting a file and relaunching
restores just that file. When an update changes a bundled default, files you haven't edited are
updated at launch. Files you edited are kept: Settings marks them with a badge and offers
**Restore Default** or **Keep mine**.

Edit them in **Settings (⌘,)** or in any text editor. The app reads the files on every request, so
a change applies to the next request with no restart. The Settings sidebar has a Prompts section
(global rules and channels) and a Refinements section. In Settings:

- **Save (⌘S)** writes the file. `polish.txt` must keep the `{{CHANNEL_GUIDELINES}}` placeholder,
  and no file can be empty; the editor shows the error and does not save.
- **Revert** discards unsaved changes.
- **Restore Default** replaces the selected file with the bundled version, after a confirmation.
- **Reveal in Finder** shows the selected file in Finder.

The bundled defaults live in `Sources/WritingAssistantCore/Resources/Prompts/`.

---

## Appearance

**Settings (⌘,) → Appearance** picks the app's colours. Choose one of three presets (Writing
Desk, Lagoon, Sepia), then change any of its six colours: Accent, Sheet, Background, Dividers,
Removed text and Added text. Each colour has a Light and a Dark value, and the app follows the
system appearance. Changes apply to the open window right away. **Reset to Preset** drops your
custom colours; choosing another preset drops them too.

The theme is stored as a JSON string under the `theme` key of the app's defaults, so it can also
be set from the command line (the app reads it at launch):

```sh
defaults write local.writing-assistant theme \
  '{"preset":"lagoon","overrides":{"ink":{"light":"#025F67","dark":"#6FCFC6"}}}'
```

`preset` is `writingDesk`, `lagoon` or `sepia`; override keys are `ink`, `paper`, `desk`, `rule`,
`redPencil` and `marginGreen`; `overrides` can be left out. A value the app can't read is logged
and replaced by Writing Desk.

---

## Logs

The app logs CLI errors and unexpected responses with the subsystem `local.writing-assistant`:

```sh
/usr/bin/log stream --predicate 'subsystem == "local.writing-assistant"'
```

Use the full `/usr/bin/log` path: in zsh, plain `log` is a shell builtin. Or open Console.app and
filter on that subsystem. Errors that say "Check the logs" refer to these.

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
login shell profile, `~/.zprofile`, then try again. The app runs a non-interactive login shell,
which doesn't read `~/.zshrc`.

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
swift format lint --strict -r Sources Tests # lint
```

`scripts/test.sh` wraps `swift test`. With only the Command Line Tools installed, SwiftPM does not
find the Swift Testing framework on its own, so the script passes its framework and library paths
to the compiler and linker. Extra arguments go through to `swift test` (for example
`scripts/test.sh --filter Routing`).

### Checks

Git hooks run through [prek](https://prek.j178.dev), configured in `.pre-commit-config.yaml`:
`swift format lint --strict`, `shellcheck`, `shfmt`, `actionlint`, `zizmor` and `plutil -lint`.
They use the tools on your `PATH`.

```sh
uv tool install prek        # or: brew install prek
brew install shellcheck shfmt actionlint zizmor
prek install                # set up the pre-commit hook
prek run --all-files        # run every check by hand
```

CI (`.github/workflows/ci.yml`) runs the same checks on every pull request and push to `main`, plus
a build with warnings treated as errors and the test suite on a macOS 26 runner. Dependabot keeps
the pinned actions up to date.

### Versioning and releases

Versions follow [Semantic Versioning](https://semver.org). The version lives in
`Resources/Info.plist` (`CFBundleShortVersionString`, shown in **About Writing Assistant**), each
release is tagged `vX.Y.Z`, and [CHANGELOG.md](CHANGELOG.md) lists what changed.

`scripts/release.sh` works out the next version from the
[conventional commit](https://www.conventionalcommits.org) subjects since the last tag (merge
commits are skipped):

| Commit | Bump |
|--------|------|
| `type(scope)!: …` or a `BREAKING CHANGE:` footer | major |
| `feat(…): …` | minor |
| `fix(…): …`, `perf(…): …` | patch |
| `docs`, `chore`, `refactor`, `test`, … | none |

To release, after the changes are merged:

```sh
git switch main && git pull
git switch -c chore/NOJIRA-000_release
scripts/release.sh --dry-run   # preview the version and changelog entry
scripts/release.sh             # update Info.plist and CHANGELOG.md, commit, tag
git push -u origin chore/NOJIRA-000_release && git push origin vX.Y.Z
```

Then open and merge the PR. The tag stays on the release commit, which the merge brings into
`main`. `scripts/test_release.sh` tests the release script against throwaway repositories.

The code is split into `WritingAssistantCore` (logic, no UI, unit-tested) and `WritingAssistant`
(the SwiftUI app). See [docs/architecture.md](docs/architecture.md).

---

## Model routing

Text of 60 words or fewer that looks like English goes to Haiku (faster, uses less quota);
everything else goes to Sonnet. The model name is shown in the Polished Text card header.

The model IDs are constants in `Sources/WritingAssistantCore/ModelRouting.swift`:

```swift
public static let haikuModel = "claude-haiku-4-5-20251001"
public static let sonnetModel = "claude-sonnet-5-5"
```

To change models, update these constants, check the new ID with
`claude --print --model <id> "hi"`, then rebuild with `scripts/build_app.sh`.
