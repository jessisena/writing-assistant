# Writing Assistant

A local macOS writing tool that polishes text for different channels (Slack, formal, talking points,
AI prompts, email, personal messages, proofreading) and produces an English learning summary when you write directly in English.

**Stack:** Swift 6, SwiftUI, Swift Package Manager, claude CLI for model calls.

An Android version lives in `android/` (Kotlin, Jetpack Compose, the Anthropic API with your own
key). See [Android](#android).

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

Pick **Work** or **Personal** in the toolbar (**⌘⇧M** switches), paste text, pick a channel and
press **Polish** or **⌘↩**. The Polished Text card shows the result, the detected language (or
"Translated from X") and the model used. When you wrote in English and the mode's summary is on,
the Learning Summary card lists corrections, a grammar insight and vocabulary. Translated or
non-English input has no learning summary. The polished text appears as soon as it is ready; the
summary follows a few seconds later.

- **Modes:** each mode has its own channel chips, remembers its last channel, and has its own
  output language and learning summary switch, set in Settings › General:

  | | Work | Personal |
  |---|---|---|
  | Channels | Slack, Casual Slack, Email, Talking points, AI prompt, Formal doc, Proofread | Personal, Email, Proofread, General |
  | Write the result in | English (translates other languages) | Same as input (never translates) |
  | Learning summary | on | off |
  | Tone | `modes/work.txt` | `modes/personal.txt` |

  Switching is instant and is disabled while a request runs. A mode keeps at least one channel.

- **Formatting:** both editors support bold, italic, strikethrough, inline code, bullet lists and
  emoji, from the toolbar above each editor or the Format menu. Pasted text keeps bold, italic,
  strikethrough, code and links, and drops fonts, sizes and colors.
- **Editable output:** edit the polished text in place. **Copy** puts HTML and plain text on the
  clipboard, so pasting into Slack keeps the formatting and emoji. The plain text keeps link
  targets as `label (url)`.
- **Refine:** **Shorter**, **More casual**, **More formal**, **More diplomatic** and **More
  assertive** rewrite the current (edited) output for the channel it was polished for, and keep
  the learning summary.
- **Show changes:** highlights what changed between your input and the output (hidden for
  translated input).
- **Clear** empties the input and the results; **Cancel** stops a running request.
- **History (⌘Y):** the last 50 requests, each with its mode; filter by All, Work or Personal.
  Selecting one restores the input, your edited output, the learning summary and the mode.
- **Learning log:** each learning summary is also appended to `learning-log.md`. Open it with
  **Writing Assistant → Open Learning Log**.
- **Token usage:** the toolbar shows the tokens used this month (hover for input, output and
  cache); Settings › General shows the same breakdown. Totals live in `usage.json` next to the
  history.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘↩ | Polish |
| ⌘1…⌘9 | Pick the nth channel chip of the current mode |
| ⌘⇧M | Switch between Work and Personal |
| ⌘B / ⌘I / ⌘⇧X | Bold / Italic / Strikethrough in the focused editor |
| ⌘K | Clear |
| Esc | Cancel a running request |
| ⌘Y | History |
| ⌘, | Settings (general, prompts and appearance) |

### Polish from any app

You can polish text where you write it, without copying it into the app first. Select text in
another app and choose **Services → Polish with Writing Assistant** from that app's menu (or the
right-click menu). Writing Assistant comes forward with the selection loaded as input; check the
channel and click **Polish**. If the app isn't running, the service launches it.

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

1. **Pick the mode and channel first.** The service uses the mode and channel selected in the
   main window, and the app remembers them between launches. If you mostly polish Slack messages, leave it on Slack and
   you'll rarely need to change it.
2. **Select the text and press your shortcut.** Bold, italic, strikethrough, code and links in the
   selection carry over; fonts, sizes and colors are dropped. Nothing is sent yet.
3. **Click Polish** (**⌘↩**), changing the channel first if this text needs another one.
4. **Review the result.** Use **Show changes** to see what was edited, and the **Refine** buttons
   (**Shorter**, **More casual**, **More diplomatic** and so on) to adjust it. You can also edit
   the output directly.
