# MinimalAIApp

A minimal runnable AI terminal application built with **ForgeLoopTUI**.

## What It Demonstrates

- Interactive single-line prompt with streaming AI response
- Block-based streaming via `blockStart` / `blockUpdate` / `blockEnd`
- Committed-append transcript rendering: completed replies are printed once
  via `StreamingTranscriptAppendState` + `TUI.appendFrame` and stay in the
  terminal scrollback; the status/input area redraws in place via
  `TUI.render(committed:live:cursorPlacement:)`
- Cancel-in-flight with `Esc`
- Prompt history navigation with `Ctrl-P` / `Ctrl-N`
- Non-interactive (piped) fallback

## How to Run

```bash
cd Examples/MinimalAIApp
swift run
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Enter` | Submit prompt |
| `Esc` | Cancel current streaming, or clear input if idle |
| `Ctrl-C` | Exit application |
| `↑` / `↓` | Move cursor across buffer lines (visual-row-aware when wrapped) |
| `Ctrl-P` / `Ctrl-N` | Previous / next history entry |
| `←` / `→` | Move cursor |
| `Backspace` | Delete character before cursor |
| `Home` / `End` | Jump to start / end of input |

## Non-Interactive Mode

Pipe stdin directly:

```bash
echo "hello" | swift run
```

## Replacing the AI Provider

The app uses a `MinimalAIProvider` protocol:

```swift
protocol MinimalAIProvider {
    func streamReply(to prompt: String) -> AsyncStream<String>
}
```

Replace `FauxAIProvider` with any real implementation (OpenAI, Anthropic, local LLM, etc.) — no other code changes required.
