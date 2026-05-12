# ForgeLoopTUI Integration Guide

> Audience: third-party developers building terminal apps on top of `ForgeLoopTUI`.  
> Scope: library-owned APIs only; no app-specific business logic.

---

## 1. Minimal Dependencies and Module Boundaries

`ForgeLoopTUI` is a Swift Package Manager library. Add it as a dependency and import a single module:

```swift
import ForgeLoopTUI
```

### What lives in the library

| Concern | Types |
|---------|-------|
| **Terminal abstraction** | `Terminal`, `StdoutTerminal`, `VirtualTerminal`, `TerminalSize`, `getTerminalSize()` |
| **ANSI / width** | `ANSIParser`, `SGRState`, `physicalRows(for:width:)` |
| **Input** | `RawTTY`, `InputReader`, `InputPipeline`, `KeyEvent`, `KeyParser`, `ByteStreamBuffer` |
| **Runtime** | `TUI`, `RenderLoop`, `RenderStrategy` |
| **Transcript** | `TranscriptRenderer`, `CoreRenderEvent`, `StreamingTranscriptAppendState` |
| **Markdown** | `MarkdownEngine`, `StreamingMarkdownEngine`, `MarkdownRenderOptions`, `TableRenderPolicy` |
| **Components** | `Component`, `AnyComponent`, `VStack`, `@ComponentBuilder`, `FrameComposer`, `ComposedFrame`, `LayoutBudget` |
| **Screen layout** | `ScreenLayout`, `ScreenLayoutConfig`, `ScreenLayoutRenderer` |
| **Interaction primitives** | `TextInputState`, `ListPickerState`, `ListPickerRenderer`, `ModalRenderer` |
| **Style** | `Style`, `TerminalCapability` |

### What must stay in the app

- Agent / chat event adaptation (`AgentEventRenderAdapter` in `ForgeLoopCli`)
- Prompt history, slash-command registry, model picker
- Authentication, credential store, attachment store
- App-specific status text, footer notices, and orchestration policy

**Rule of thumb**: if a type mentions your product domain (agent, model, auth, attachment), it belongs in the app, not in `ForgeLoopTUI`.

---

## 2. Minimal Rendering Pipeline

The shortest path from user input to pixels is:

```
Input ──► State ──► ScreenLayout ──► ScreenLayoutRenderer ──► ComposedFrame ──► TUI.render(frame:)
```

### 2.1 Build `ScreenLayout`

```swift
let layout = ScreenLayout(
    header: ["MyApp v1.0"],
    transcript: renderer.transcriptLines,
    queue: [],
    status: ["Ready"],
    input: [inputState.render(prefix: Style.prompt("> ", mode: .ansi), totalWidth: 80).line],
    pinnedTranscriptRange: renderer.preferredPinnedRange
)
```

### 2.2 Configure `ScreenLayoutConfig`

```swift
let config = ScreenLayoutConfig(
    terminalHeight: terminalSize?.rows ?? 24,
    terminalWidth: terminalSize?.columns ?? 80,
    showHeader: true
)
```

### 2.3 Render to `ComposedFrame`

```swift
let frame = ScreenLayoutRenderer().render(
    layout: layout,
    config: config,
    cursorOffset: inputState.cursorOffset
)
```

### 2.4 Output via `TUI`

```swift
let tui = TUI()
tui.render(frame: frame)
```

`TUI.render(frame:)` is a convenience that forwards to `TUI.render(committed:live:cursorOffset:)`.

---

## 3. Committed / Live / CursorOffset Semantics

### `committed`
- Append-only history.  
- The runtime treats it as stable: when only `live` changes, `committed` lines are **not** redrawn.
- Ideal for transcript, headers, and status lines that rarely change.

### `live`
- Mutable region that supports diff-based redraw.  
- Typical use: the current input line, a spinner, or a streaming block that updates every keystroke.
- When `live` exceeds `liveBudget` on `TUI`, oldest `live` lines overflow into `committed` automatically.