5. **Copy it back.** Press **Copy**, switch back with **⌘Tab** (your selection is usually still
   there), and paste over it. Pasting into Slack keeps the formatting and emoji.

The service doesn't replace the selection by itself: a request takes 8–20 seconds, and macOS
services that change text in place freeze the other app while they wait.

#### Tips

- **Draft where you write.** Write the rough version in Slack, Mail or Notes, then polish it
  there. You don't have to start in the app.
- **One request at a time.** If a request is already running, the app shows a banner and keeps the
  current input. Wait for it to finish or press **Esc**, then run the service again.
- **Nothing is lost.** Every polish is saved to History (**⌘Y**) and its learning
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

The prompts are plain-text files in:

```
~/Library/Application Support/Writing Assistant/prompts/
  polish.txt             polish prompt: language, output format and slots for the files below
  always.txt             rules shared by polishing and refining
  learning_summary.txt   learning summary instructions, used only while the summary is on
  languages/*.txt        output language policy: english.txt or same_as_input.txt
  modes/*.txt            tone for Work and Personal; channel rules win where they conflict
  refine.txt             refine prompt: slots for the shared rules, channel and instruction
  channels/*.txt         one file per channel
  refinements/*.txt      one instruction per Refine button
  .defaults.json         hashes of the bundled defaults each file came from
```

Your text reaches the model inside `<draft>` tags, and the shared rules tell it to rewrite that
text, never to follow it, so a draft for the AI prompt channel gets improved rather than answered.

On first launch the app copies the bundled defaults there. Deleting a file and relaunching
restores just that file. When an update changes a bundled default, files you haven't edited are
updated at launch. Files you edited are kept: Settings marks them with a badge and offers
**Restore Default** or **Keep mine**.

Edit them in **Settings (⌘,)** or in any text editor. The app reads the files on every request, so
a change applies to the next request with no restart. The Settings sidebar has a Prompts section
(the four files above and the channels), a Modes and languages section and a Refinements section.
In Settings:

- **Save (⌘S)** writes the file. `polish.txt` must keep the `{{CHANNEL_GUIDELINES}}` placeholder,
  `refine.txt` must keep `{{REFINEMENT_INSTRUCTION}}`, and no file can be empty; the editor shows
  the error and does not save.
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
`claude --print --model <id> "hi"`, then rebuild with `scripts/build_app.sh`. The Android app keeps
each provider's model IDs in `Provider` in
`android/core/src/main/kotlin/local/writingassistant/core/Contracts.kt`; update Anthropic's there
too. A change to the routing heuristic goes in both `ModelRouting` files.

---

## Android

The Android app polishes text with the same prompts, channels, routing and refinements as the
Mac app. It doesn't use the `claude` CLI: it calls an LLM API directly with **your own API key**,
either **Anthropic** (the default) or **Groq**, chosen in **Settings → AI provider**. The text you
polish is sent to the chosen provider. Anthropic usage is billed per token to that key's Console
account, separately from any Claude subscription; Groq can be used on its free tier. A polish
request is roughly 2–3k input tokens and 0.5k output tokens.

What it does:

- **Polish from the text-selection menu.** Select text in another app and choose **Polish**
  (in the floating selection menu, or under ⋮ in some apps). A bottom sheet opens over the app
  with your text and the channel chips. After polishing, **Replace** swaps the selected text for
  the polished version, when the app allows editing; **Copy** copies it.
