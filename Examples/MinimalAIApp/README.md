# MinimalAIApp

A minimal runnable AI terminal application built with **ForgeLoopTUI**.

## What It Demonstrates

- Interactive single-line prompt with streaming AI response
- Block-based streaming via `blockStart` / `blockUpdate` / `blockEnd`
- Cancel-in-flight with `Esc`
- Up / Down arrow history navigation
- Full-screen layout composition with `ScreenLayoutRenderer`
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
| `↑` | Previous history entry |
| `↓` | Next history entry (or clear if at current) |
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
