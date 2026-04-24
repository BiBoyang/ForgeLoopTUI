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
- tool execution placeholders (`running...` -> `done/failed`)
- ANSI-aware physical row accounting for wrapped lines
- safe stdout writing with `EINTR` / `EAGAIN` handling
- logical-line normalization for embedded `\n` / `\r\n`
- reusable streaming transcript append planner for scrollback-safe terminal output

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

- `appendFrame(lines:)` to write plain terminal output without retained-mode redraw
- `resetRetainedFrame()` to drop inline redraw state before switching modes
- `transcriptLines` as the stable read-only snapshot of rendered transcript lines
- `StreamingTranscriptAppendState` to compute transcript deltas for append-only streaming UIs
- `TranscriptRenderer.activeStreamingRange` to know which transcript range is still mutable

Low-level logical-line and terminal-metric helpers are kept as implementation details; the stable consumer-facing API is centered on `TUI`, `TranscriptRenderer`, `RenderEvent`, `RenderMessage`, `Style`, `prefixedLogicalLines`, and `StreamingTranscriptAppendState`.

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

There are two runnable local example packages:

- `Examples/MinimalStreamingDemo`: stability / public-API smoke example
- `Examples/MarkdownShowcase`: Markdown presentation example

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
