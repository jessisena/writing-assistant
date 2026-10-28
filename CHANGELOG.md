# Changelog

All notable changes to Writing Assistant. Versions follow [Semantic Versioning](https://semver.org).
`scripts/release.sh` adds each new entry from the conventional commits since the last tag.

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
