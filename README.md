# ForgeLoopTUI

[![Release](https://img.shields.io/github/v/release/BiBoyang/ForgeLoopTUI?display_name=tag)](https://github.com/BiBoyang/ForgeLoopTUI/releases)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/BiBoyang/ForgeLoopTUI/blob/main/LICENSE)

`ForgeLoopTUI` is a lightweight Swift terminal UI library for streaming AI transcripts.

It provides:
- event-driven transcript rendering
- terminal-friendly Markdown presentation for headings, lists, blockquotes, fenced code blocks, and tables
- in-place streaming replacement with `inlineAnchor` / `legacyAbsolute` strategies
- **commit / live partition rendering**: committed lines are append-only, live lines are efficiently diffed; committed append uses `ESC[nL` fast path to avoid redrawing unchanged live content
- **live budget with overflow settlement**: when live lines exceed a configured budget, oldest lines are automatically settled into committed to avoid unbounded growth. Budget can be counted by logical line count (`.logicalLines`, default for back-compat) or by wrap-aware physical rows (`.physicalRows`, recommended for streaming Markdown / narrow terminals). The same algorithm is shared by `TUI.liveBudget` and `FrameComposer`'s optional `liveOverflow: .settleThenClip` policy
- **selectable cursor positioning**: `TUI.cursorPositioningMode` defaults to `.relative` (existing relative-move sequences for back-compat) and offers `.marker` for physical-row + CHA absolute-column positioning, recommended when accurate hardware cursor position matters (e.g. Chinese IME candidate windows on multi-line wrapped input)
- **tool execution placeholders** (`running...` -> `done/failed`) with stable slot ordering for out-of-order completions
- **resize-safe anchoring**: physical row caches are recomputed on terminal resize so diff cursor math stays correct
- single-line text input primitives with CJK-safe cursor accounting and horizontal scrolling
- modal/list-picker primitives for temporary terminal overlays
- semantic ANSI styling with plain-text fallback
- ANSI-aware physical row accounting for wrapped lines
- safe stdout writing with `EINTR` / `EAGAIN` handling
- logical-line normalization for embedded `\n` / `\r\n`
- reusable streaming transcript append planner for scrollback-safe terminal output
- **declarative component DSL** (`Component` protocol, `VStack`, `@ComponentBuilder`) for composable UI without touching runtime internals
- **frame composition** (`ComposedFrame`, `FrameComposer`) to assemble committed/live regions from multiple components
- **viewport budget clipping** (`LayoutBudget`) with physical-row-aware tail retention and optional overflow markers
- `Terminal` protocol with `StdoutTerminal` and `VirtualTerminal` for testable, decoupled output

## Requirements

- Swift 6
- macOS 14+

## Install (SwiftPM)

```swift
dependencies: [
    .package(url: "https://github.com/BiBoyang/ForgeLoopTUI.git", from: "0.1.2")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["ForgeLoopTUI"]
    )
]
```

## Quick Start

```swift
import ForgeLoopTUI

@MainActor
func demo() {
    let tui = TUI()
    let renderer = TranscriptRenderer()

    renderer.apply(.messageStart(message: .user("write hello world")))
    renderer.apply(.messageStart(message: .assistant(text: "", errorMessage: nil)))
    renderer.apply(.messageUpdate(message: .assistant(text: "Hello", errorMessage: nil)))
    renderer.apply(.messageUpdate(message: .assistant(text: "Hello world", errorMessage: nil)))
    renderer.apply(.messageEnd(message: .assistant(text: "Hello world", errorMessage: nil)))

    renderer.apply(.toolExecutionStart(toolCallId: "1", toolName: "read", args: "{\"path\":\"README.md\"}"))
    renderer.apply(.toolExecutionEnd(toolCallId: "1", toolName: "read", isError: false, summary: "Loaded 120 lines"))

    tui.requestRender(lines: renderer.transcriptLines)
}
```

## Rendering Modes

- `inlineAnchor`:
  - first frame prints directly without clearing the screen
  - later frames rewrite only the dirty tail when possible
  - automatically falls back to full redraw if the frame grows beyond the visible terminal height
- `legacyAbsolute`:
  - always does `ANSI clear + home + redraw`

You can also use:

- `render(committed:live:cursorOffset:)` for two-region rendering where committed is append-only and live is diff-friendly
- `render(committed:live:cursorPlacement:)` for two-region rendering with 2D cursor positioning (used by multi-line input)
- `liveBudget` on `TUI` to cap live region size with automatic overflow settlement
- `appendFrame(lines:)` to write plain terminal output without retained-mode redraw
- `resetRetainedFrame()` to drop inline redraw state before switching modes
- `transcriptLines` as the stable read-only snapshot of rendered transcript lines
- `StreamingTranscriptAppendState` to compute transcript deltas for append-only streaming UIs
- `TranscriptRenderer.activeStreamingRange` to know which transcript range is still mutable
- `TranscriptRenderer.slotOrderedToolIDs` to inspect pending tools in start order

Low-level logical-line and terminal-metric helpers are kept as implementation details; the stable consumer-facing API is centered on `TUI`, `TranscriptRenderer`, `RenderEvent`, `RenderMessage`, `Style`, `prefixedLogicalLines`, and `StreamingTranscriptAppendState`.

## Interaction Primitives

`ForgeLoopTUI` also exposes reusable terminal interaction building blocks that do not depend on any chat or agent semantics:

- `Style`
  - semantic styles such as `header`, `dimmed`, `running`, `success`, `warning`, `error`, and `selection`
  - `automatic` / `ansi` / `plain` rendering modes
- `TextInputState`
  - single-line editor state with cursor movement, backspace/delete, `Home` / `End`, and horizontal scrolling
  - `render(prefix:totalWidth:)` returns a line plus `cursorOffset` ready for `TUI.requestRender`
- `MultiLineInputState`
  - multi-line editor state with cursor movement across lines, backspace/delete (including line-join), newline insertion, `Home` / `End`, kill-to-line-start/end
  - `render()` returns lines plus a `CursorPlacement` (2D cursor anchor) ready for `TUI.render(committed:live:cursorPlacement:)`
  - `handle(_:)` accepts `MultiLineInputAction` (insert, insertText, insertNewline, backspace, deleteForward, move, kill, replace, clear)
  - optional `viewport: Viewport?` enables soft-wrap aware `.moveUp` / `.moveDown` — vertical moves walk by visual rows so a single long line wrapping across multiple physical rows is navigated as the user sees it
- `ModalRenderer`
  - lightweight title/body/footer modal framing
- `ListPickerState` + `ListPickerRenderer`
  - arrow-key style selection state and renderer for modal pickers such as `/model`
- `PromptHistory`
  - minimal input history for up/down key navigation (`commit` / `prev` / `next` / `reset` / `isAtCurrent`)
  - purely a navigation primitive — carries no business semantics (no conversation-id, no session-key, no persistence)
  - lives in `ForgeLoopTUI`; CLI consumers compose it, never re-implement it
- `KeyStroke` / `KeySequence` / `KeyBinding` / `KeybindingRegistry` / `KeyResolver` / `ResolvedKey`
  - declarative key bindings with single-key and multi-key chord support
  - `KeybindingRegistry<Action>` enforces a strict three-state match (`miss` / `prefix` / `exact`) and rejects prefix conflicts at registration time
  - `KeyResolver<Action>` buffers chord prefixes, releases them as passthrough on timeout (driven by an injectable `InputClock`) or mismatch, and always passes paste events straight through
  - see `docs/integration-guide.md` §7 for a worked example

Example:

```swift
import ForgeLoopTUI

var input = TextInputState(text: "帮我看看这个函数的问题")
input.handle(.moveToEnd)
let renderedInput = input.render(prefix: Style.prompt("❯ ", mode: .ansi), totalWidth: 24)

let tui = TUI()
tui.requestRender(lines: [renderedInput.line], cursorOffset: renderedInput.cursorOffset)

var picker = ListPickerState(
    title: "Select a model",
    subtitle: "provider: openai",
    items: [
        .init(id: "gpt-4.1", title: "gpt-4.1"),
        .init(id: "gpt-4o", title: "gpt-4o"),
        .init(id: "o3-mini", title: "o3-mini"),
    ],
    selectedIndex: 1
)

let pickerLines = ListPickerRenderer(styleMode: .ansi).render(state: picker)
tui.requestRender(lines: pickerLines)
```

## Customizing Wide Tables

Wide Markdown tables are now configurable by the caller. `ForgeLoopTUI` ships with a default policy that tries:

1. compact column widths
2. truncate long cell contents
3. degrade to raw Markdown only if the table still cannot fit

If your app wants different behavior when calling `ForgeLoopTUI`, configure it at renderer/engine creation time:

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

If you prefer the old “too wide means keep raw Markdown” behavior:

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

The public types involved are:

- `MarkdownRenderOptions`
- `TableRenderPolicy`
- `TableOverflowBehavior`
- `StreamingMarkdownEngine(options:)`
- `TranscriptRenderer(markdownOptions:)`

For design rationale and change notes, see `docs/markdown-table-rendering.md`.

## Stability & SemVer

- `docs/public-api-surface.md` — complete catalog of public APIs with stability tiers (Stable / Provisional / Internal-detail), including API stability commitments around defaults, errors, and concurrency
- `docs/semver-and-api-stability.md` — SemVer policy, breaking-change definitions, deprecation window, and compatibility test requirements
- `docs/release-checklist.md` — step-by-step release validation (tests, docs, API audit, performance gate, tag)
- `docs/performance-baseline.md` — baseline gates for hot paths (settlement planner, multi-line input editing, key resolver passthrough); enforced by `PerformanceBaselineTests`

## Roadmap and Architecture Docs

- `docs/module-dataflow-and-dependency-map.md`
  - module collaboration map and dependency direction rules
  - includes an ASCII pipeline for "event -> ANSI handling -> terminal output"

## Event Model

- `RenderMessage`: user / assistant / tool
- `RenderEvent`:
  - `messageStart`
  - `messageUpdate`
  - `messageEnd`
  - `toolExecutionStart`
  - `toolExecutionEnd`

You can adapt your own agent events to `RenderEvent` and keep this library independent from your business layer.

## Development

```bash
swift test
```

For a fuller testing workflow, see `TESTING.md`.

## Examples

There are three runnable local example packages:

- `Examples/MinimalStreamingDemo`: stability / public-API smoke example
- `Examples/MarkdownShowcase`: Markdown presentation example
- `Examples/MinimalAIApp`: minimal interactive AI terminal app (prompt, streaming, cancel, declarative keybindings with readline-style chords, history). See `Examples/MinimalAIApp/KEYS.md` for the full keymap and interaction manual.

Run the smoke example with:

```bash
cd Examples/MinimalStreamingDemo
swift run
```

Run it with a custom fixture:

```bash
cd Examples/MinimalStreamingDemo
swift run MinimalStreamingDemo ../Fixtures/markdownview-sample.md
```

The smoke example shows:
- a user prompt rendered once
- assistant streaming with append-only transcript deltas
- final flush on `messageEnd`
- a simple tool start/end placeholder flow

Run the minimal AI app with:

```bash
cd Examples/MinimalAIApp
swift run
```

Run the Markdown presentation example with:

```bash
cd Examples/MarkdownShowcase
swift run
```

Run the built-in edge-case fixture with:

```bash
cd Examples/MarkdownShowcase
swift run MarkdownShowcase edge-cases
```

Run the long mixed-structure fixture with:

```bash
cd Examples/MarkdownShowcase
swift run MarkdownShowcase long-mixed
```

Run the narrow-terminal stress fixture with:

```bash
cd Examples/MarkdownShowcase
swift run MarkdownShowcase narrow-terminal
```

Run all bundled Markdown fixtures in one pass with:

```bash
cd Examples/MarkdownShowcase
swift run MarkdownShowcase --all
```

Run it with a custom fixture:

```bash
cd Examples/MarkdownShowcase
swift run MarkdownShowcase ../Fixtures/markdownview-sample.md
```

The Markdown example is intentionally separate from the smoke example so presentation tuning does not blur the public-API/stability contract.
It now ships with a default showcase fixture, a dedicated table edge-case fixture, a longer mixed-structure fixture, and a narrow-terminal stress fixture so rendering tweaks can be checked against ideal, degraded, long-form, and tight-width output.

## Related Projects

- `ForgeLoop` (main coding-agent application): https://github.com/BiBoyang/ForgeLoop

## Suggested GitHub Topics

- `swift`
- `tui`
- `terminal-ui`
- `llm-agent`
- `streaming`
