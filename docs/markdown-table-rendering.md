# Markdown Table Rendering Policy

Date: 2026-04-25 (updated 2026-08-28: `WideTableStrategy` / `TableStreamingBehavior`)
Scope: `ForgeLoopTUI` Markdown rendering

## Background

`ForgeLoopTUI` originally used a single hard cutoff for Markdown tables:

- if a rendered table fit within the internal width budget, it became a box table
- if it was wider than that budget, it degraded immediately back to raw Markdown

That behavior was stable, but it had a poor user-facing result for realistic fixtures such as `Examples/Fixtures/markdownview-sample.md`:

- headings, lists, quotes, and code blocks were rendered structurally
- wide tables stayed as raw Markdown even in final output

For terminal applications that want an IDE-like reading experience, this made wide tables feel unfinished.

## What Changed

`ForgeLoopTUI` now exposes public Markdown rendering options that let the caller choose the table-overflow policy.

New public API:

- `MarkdownRenderOptions`
- `TableRenderPolicy`
- `TableOverflowBehavior`
- `WideTableStrategy` *(added 2026-08-28 refresh)*
- `TableStreamingBehavior` *(added 2026-08-28 refresh)*
- `StreamingMarkdownEngine(options:)`
- `TranscriptRenderer(markdownOptions:)`

## New Default Behavior

The default table strategy is now:

1. compact column widths
2. truncate cell contents if needed
3. degrade back to raw Markdown only when the table still cannot fit

Default values:

- `maxRenderedWidth = 80`
- `minColumnWidth = 6`
- `maxColumnWidth = 24`
- `truncationIndicator = "..."` (width-deterministic ASCII: the indicator sits flush against a column's right border, and East-Asian-Ambiguous glyphs like "…" render double-width in some terminal/font configurations, which would push that row's border one cell out; pass `truncationIndicator: "…"` explicitly only for terminals known to render ambiguous characters single-width)
- `overflowBehavior = .compactThenTruncateThenDegrade`

This keeps the default conservative while allowing typical two-column documentation tables to remain structured in terminal output.

## Why This Shape

The policy is intentionally configured at the Markdown rendering layer instead of the terminal-output layer.

Reason:

- `TUI` is responsible for frame output, cursor placement, and redraw behavior
- `StreamingMarkdownEngine` is responsible for turning Markdown into terminal lines
- wide-table handling belongs to content rendering, not ANSI screen management

That means a consuming app such as `ForgeLoop` can decide how aggressive or conservative table rendering should be when it creates `StreamingMarkdownEngine` or `TranscriptRenderer`.

## Example

```swift
import ForgeLoopTUI

// TranscriptRenderer is @MainActor-isolated; configure it on the main actor.
@MainActor
func makeTableRenderer() -> TranscriptRenderer {
    let options = MarkdownRenderOptions(
        tablePolicy: TableRenderPolicy(
            maxRenderedWidth: 96,
            minColumnWidth: 6,
            maxColumnWidth: 28,
            truncationIndicator: "...",
            overflowBehavior: .compactThenTruncateThenDegrade
        )
    )
    return TranscriptRenderer(markdownOptions: options)
}
```

If you want the old behavior (continuation of the example above — same import
and `@MainActor` context):

```swift
let legacyRenderer = TranscriptRenderer(
    markdownOptions: .init(
        tablePolicy: .init(
            maxRenderedWidth: 80,
            minColumnWidth: 6,
            maxColumnWidth: 24,
            truncationIndicator: "…",
            overflowBehavior: .degradeImmediately
        )
    )
)
```

## Wide-Table Readability Strategy

`TableRenderPolicy.wideTableStrategy` controls what happens when box-drawing
readability suffers under heavy truncation:

- `.alwaysBox` *(library default)* — always render as a box table, even when
  heavily truncated. Keeps the historical zero-regression behavior.
- `.autoReadable` — degrade to raw Markdown when readability would be poor,
  judged by two tunable thresholds:
  - `autoReadableTruncatedCellThreshold` (default `0.4`) — how much cell
    truncation is tolerated before the table is considered unreadable.
  - `autoReadableTrimmedWidthThreshold` (default `0.3`) — how much overall
    width trimming is tolerated.

Consumers opt into `.autoReadable` explicitly; the default stays `.alwaysBox`.

## Streaming Behavior for Incomplete Tables

`MarkdownRenderOptions.tableStreamingBehavior` controls how a table is
presented while its rows are still streaming in:

- `.monotonic` *(default)* — parse and render currently valid rows without
  regressing to raw Markdown while the last row is incomplete.
- `.strict` — keep raw Markdown until the current table block is fully
  terminated.

## Compatibility Notes

- Existing `TranscriptRenderer()` and `StreamingMarkdownEngine()` calls keep working and use the new default policy
- Callers that want strict legacy degradation can opt back into `.degradeImmediately`
- The API remains library-driven: defaults live in `ForgeLoopTUI`, but callers control the final policy
