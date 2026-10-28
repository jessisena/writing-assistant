# Theme palettes in Settings

## Context
Colours are fixed today: `Sources/WritingAssistant/Theme.swift` defines six static tokens
(`ink`, `paper`, `desk`, `rule`, `redPencil`, `marginGreen`), each a light/dark pair built by
`dynamic(light:dark:)`. The user wants to pick one of 3 preset palettes in Settings and then
customise its colours. Decisions taken: presets keep a light + dark variant and follow the
system; all 6 tokens are customisable (one picker for light, one for dark); Settings becomes a
`TabView` with **Prompts | Appearance**.

## Presets
| Token (UI label) | Writing Desk (current, default) | Lagoon (user's palette) | Sepia (new) |
|---|---|---|---|
| ink (Accent) | 33378A / A9ADF2 | **025F67** / 6FCFC6 | 8A4B1F / E8B07F |
| paper (Sheet) | FDFDFC / 1F2024 | **F7F6F2** / 0B2A45 | FBF6EC / 2A241D |
| desk (Background) | EDEFF3 / 141519 | E4E8EA / **063154**-derived 041F35 | EFE6D6 / 1C1813 |
| rule (Dividers) | D9DCE3 / 34363D | **BCC5CC** / 24435C | DCCFB8 / 433A2E |
| redPencil (Removed) | B3263E / FF8597 | B8463A / FF8F80 | A8322A / FF8C7A |
| marginGreen (Added) | 1D7A52 / 63D6A3 | **2F9D94** / 63D6C8 | 4D7A2A / 9CD67A |

Lagoon maps the given `#2f9d94 #f7f6f2 #bcc5cc #025f67 #063154`: deep teal is the accent (it
has the contrast on cream that the lighter teal lacks), light teal marks added text, navy is the
base of the dark variant. Its red is derived (the palette has none). Values are tuned during
implementation by screenshots in both appearances.

## Design
**Data (`Sources/WritingAssistant/ThemePalette.swift`, new)**
- `enum ThemeToken: String, Codable, CaseIterable` (6 cases, with a `label` for the UI).
- `struct ThemeColor: Codable, Equatable { light: UInt32; dark: UInt32 }`.
- `struct ThemePalette: Equatable { colors: [ThemeToken: ThemeColor] }` with a
  `color(_ token:) -> Color` that uses today's `NSColor(name:dynamicProvider:)` logic, and
  `ink`/`paper`/… convenience properties so call sites read the same.
- `enum ThemePreset: String, Codable, CaseIterable { writingDesk, lagoon, sepia }` with
  `displayName` and `palette`.

**State (`Sources/WritingAssistant/ThemeSettings.swift`, new)** — `@MainActor @Observable`
- Stored: `preset: ThemePreset`, `overrides: [ThemeToken: ThemeColor]`.
- `palette` = preset colours with overrides applied.
- `select(_ preset:)` switches preset and clears overrides (stated in the UI: "Choosing a
  preset resets your custom colours").
- `setColor(_:for:appearance:)`, `resetToPreset()`, `isCustomized`.
- Persisted as one JSON value under UserDefaults key `"theme"` on every change, injected
  `defaults: UserDefaults = .standard` like `AppModel` (`AppModel.swift:85`). Missing or
  malformed JSON, or an unknown preset, falls back to Writing Desk without overrides. The JSON is
  documented so an agent or `defaults write` can set a theme.

**Plumbing**
- Add `EnvironmentValues.theme: ThemePalette` (default Writing Desk). `WritingAssistantApp`
  owns `@State var themeSettings` and applies `.environment(\.theme, themeSettings.palette)` and
  `.tint(themeSettings.palette.ink)` to both scenes (replacing `.tint(Theme.ink)` at lines 32
  and 45).
- Replace every `Theme.x` call site (24, in `ComposerView`, `ResultsView`, `DiffView`,
  `LearningSummaryView`, `HistoryView`, `WritingAssistantApp`) with `@Environment(\.theme)`
  reads. `DiffView`'s `removedColor`/`addedColor` statics become functions of the palette.
- `Theme.swift` loses its static tokens (replace, don't deprecate); `NSColor(hex:)` stays.
  Writing Desk's values move into `ThemePreset.writingDesk` unchanged.
- Out of scope: system colours (`ErrorBanner` red, prompt-editor orange/blue, `.secondary`).

**Settings UI**
- `Settings { TabView { PromptEditorView(...).tabItem("Prompts", systemImage: "doc.text");
  AppearanceSettingsView(settings:).tabItem("Appearance", systemImage: "paintpalette") } }`.
  Keep the prompt editor's current frame inside its tab.
- `AppearanceSettingsView` (new): a row of 3 preset cards (name + 6 swatches, selected one
  outlined in its accent); below, a `Form` with one row per token: label, `ColorPicker` "Light",
  `ColorPicker` "Dark" (`supportsOpacity: false`); a "Reset to preset" button enabled when
  customised. Changes apply live to the open main window.
- `ColorPicker` → hex: `NSColor(color).usingColorSpace(.sRGB)` rounded to `UInt32`; a small
  `NSColor.hexValue` next to `NSColor(hex:)`.

## Tests (`Tests/WritingAssistantTests/ThemeSettingsTests.swift`, new; `TestDefaults.make()`)
- Default is Writing Desk with no overrides; its palette equals today's hex values.
- Selected preset and overrides survive a new `ThemeSettings` on the same suite.
- Malformed JSON / unknown preset / unknown token fall back to the default.
- Selecting a preset clears overrides; `resetToPreset` clears them; `isCustomized` tracks both.
- Override for one appearance leaves the other untouched.
- Hex round-trip: `NSColor(hex:)` → `UInt32` returns the input (property-style loop over
  sample values incl. 0x000000 and 0xFFFFFF).
- `palette.color(.ink)` resolves to the light/dark hex under `.aqua` / `.darkAqua`.
- Update `DiffViewTests.swift:22-40` to compare against a palette instead of `Theme` statics.

## Execution
Plan saved as `docs/plans/2026-10-28-theme-palettes.md` (the existing plans folder). The main
session manages the work and runs subagents in parallel worktrees.

**Wave 0 — contract (main session).** Branch `feat/NOJIRA-000_theme_palettes` from
`origin/main`. Commit the plan plus the shared interface so the workers compile against it:
`ThemePalette.swift` complete (tokens, `ThemeColor`, `ThemePalette`, the 3 presets,
`EnvironmentValues.theme`), and `ThemeSettings.swift` with its public API (`preset`,
`overrides`, `palette`, `isCustomized`, `select`, `setColor`, `resetToPreset`,
`init(defaults:)`) and in-memory behaviour only, no persistence yet.

**Wave 1 — 3 parallel worktree subagents**, each branching from the Wave 0 commit
(`git switch -c <name> feat/NOJIRA-000_theme_palettes`), touching disjoint files:
- **A: persistence + tests.** UserDefaults JSON in `ThemeSettings.swift`, fallbacks, and
  `ThemeSettingsTests.swift` (all bullets in Tests except the hex round-trip).
- **B: environment migration.** Replace all `Theme.x` call sites with `@Environment(\.theme)`,
  remove the static tokens from `Theme.swift`, update `DiffView` and `DiffViewTests`, add the
  palette-resolves-per-appearance test. Wire `themeSettings` + `.environment`/`.tint` into the
  main window scene in `WritingAssistantApp.swift`.
- **C: Appearance tab.** `AppearanceSettingsView.swift`, `NSColor.hexValue` with its
  round-trip test, the Settings `TabView` in `WritingAssistantApp.swift` (only the `Settings`
  scene; B owns the `Window` scene, so the one-file overlap is in separate blocks).

**Wave 2 — integrate (main session).** Merge A, B, C; resolve the `WritingAssistantApp.swift`
merge; full tests + lint; code review; fix findings (in parallel subagents if several); update
`docs/architecture.md` (theme section, UserDefaults key/JSON) and README (Settings →
Appearance); install, screenshots, draft PR; remove worktrees.

## Verification
- `scripts/test.sh` and `swift format lint -r Sources Tests` clean, zero warnings.
- `scripts/build_app.sh --relaunch`; in Settings → Appearance switch each preset and check the
  main window updates live in light and dark mode (screenshots); edit a colour, relaunch, and
  confirm it persists; Reset returns preset values.
