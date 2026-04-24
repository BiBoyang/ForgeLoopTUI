# ForgeLoopTUI

[![Release](https://img.shields.io/github/v/release/BiBoyang/ForgeLoopTUI?display_name=tag)](https://github.com/BiBoyang/ForgeLoopTUI/releases)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/BiBoyang/ForgeLoopTUI/blob/main/LICENSE)

`ForgeLoopTUI` is a lightweight Swift terminal UI library for streaming AI transcripts.

It provides:
- event-driven transcript rendering
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
    .package(url: "https://github.com/BiBoyang/ForgeLoopTUI.git", from: "0.1.1")
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

    tui.requestRender(lines: renderer.lines.all)
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
- `StreamingTranscriptAppendState` to compute transcript deltas for append-only streaming UIs
- `TranscriptRenderer.activeStreamingRange` to know which transcript range is still mutable

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

There is a runnable local example package under `Examples/MinimalStreamingDemo`.

Run it with:

```bash
cd Examples/MinimalStreamingDemo
swift run
```

Run it with a custom fixture:

```bash
cd Examples/MinimalStreamingDemo
swift run MinimalStreamingDemo ../Fixtures/markdownview-sample.md
```

The example shows:
- a user prompt rendered once
- assistant streaming with append-only transcript deltas
- final flush on `messageEnd`
- a simple tool start/end placeholder flow

## Related Projects

- `ForgeLoop` (main coding-agent application): https://github.com/BiBoyang/ForgeLoop

## Suggested GitHub Topics

- `swift`
- `tui`
- `terminal-ui`
- `llm-agent`
- `streaming`
