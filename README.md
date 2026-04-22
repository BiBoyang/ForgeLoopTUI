# ForgeLoopTUI

[![Release](https://img.shields.io/github/v/release/BiBoyang/ForgeLoopTUI?display_name=tag)](https://github.com/BiBoyang/ForgeLoopTUI/releases)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14%2B-blue.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/BiBoyang/ForgeLoopTUI/blob/main/LICENSE)

`ForgeLoopTUI` is a lightweight Swift terminal UI library for streaming AI transcripts.

It provides:
- event-driven transcript rendering
- in-place streaming replacement (not append-only)
- tool execution placeholders (`running...` -> `done/failed`)
- simple full-screen terminal repaint (`ANSI clear + redraw`)

## Requirements

- Swift 6
- macOS 14+

## Install (SwiftPM)

```swift
dependencies: [
    .package(url: "https://github.com/<your-org>/ForgeLoopTUI.git", branch: "main")
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

## Related Projects

- `ForgeLoop` (main coding-agent application): https://github.com/BiBoyang/ForgeLoop
