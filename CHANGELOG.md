# Changelog

All notable changes to Writing Assistant. Versions follow [Semantic Versioning](https://semver.org).
`scripts/release.sh` adds each new entry from the conventional commits since the last tag.

## [1.1.0] - 2026-10-28

### Features

- add theme colour tokens
- add short channel names for chips
- add editor line spacing, borderless mode and focus state
- keep channel, track request start and undo clear
- add diff change count
- track which refinement is running
- add wrapping flow layout
- turn composer into a writing sheet
- drop header, add desk background and ink tint
- proofreading marks and change count in diff
- restyle result cards and add edit-changes switch

### Fixes

- keep polish button legible in dark mode and while polishing
- cross-fade results phases in a zstack
- fade results out without sliding on removal
- fire copy haptic on every copy
- save newer output before undoing clear
- address composer review findings

## [1.0.0] - 2026-10-28

First tagged release.

### Features

- Native SwiftUI macOS app that polishes text through the `claude` CLI, with a prompt per
  channel and model routing by length and language
- Rich text editing with Markdown round trip, Slack-friendly copy, history and a learning log
- Services menu entry "Polish with Writing Assistant"
- Prompt editor in Settings

### Fixes

- Bullet lists continue on Return and pasted text arrives unformatted
- Emoji emphasis and bare URLs survive the Markdown round trip