### `cursorOffset`
- Optional horizontal cursor offset **within the live region**.
- When present, the runtime anchors the frame (no trailing newline) and emits ANSI cursor-positioning sequences.
- Required for text-input scenarios; omit for log-style output.

### Relationship to `ScreenLayoutRenderer`

`ScreenLayoutRenderer` partitions `ScreenLayout` into committed/live automatically:

- **Live** = final `input` lines (if any).  
- **Committed** = everything else (`header`, `transcript`, `queue`, `status`).

This policy is minimal, stable, and visually neutral.  Apps that need a different live policy can compose `FrameComposer` directly instead.

---

## 4. Coalesce Rules

`RenderLoop` provides 16 ms frame coalescing for high-frequency updates.  When using `ComposedFrame`, coalescing must respect live-region integrity.

### When coalescing is **allowed**

- `frame.live.isEmpty && frame.cursorOffset == nil && priority == .normal`
- In this case the frame can be flattened to `frame.committed` and submitted to `RenderLoop` without losing semantics.

### When coalescing is **prohibited**

- `frame.live` is non-empty  
- `frame.cursorOffset` is non-nil  
- `priority == .immediate`

In these cases the frame must bypass `RenderLoop` and go directly to `TUI.render(frame:)` so that live diff and cursor positioning are preserved.

### Example guard (app-side)

```swift
func shouldCoalesceWithRenderLoop(
    frame: ComposedFrame,
    priority: RenderLoop.Priority
) -> Bool {
    priority == .normal && frame.live.isEmpty && frame.cursorOffset == nil
}
```

---

## 5. Composition Without ScreenLayout

For apps that do not fit the `ScreenLayout` model, use `FrameComposer` + `Component`:

```swift
let composer = FrameComposer(
    committed: [AnyComponent(TranscriptComponent(renderer: renderer))],
    live: [AnyComponent(InputComponent(state: inputState))],
    layoutBudget: LayoutBudget(maxRows: 24, overflowMarker: "…")
)
let frame = composer.render(width: 80, cursorOffset: inputState.cursorOffset)
tui.render(frame: frame)
```

---

## 6. Testing with `VirtualTerminal`

`VirtualTerminal` implements `Terminal` and records every cell, cursor move, and clear operation.  Use it for deterministic behavior tests without a real TTY:

```swift
let vt = VirtualTerminal(width: 80, height: 24)
let tui = TUI(strategy: .inlineAnchor, terminal: vt)
tui.render(frame: frame)
// Assert on vt.grid, vt.cursorRow, vt.cursorCol
```

---

## 7. Version Selection and Upgrade Notes

### Choosing a version

- **Patch releases** (`0.1.Z`) are safe to adopt automatically: bug fixes and docs only.
- **Minor releases** (`0.Y.0`) may add new APIs or evolve **Provisional** APIs. Review `CHANGELOG.md` before upgrading.
- **Major releases** (`X.0.0`) may break **Stable** APIs. Read `docs/public-api-surface.md` and `docs/semver-and-api-stability.md` before upgrading.

### Breaking-change policy

- **Stable** APIs require a deprecation window of at least one MINOR release before removal.
- **Provisional** APIs may evolve in MINOR releases without deprecation.
- **Internal-detail** APIs carry no SemVer protection; avoid depending on them.

See `docs/semver-and-api-stability.md` for the full policy and `docs/public-api-surface.md` for the per-type stability assignment.

## 8. Related Documents

- `docs/public-api-surface.md` — complete public API catalog with stability tiers
- `docs/semver-and-api-stability.md` — SemVer policy and breaking-change definitions
- `docs/release-checklist.md` — release validation steps
- `docs/module-dataflow-and-dependency-map.md` — ASCII dataflow diagrams
- `docs/migration-guide-for-forgeloopcli.md` — concrete migration notes for `ForgeLoopCli`
