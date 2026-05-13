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
- When `live` exceeds `liveBudget` on `TUI`, oldest `live` lines overflow into `committed` automatically. The library calls this **settlement**: the head of `live` is appended to the tail of `committed` in order, line-by-line, until `live` fits the budget again. Settlement does **not** drop content — it only moves the commit/live boundary.
- `liveBudget` is counted by `TUI.liveBudgetMode`:
  - `.logicalLines` (default): the count is `live.count`. Backwards-compatible with previous releases.
  - `.physicalRows`: the count is the sum of `physicalRows(for:width:)` over each live line. Recommended for streaming Markdown / long wrapped output / narrow terminals, since a width change can now trigger fresh settlement on the next frame without losing content.
- At least one line is always kept in `live`, even if its physical rows already exceed `liveBudget`. This preserves a cursor anchor and a diff target.

```swift
let tui = TUI(
    liveBudget: 4,
    liveBudgetMode: .physicalRows
)
```

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

### Live overflow policy

`LayoutBudget.liveOverflow` decides what happens when the live region itself is taller than the budget:

- `.clipOnly` (default): the existing tail-keep behaviour — older live lines are dropped from the head. Backwards compatible with previous releases.
- `.settleThenClip` *(recommended for streaming apps)*: the same settlement algorithm used by `TUI.liveBudget` first moves overflowing live lines into the tail of `committed`; the final tail-clip then runs on the consolidated buffer. The settled lines become real committed history before any clipping, so the commit/live boundary stays semantically meaningful.

> **Note:** settlement does **not** bypass the final tail-clip. If `committed + live` is still over `maxRows` after settling, the subsequent clip pass can drop settled content too — the difference between `.clipOnly` and `.settleThenClip` is only in *which* lines are treated as committed history while the clip runs, not in whether anything is ultimately retained.

```swift
let composer = FrameComposer(
    committed: [...],
    live: [...],
    layoutBudget: LayoutBudget(
        maxRows: 24,
        overflowMarker: "…",
        liveOverflow: .settleThenClip
    )
)
```

Pair `.settleThenClip` with `TUI(liveBudget:liveBudgetMode:.physicalRows)` if your app streams long output: both call sites share the internal `LiveBudgetPlanner`, so they will agree on what "live" means.

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

## 7. Keybindings (Stable)

For apps that need more than ad-hoc `switch` statements over `KeyEvent`, `ForgeLoopTUI` ships a small keybinding system:

- `KeyStroke` — a single normalized key (`Key` + `Modifiers`).
- `KeySequence` — one or more `KeyStroke`s (single key or multi-key chord).
- `KeybindingRegistry<Action>` — sequence → caller-defined action, with prefix-conflict detection.
- `KeyResolver<Action>` — stateful resolver. `feed(_:)` returns `[ResolvedKey<Action>]`; `tick()` flushes chord prefixes that have timed out.

### 7.1 Define your commands and registry

```swift
enum AppCommand: Sendable {
    case submit, insertNewline, historyPrev, historyNext, interrupt
}

func appKeybindings() -> KeybindingRegistry<AppCommand> {
    var r = KeybindingRegistry<AppCommand>()
    try? r.register(KeySequence(KeyStroke(key: .enter)), action: .submit)
    try? r.register(
        KeySequence(KeyStroke(key: .character("O"), modifiers: .ctrl)),
        action: .insertNewline
    )
    try? r.register(
        KeySequence(KeyStroke(key: .character("P"), modifiers: .ctrl)),
        action: .historyPrev
    )
    try? r.register(
        KeySequence(KeyStroke(key: .character("N"), modifiers: .ctrl)),
        action: .historyNext
    )
    try? r.register(
        KeySequence(KeyStroke(key: .character("C"), modifiers: .ctrl)),
        action: .interrupt
    )
    // Multi-key chord example
    try? r.register(
        KeySequence([
            KeyStroke(key: .character("X"), modifiers: .ctrl),
            KeyStroke(key: .character("S"), modifiers: .ctrl),
        ]),
        action: .submit
    )
    return r
}
```

`KeyParser` emits Ctrl-letter combos with uppercase characters (e.g. `Ctrl-a` arrives as `.character("A"), modifiers: .ctrl`); register the uppercase form to match.

### 7.2 Feed events through the resolver

```swift
let resolver = KeyResolver(registry: appKeybindings())

for event in eventsFromReader {
    for resolved in resolver.feed(event) {
        switch resolved {
        case .action(let command):
            apply(command)
        case .passthrough(let event):
            // Plain text input falls through here.
            if case .character(let c) = event.key, event.modifiers.isEmpty {
                input.handle(.insert(c))
            } else if case .paste(let text) = event.key {
                input.handle(.insertText(text))
            }
        }
    }
}
```

### 7.3 Drive chord timeouts

Multi-key chords need a tick when no input arrives, otherwise a buffered prefix would hang forever. Call `resolver.tick()` from your idle loop or a timer and process its output the same way you process `feed(_:)`:

