# Markdown Table Rendering Policy

Date: 2026-04-25
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
- `truncationIndicator = "…"`
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

let options = MarkdownRenderOptions(
    tablePolicy: TableRenderPolicy(
        maxRenderedWidth: 96,
        minColumnWidth: 6,
        maxColumnWidth: 28,
        truncationIndicator: "...",
        overflowBehavior: .compactThenTruncateThenDegrade
    )
)

let renderer = TranscriptRenderer(markdownOptions: options)
```

If you want the old behavior, use:

```swift
let renderer = TranscriptRenderer(
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

## Compatibility Notes

- Existing `TranscriptRenderer()` and `StreamingMarkdownEngine()` calls keep working and use the new default policy
- Callers that want strict legacy degradation can opt back into `.degradeImmediately`
- The API remains library-driven: defaults live in `ForgeLoopTUI`, but callers control the final policy
