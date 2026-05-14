# AppKitExampleApp

A minimal macOS window app that consumes `ForgeLoopTUI` via Swift Package Manager
and renders state through the AppKit bridge (`HybridRenderState` + `HybridRenderAdapter`).

## What It Demonstrates

- Local SPM dependency to `ForgeLoopTUI`
- Real AppKit window rendering (`NSWindow`, `NSTextView`, `NSStackView`)
- `AppKitEventAdapter` (`NSEvent -> KeyEvent`) input bridge
- `MultiLineInputState` editing and viewport-aware up/down movement
- `HybridRenderAdapter.appKitProjection(of:)` as the single UI projection entry

## Run

```bash
cd Examples/AppKitExampleApp
swift run
```

## Keys

- `Enter`: submit prompt
- `Option+Enter`: insert newline
- `Arrow / Home / End`: move cursor
- `Backspace` / `Delete`: edit
- `Esc`: clear input
- `Ctrl-A/E/U/K/O`: basic readline-style editing
- `Ctrl-C`: quit
