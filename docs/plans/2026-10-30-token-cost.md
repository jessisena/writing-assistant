# Token cost: show what this month's tokens cost, not just how many

## Context

The macOS app counts tokens per calendar month (`UsageStore`, `usage.json`) and shows the total in
the toolbar ("48.2K tokens this month") and Settings › General (total plus input / output /
cache write / cache read / requests). The user wants to see the cost as well.

The claude CLI already prices every run. Its final stream-json `result` event carries
`total_cost_usd` (fixture `Tests/WritingAssistantCoreTests/Fixtures/stream-json-reply.jsonl`:
`0.0219465` for one Haiku 4.5 polish) and a per-model `modelUsage[…].costUSD` with
`"costBasis": "list"`. Using that number instead of an in-app price table means:

- no prices to keep up to date when models or prices change;
- cache writes are priced correctly: the CLI writes 1-hour cache entries
  (`cacheCreationEphemeral1hInputTokens`), which cost 2x input, versus 1.25x for 5-minute ones, and
  `TokenUsage` doesn't record which kind it was;
- Haiku and Sonnet routing is priced per model without the app knowing which model ran.

The app runs `claude` with the user's subscription login (no `ANTHROPIC_API_KEY`), so this is what
the tokens would cost at API list prices, not what the user is billed. The UI says so.

Scope: macOS only. Android has no usage tracking yet (follow-up, see the end).

## Changes

### Core (`Sources/WritingAssistantCore`)

- `StreamJSONReader.swift`: `StreamResult` gains `costUSD: Double?`, read from `total_cost_usd`
  (`as? Double`; missing or non-numeric → nil).
- `Contracts.swift`:
  - `ClaudeReply` gains `costUSD: Double?`.
  - `MonthlyUsage` gains `costUSD: Double` (`.zero` has 0).
  - `UsageRecording.record(_ tokens: TokenUsage, costUSD: Double?)`.
- `ClaudeCLI.swift`: pass `result.costUSD` into `ClaudeReply`.
- `PolishService.swift`: `record(reply.usage, costUSD: reply.costUSD)`. A reply with tokens but no
  cost still counts its tokens and adds 0 to the cost.
- `UsageStore.swift`: `record` adds `costUSD ?? 0` to the month. Error messages say "usage" rather
  than "token usage" where they now cover cost too.

`usage.json` month entries become `{"tokens": {…}, "requests": n, "costUSD": 0.42}`.

### App (`Sources/WritingAssistant`)

- `MonthlyUsageLabel.swift`:
  - `compactSummary`: "48.2K tokens · $0.42 this month".
  - `fullSummary` (accessibility): "48,234 tokens, about $0.42 at API prices, this month".
  - `breakdown` (tooltip): the existing rows plus "Cost at API prices: $0.4213".
  - A `formattedCost(locale:)` helper: USD currency style, 2 decimals; "<$0.01" when above 0 but
    under a cent; "$0.00" for 0. The tooltip and Settings use 4 decimals, since single requests
    cost about $0.02.
- `GeneralSettingsView.swift`: "This month" section gets an "Estimated cost" row under
  "Total tokens", and a footer: "At API list prices, as reported by Claude Code. Your Claude
  subscription isn't charged per token."

## Tests

- `StreamJSONReaderTests` / `ClaudeCLITests`: the fixture yields `costUSD == 0.0219465`; a result
  without `total_cost_usd` yields nil; a string value yields nil.
- `PipelineTests`: the fake `UsageRecording` receives the reply's cost, including for a reply that
  then fails to parse; a reply with no cost passes nil.
- `UsageStoreTests`: two records sum their costs; a nil cost adds 0 but still counts the request;
  a new month starts at $0.
- `MonthlyUsageLabel` tests (alongside `AppModelUsageTests`): 0 → "$0.00", 0.004 → "<$0.01",
  0.4213 → "$0.42" compact and "$0.4213" in the breakdown, with a fixed `en_US` locale.
- `AppModelUsageTests`: after a request, `monthlyUsage.costUSD` reflects the recorded cost.

Run `scripts/test.sh` and `swift format lint -r Sources Tests`; zero warnings.

## Docs

`docs/architecture.md` › "Progressive display, summary setting and token count": cost comes from
`total_cost_usd`, is stored per month next to the tokens, is an API-list-price estimate, and shares
the existing undercount (cancelled runs and retried first attempts aren't counted).

## Manual check

`scripts/build_app.sh`, polish once with short English (Haiku) and once with long text (Sonnet):
the toolbar cost rises by about the amounts in `usage.json`, the Sonnet request by more.

## Decisions

1. **Existing `usage.json`.** It only exists on the dev machine (PR #15 is unreleased).
   `costUSD` is required, no fallback decoding; trash the local file before running the new build
   (otherwise it's moved aside as damaged on first launch and the banner shows once).
2. **Toolbar text.** Tokens and cost together.
3. **Per-model split** (Haiku vs Sonnet cost from `modelUsage`): left out.

## Follow-up (not in this plan)

Android calls the API with the user's own key, so cost there is real money. It would need its own
price table (the Messages API returns tokens, not cost) and a usage store; worth a separate plan.