```swift
while reader.running {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    for resolved in resolver.tick() {
        // same dispatch as above
    }
}
```

### 7.4 Conflict rules

`KeybindingRegistry` rejects three situations:

- **Duplicate** (`.duplicate`) — registering the same `KeySequence` twice.
- **Prefix conflict** (`.prefixConflict`) — registering a sequence that is a prefix of (or an extension of) an existing sequence. This keeps `KeyResolver` strictly three-state (`miss` / `prefix` / `exact`) and avoids "wait or fire" ambiguity.
- **Contains paste** (`.containsPaste`) — defense-in-depth guard. The public `KeyStroke(key:modifiers:)` already traps on `Key.paste`, so this only fires for callers that hand-build paste-bearing strokes through reflection or test-only initializers.

Catch the error from `try registry.register(_:action:)` if you load bindings dynamically.

### 7.5 What `KeyResolver` will *not* match

- `Key.paste(_:)` always passes through; pastes never participate in chord matching.
- Plain typed characters that you have not bound also pass through, so you can route them straight into your input state.

### 7.6 Concurrency

`KeyResolver` is intentionally **non-`Sendable`**. Its internal pending buffer is mutable and unsynchronized. Use it from a single actor or a single thread; if you need to share resolution across actors, wrap it in your own actor.

---

## 8. Cursor Positioning Mode (Stable)

`cursorPlacement` rendering can use two hardware positioning strategies, selectable per `TUI` instance:

- `.relative` (default) — uses relative cursor movement (`ESC[nA` / `ESC[nD` / `ESC[nC`). Implementation is simple and backwards compatible, but the actual hardware position drifts when the rendered content wraps, which can misplace IME candidate windows on multi-line wrapped lines.
- `.marker` — uses physical-row math plus the **Cursor Horizontal Absolute** sequence `ESC[<col>G`. This is robust against wrap and ambiguous autowrap behaviour; recommended when accurate hardware cursor position matters, such as Chinese IME candidate windows on multi-line input.

```swift
let tui = TUI(
    cursorPositioningMode: .marker
)
```

Behaviour notes:

- Non-TTY output never emits any cursor sequence regardless of mode.
- Both modes produce an undo sequence consumed on the *next* render so the diff/fast-path's invariant "cursor sits at the canonical anchor" is preserved.
- `.marker` is computed per-frame from `physicalRows(for:width:)` and the current `terminalWidth`, so resizes are handled correctly on the next frame.

## 9. Soft-wrap Viewport for `MultiLineInputState` (Stable)

By default `MultiLineInputState.moveUp` / `moveDown` walk by **logical** rows. For inputs that wrap (a single long line that spans several physical rows, long pasted code blocks, or wide-character heavy CJK content), this means a single `Up` key may not visibly move the caret. Set a `Viewport` to opt into visual-row navigation:

```swift
var input = MultiLineInputState(text: "")
input.setViewport(Viewport(width: terminalWidth - promptWidth))
```

Behaviour notes:

- The viewport hint is consumed only by `.moveUp` and `.moveDown`. Other actions (insert, backspace, kill, move-to-line-start/end) ignore it.
- Visual moves preserve a *preferred visual column* across rows, mirroring user expectations from desktop editors.
- Pass `nil` (or call `setViewport(nil)`) to revert to logical-row behaviour.
- On terminal resize, update the viewport with the new width — the next `.moveUp` / `.moveDown` will use the new wrap geometry without any extra recomputation.

```swift
// inside your render() / resize handler
input.setViewport(Viewport(width: max(1, terminalWidth - promptWidth)))
```

## 10. Version Selection and Upgrade Notes

### Choosing a version

- **Patch releases** (`0.1.Z`) are safe to adopt automatically: bug fixes and docs only.
- **Minor releases** (`0.Y.0`) may add new APIs or evolve **Provisional** APIs. Review `CHANGELOG.md` before upgrading.
- **Major releases** (`X.0.0`) may break **Stable** APIs. Read `docs/public-api-surface.md` and `docs/semver-and-api-stability.md` before upgrading.

### Breaking-change policy

- **Stable** APIs require a deprecation window of at least one MINOR release before removal.
- **Provisional** APIs may evolve in MINOR releases without deprecation.
- **Internal-detail** APIs carry no SemVer protection; avoid depending on them.

See `docs/semver-and-api-stability.md` for the full policy and `docs/public-api-surface.md` for the per-type stability assignment.

## 11. Related Documents

- `docs/public-api-surface.md` — complete public API catalog with stability tiers
- `docs/semver-and-api-stability.md` — SemVer policy and breaking-change definitions
- `docs/release-checklist.md` — release validation steps
- `docs/module-dataflow-and-dependency-map.md` — ASCII dataflow diagrams
- `docs/migration-guide-for-forgeloopcli.md` — concrete migration notes for `ForgeLoopCli`
