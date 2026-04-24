# TESTING

This document describes the recommended testing workflow for `ForgeLoopTUI`.

## Goals

`ForgeLoopTUI` is a terminal UI library, so testing should cover four things:

1. core correctness
2. public API usability
3. terminal rendering behavior
4. real interactive experience

## 1. Default Test Command

Run the full package test suite from the repository root:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test
```

Use this after any non-trivial change.

## 2. Focused Test Commands

When working on a specific subsystem, use targeted test filters.

### `TUI`

Use when changing:

- `Sources/ForgeLoopTUI/TUI.swift`
- `Sources/ForgeLoopTUI/LogicalLines.swift`
- `Sources/ForgeLoopTUI/TerminalMetrics.swift`

Command:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test --filter TUITests
```

This verifies:

- inline first-frame behavior
- legacy full redraw behavior
- append-only output behavior
- retained-state reset behavior

### `TranscriptRenderer`

Use when changing:

- `Sources/ForgeLoopTUI/TranscriptRenderer.swift`
- `Sources/ForgeLoopTUI/RenderEvents.swift`

Commands:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test --filter TranscriptRendererTests
swift test --filter TranscriptRendererToolResultTests
```

This verifies:

- streaming replacement semantics
- multi-line user message handling
- tool placeholder replacement
- multi-line tool summary handling
- blank-line and error rendering behavior

### `StreamingTranscriptAppendState`

Use when changing:

- `Sources/ForgeLoopTUI/StreamingTranscriptAppendState.swift`

Command:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test --filter StreamingTranscriptAppendStateTests
```

This verifies:

- prompt/static-prefix append-once behavior
- growing partial lines are not repeated
- completed streaming lines append once
- final tail flush on stream end

## 3. Public API Smoke Test

`swift test` is not enough for a library. You should also verify that a consumer can use the public API naturally.

Run the included example:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI/Examples/MinimalStreamingDemo
swift run
```

Run the example with a specific fixture:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI/Examples/MinimalStreamingDemo
swift run MinimalStreamingDemo ../Fixtures/markdownview-sample.md
```

This smoke test verifies that the public API is sufficient to:

- create a `TUI`
- create a `TranscriptRenderer`
- create a `StreamingTranscriptAppendState`
- render a user prompt once
- stream assistant output with transcript deltas
- flush the final assistant output on end
- render a minimal tool result

If this example breaks, treat it as a public API regression.

## 4. Manual Terminal Smoke Test

For terminal libraries, some regressions are easier to see than to assert.

Do a quick manual smoke test when changing rendering behavior:

1. open a normal terminal window
2. run the example
3. confirm output order is stable
4. confirm no unexpected ANSI junk is visible
5. confirm prompt/tool lines are not duplicated

If you add more advanced examples later, also test:

- small terminal windows
- long streaming output
- wrapped lines
- CJK / wide characters
- multi-line input or summaries

### Recommended Fixture

Use the long transcript fixture at:

- `Examples/Fixtures/long-transcript.md`

You can inspect it directly with:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
sed -n '1,160p' Examples/Fixtures/long-transcript.md
```

Use it as a stable reference when visually checking:

- long scrollback behavior
- wrapped long lines
- mixed CJK / ASCII display
- whether output feels duplicated or noisy

You can also copy external Markdown samples into `Examples/Fixtures/` and run them through the example.

## 5. Recommended Workflow

### Routine changes

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test
```

### Rendering changes

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test --filter TUITests
cd Examples/MinimalStreamingDemo
swift run
```

### Streaming planner changes

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test --filter StreamingTranscriptAppendStateTests
cd Examples/MinimalStreamingDemo
swift run
```

### Release candidate check

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test
cd Examples/MinimalStreamingDemo
swift run
```

Then do one manual terminal smoke pass.
For the manual pass, keep `Examples/Fixtures/long-transcript.md` open as a reference text set.

## 6. Failure Triage

When something fails, use this rule of thumb:

- `TUITests` failures usually mean rendering strategy or terminal semantics changed
- `TranscriptRendererTests` failures usually mean transcript/event semantics changed
- `StreamingTranscriptAppendStateTests` failures usually mean append-only streaming semantics changed
- example failures usually mean a public API or integration contract regressed

Keep package tests and example behavior in sync.