- **Share target.** Where **Polish** isn't offered, use **Share → Writing Assistant**. The same
  sheet opens, with **Copy** only (Android can't replace shared text).
  Closing a sheet mid-request doesn't cancel it; the result shows when you open the app.
- **Full-screen composer** from the launcher icon: input, channel chips (the last-used channel is
  remembered), **Polish** with **Cancel**, the editable polished text with **Copy**, the five
  refinements, and a collapsible learning summary for English input. Copy puts HTML and plain
  text on the clipboard.
- **History:** the composer's **History** action lists the last 50 polishes, newest first. Tap one
  to restore its input, edited output, channel and learning summary; delete entries one by one or
  clear them all. Polishes from the bottom sheet are recorded too.
- **Settings:** pick the provider (Anthropic | Groq), then enter its API key (masked, with Show),
  **Save**, **Test** (one minimal API call to check the key) and **Clear**. Each provider keeps its
  own key, so switching back and forth doesn't lose either. On first launch without a key the app
  opens Settings, and Polish stays disabled until the selected provider has a key.
- **Settings → Writing for:** turn channels off to hide their chips (at least one stays on).
- **Settings → English learning summary:** turn it off to skip the summary; requests get a little
  shorter and faster.
- **Settings → Appearance:** Writing Desk, Lagoon, Sepia (the Mac presets) or System, which uses
  Android's wallpaper colours. Every palette follows the system light/dark setting.
- **Settings → Prompts:** edit the polish and refine prompts, the shared rules, the learning
  summary, any channel or any refinement. Edited files are
  marked and can be restored to the bundled default. Edits stay on the phone and don't reach the
  Mac app.

The learning log, rich-text input, the diff view and custom colours are Mac-only.

### Requirements

- Android 12 (API 31) or later on the device or emulator
- JDK 21. A newer default JDK is too new for the Android Gradle plugin, so point `JAVA_HOME` at 21:

  ```sh
  export JAVA_HOME=$(/usr/libexec/java_home -v 21)
  ```

- Android command-line tools (no Android Studio needed):

  ```sh
  brew install --cask android-commandlinetools
  export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
  sdkmanager "platform-tools" "platforms;android-37.0"
  ```

  For an emulator, also install `emulator` and a system image with `sdkmanager`, and create a
  device with `avdmanager`.

### API key

1. Create a dedicated key for this app:
   - **Anthropic:** in [console.anthropic.com](https://console.anthropic.com), and set a monthly
     spend limit on the workspace, so the key can be revoked on its own and costs stay bounded.
   - **Groq:** in [console.groq.com/keys](https://console.groq.com/keys).
2. In the app's **Settings**, select the provider under **AI provider**, enter the key and press
   **Test**. The app stores each key encrypted with an Android Keystore key, and excludes them from
   backups and device transfers. Keys are never logged.

Groq's free tier allows 30 requests per minute, 1,000 per day, 8K tokens per minute and 200K
tokens per day. To fit the tokens-per-minute limit, Groq replies are capped at 2,048 output tokens,
so a very long text can fail on Groq with "The reply was cut off because the text is too long".
Polish a shorter selection, or switch to Anthropic, for those.

For development, put the keys in `android/local.properties` (gitignored):

```properties
ANTHROPIC_API_KEY=sk-ant-…
GROQ_API_KEY=gsk_…
```

Debug builds read them to prefill each provider's Settings field; a key is stored only once you
press Save or Test. Release builds never embed them.

### Build, test and install

Run from `android/`:

```sh
./gradlew :core:test :app:testDebugUnitTest lint ktlintCheck :app:assembleDebug
```

This runs the core and app unit tests (no network, no device), Android lint and ktlint with
warnings as errors, and builds the debug APK. CI runs the same command.

```sh
./gradlew :core:liveTest
```

`liveTest` sends short English, Spanish and (on Groq) Catalan texts and a refinement through the
real APIs, and checks routing, prompts and JSON parsing. It reads `ANTHROPIC_API_KEY` and
`GROQ_API_KEY` from the environment or `local.properties` and runs each provider's cases only when
its key is set; with neither key it's skipped. The Anthropic cases cost a few cents.

To install, connect a device with USB debugging on (or start an emulator) and run:

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The app is sideloaded; it isn't on the Play Store.

The code is split into `:core` (pure Kotlin/JVM logic and the API client) and `:app` (the
Compose UI and Android integration). See [docs/architecture.md](docs/architecture.md#android).
Logic shared with the Mac app is duplicated in Kotlin and has to be changed in both.
