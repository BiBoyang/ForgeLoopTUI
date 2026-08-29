# MinimalAIApp

A minimal runnable AI terminal application built with **ForgeLoopTUI**.

## What It Demonstrates

- Interactive single-line prompt with streaming AI response
- Block-based streaming via `blockStart` / `blockUpdate` / `blockEnd`
- Committed-append transcript rendering with live preview: while a reply
  streams, the unstable tail of the active block (the rendered lines past
  the engine-certified stable prefix) previews in the committed region via
  `TUI.render(committed:live:cursorPlacement:)`, so markdown appears line by
  line as it streams; as lines turn stable they settle into the scrollback
  exactly once via `StreamingTranscriptAppendState` + `TUI.appendFrame`,
  using the oracle-pinned sequence erase → append → re-render with anchored
  frames throughout. The status/input area redraws in place below the
  preview.
- Cancel-in-flight with `Esc`
- Prompt history navigation with `Ctrl-P` / `Ctrl-N`
- Non-interactive (piped) fallback
- `/demo` command: streams bundled markdown fixtures offline for rendering tests

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

## Demo Fixtures (Offline Markdown Testing)

Type `/demo` in the interactive prompt to list the bundled markdown fixtures,
and `/demo <name>` to stream one locally through the normal assistant reply
path — no API key required:

```text
/demo full   # comprehensive: tables/code/quotes/lists/LaTeX/Mermaid/HTML
/demo table  # table rendering and alignment
/demo edge   # table edge cases and degradation
```

Fixtures live in `Examples/Fixtures/` and are shared with `MarkdownShowcase`
and `MinimalStreamingDemo`. In non-interactive mode, `/demo <name>` prints
the raw fixture markdown instead:

```bash
echo "/demo full" | swift run
```

## Replacing the AI Provider

The app uses a `MinimalAIProvider` protocol:

```swift
protocol MinimalAIProvider {
    func streamReply(to prompt: String) -> AsyncStream<String>
}
```

Replace `FauxAIProvider` with any real implementation (OpenAI, Anthropic, local LLM, etc.) — no other code changes required.
