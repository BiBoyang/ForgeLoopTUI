# ForgeLoopTUI Public API Surface

Date: 2026-05-23  
Version: 1.1.0  
Scope: every `public` declaration in `Sources/ForgeLoopTUI` that a third-party consumer may depend on.

---

## How to read this document

- **Stable** — SemVer-protected. Breaking changes require a MAJOR bump and a migration path.
- **Provisional** — API shape is settled but may evolve in MINOR releases with deprecation.
- **Internal-detail** — Public by necessity (protocol conformance, cross-module access). Do not depend on these directly unless you accept breakage without SemVer protection.
- **Deprecated** — Scheduled for removal. Use the replacement noted.

---

## 1. Runtime (`Runtime/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `TUI` | `class` | **Stable** | Low | Core entry point; new `liveBudgetMode` and `cursorPositioningMode` parameters have defaults so existing callers compile unchanged |
| `TUI.liveBudgetMode` | `LiveBudgetMode` | **Stable** | Low | Selects how `liveBudget` counts overflow (`.logicalLines` default; `.physicalRows` recommended for wrap-heavy streaming) |
| `TUI.cursorPositioningMode` | `CursorPositioningMode` | **Stable** | Low | Selects hardware cursor positioning strategy (`.relative` default; `.marker` recommended when accurate hardware position matters, e.g. IME candidate windows) |
| `LiveBudgetMode` | `enum` | **Stable** | Low | `.logicalLines` / `.physicalRows`; shared with `FrameComposer` settlement |
| `CursorPositioningMode` | `enum` | **Stable** | Low | `.relative` (back-compat) / `.marker` (physical-row aware, CHA-based) |
| `TUIRenderDiagnostic` | `enum` | **Provisional** | Low | Diagnostic events emitted via `TUI.diagnosticsHandler`; shape may expand with new cases |
| `RenderLoop` | `class` | **Stable** | Low | Scheduler internals may evolve; public API (`.submit`) is frozen |
| `RenderLoop.Priority` | `enum` | **Stable** | Very low | `.normal` / `.immediate` only |
| `RenderStrategy` | `enum` | **Stable** | Low | `.legacyAbsolute` / `.inlineAnchor` unlikely to change |

**Consumer dependency points:**
- `TUI.render(frame:)` — the primary output path.
- `TUI.render(committed:live:cursorOffset:)` — two-region path.
- `TUI.render(committed:live:cursorPlacement:)` — two-region path with 2D cursor positioning.
- `RenderLoop.submit(committed:priority:)` — coalescing optimization.

---

## 2. Terminal Abstraction (`Terminal/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `Terminal` | `protocol` | **Stable** | Medium | Adding requirements is breaking; new capabilities will use extension methods |
| `TerminalCapability` | `enum` | **Stable** | Very low | Plain/ansi16/ansi256/truecolor levels are fixed |
| `StdoutTerminal` | `struct` | **Stable** | Low | Default constructor stable |
| `VirtualTerminal` | `class` | **Stable** | Low | Test infrastructure; grid/cursor accessors frozen |
| `Cell` | `struct` | **Provisional** | Medium | May gain new fields (underline, italic) for richer style tracking |
| `TerminalSize` | `struct` | **Stable** | Very low | Simple value type |
| `getTerminalSize()` | `func` | **Stable** | Very low | Returns `TerminalSize?` |
| `FrameWriter` | `typealias` | **Internal-detail** | High | Use `Terminal` protocol instead |

**Consumer dependency points:**
- `Terminal.write(_:)` — the only required method.
- `VirtualTerminal(width:height:)` — deterministic testing.
- `getTerminalSize()` — dynamic terminal geometry.

---

## 3. Components & Layout (`Components/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `Component` | `protocol` | **Stable** | Medium | `render(width:)` is the contract; new default implementations are safe |
| `AnyComponent` | `struct` | **Stable** | Low | Type-erasure wrapper |
| `VStack` | `struct` | **Stable** | Low | Vertical composition primitive |
| `ComponentBuilder` | `@resultBuilder enum` | **Stable** | Low | DSL syntax frozen |
| `EmptyComponent` | `struct` | **Internal-detail** | Medium | Builder fallback; rarely used directly |
| `ComposedFrame` | `struct` | **Stable** | Low | Core frame model; fields (`committed`, `live`, `cursorOffset`, `cursorPlacement`) frozen |
| `LayoutBudget` | `struct` | **Stable** | Low | Simple value type; gained optional `liveOverflow` field with a backward-compatible default |
| `LayoutBudget.LiveOverflowPolicy` | `enum` | **Stable** | Low | `.clipOnly` (default) / `.settleThenClip` |
| `FrameComposer` | `struct` | **Stable** | Low | Constructor and `render(width:cursorOffset:)` frozen |
| `ScreenLayout` | `struct` | **Stable** | Low | Region fields frozen; new optional fields may be added safely |
| `ScreenLayoutConfig` | `struct` | **Stable** | Low | Geometry + visibility flags |
| `ScreenLayoutRenderer` | `struct` | **Stable** | Low | `render(layout:config:cursorOffset:)` is the contract |
| `ModalRenderer` | `struct` | **Stable** | Low | Modal framing primitive |

**Consumer dependency points:**
- `Component.render(width:)` — implement for custom components.
- `ComposedFrame(committed:live:cursorOffset:)` — frame assembly.
- `ScreenLayoutRenderer().render(layout:config:)` — layout → frame.
- `FrameComposer(committed:live:layoutBudget:).render(width:)` — custom composition.

---

## 4. Interaction Primitives (`Components/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `TextInputState` | `struct` | **Stable** | Low | Core single-line editor; action set may expand |
| `TextInputAction` | `enum` | **Stable** | Low | Actions (insert, backspace, move, etc.) |
| `TextInputRenderResult` | `struct` | **Stable** | Low | `.line` + `.cursorOffset` |
| `MultiLineInputState` | `struct` | **Stable** | Low | Multi-line editor; action set may expand; optional `viewport` makes `moveUp`/`moveDown` walk by visual rows |
| `MultiLineInputAction` | `enum` | **Stable** | Low | Actions (insert, insertText, insertNewline, backspace, delete, move, kill, replace, clear) |
| `Viewport` | `struct` | **Stable** | Low | Optional soft-wrap viewport hint for `MultiLineInputState` (width-only). Visual geometry is computed via `visibleWidth(_:)`, so mixed ASCII/CJK lines wrap and navigate by visible cells, not character indices. |
| `CursorPlacement` | `struct` | **Stable** | Very low | 2D cursor anchor (`up` rows, `offset` columns) |
| `MultiLineInputRenderResult` | `struct` | **Stable** | Low | `.lines` + `.cursor` (CursorPlacement) |
| `ListPickerState` | `struct` | **Stable** | Low | Selection state machine |
| `ListPickerItem` | `struct` | **Stable** | Low | `id` + `title` + optional `subtitle` |
| `ListPickerAction` | `enum` | **Stable** | Low | `.moveUp`, `.moveDown`, `.confirm`, `.cancel` |
| `ListPickerOutcome` | `enum` | **Stable** | Low | `.confirmed`, `.cancelled`, `.none` |
| `ListPickerRenderer` | `struct` | **Stable** | Low | `render(state:)` → `[String]` |
| `TranscriptComponent` | `struct` | **Stable** | Low | Wraps transcript lines as `Component` |
| `TextInputComponent` | `struct` | **Stable** | Low | Stateless prompt+value component |
| `ListPickerComponent` | `struct` | **Stable** | Low | Stateless list picker component |
| `PromptHistory` | `struct` | **Provisional** | Low | Minimal input history navigation (commit / prev / next / reset / isAtCurrent); frozen for current phase — see `docs/prompt-history-api-decision.md` for evolution criteria |

**Consumer dependency points:**
- `TextInputState.handle(_:)` — process key actions.
- `TextInputState.render(prefix:totalWidth:)` — produce renderable line.
- `MultiLineInputState.handle(_:)` — process key actions.
- `MultiLineInputState.render()` — produce renderable lines + cursor placement.
- `ListPickerState.handle(_:)` — process picker actions.
- `ListPickerRenderer.render(state:)` — render picker to lines.

---

## 5. Input Pipeline (`Input/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `KeyEvent` | `struct` | **Stable** | Low | Normalized key event model |
| `Key` | `enum` | **Stable** | Low | Key types (character, arrows, f-keys, etc.); now conforms to `Hashable` |
| `Modifiers` | `struct` | **Stable** | Low | OptionSet for shift/alt/ctrl/command; now conforms to `Hashable`; `.command` added in v1.1.0 |
| `KeyStroke` | `struct` | **Stable** | Low | Single-press normalized key for binding lookups; the public initializer traps on `Key.paste` (use `init?(event:)` when converting `KeyEvent`s) |
| `KeySequence` | `struct` | **Stable** | Low | One or more `KeyStroke`s describing a binding (single key or chord) |
| `KeyBinding` | `struct` | **Stable** | Low | `KeySequence` → caller-defined action |
| `KeybindingRegistry` | `struct` | **Stable** | Low | Registry with `register` / `unregister` / `match`; enforces prefix-conflict invariants; throws `duplicate` / `prefixConflict` / `containsPaste` |
| `KeyResolver` | `class` | **Stable** | Medium | Stateful chord resolver driven by an `InputClock`; emits `ResolvedKey`. **Non-`Sendable`** — all `feed`/`tick`/`flush`/`replaceRegistry` calls must be serialized (e.g. a single actor or thread). |
| `ResolvedKey` | `enum` | **Stable** | Low | `.action(_)` or `.passthrough(KeyEvent)` |
| `RawTTY` | `class` | **Stable** | Low | Raw TTY lifecycle |
| `RawTTYError` | `enum` | **Stable** | Very low | `.notATTY`, `.alreadyEntered`, etc. |
| `withRawTTY(fd:body:)` | `func` | **Stable** | Very low | RAII helper |
| `InputReader` | `class` | **Stable** | Medium | High-level reader; event-loop integration may evolve |
| `InputPipeline` | `class` | **Provisional** | Medium | Paste/ESC-timer logic may gain new configuration |
| `ByteStreamBuffer` | `class` | **Internal-detail** | High | Low-level byte parser |
| `InputUnit` | `enum` | **Internal-detail** | High | Parsed unit types |
| `KeyParser` | `struct` | **Internal-detail** | High | `InputUnit` → `KeyEvent` mapper |
| `InputClock` | `protocol` | **Internal-detail** | High | Injectable clock |
| `SystemInputClock` | `struct` | **Internal-detail** | High | Default clock implementation |
| `hasUTF8EraseFlag(_:)` | `func` | **Internal-detail** | High | TTY flag helper |
| `withUTF8EraseFlag(_:)` | `func` | **Internal-detail** | High | TTY flag helper |

**Consumer dependency points:**
- `InputReader.start(handler:)` / `InputReader.stop()` — event-loop integration.
- `KeyEvent.key` + `KeyEvent.modifiers` — key handling.
- `KeybindingRegistry().register(_:action:)` — declarative app-side commands.
- `KeyResolver(registry:).feed(_:)` / `.tick()` — chord-aware resolution of input.
- `RawTTY.enter()` / `RawTTY.restore()` — manual TTY management.
- `withRawTTY(fd:body:)` — RAII raw mode.

---

## 6. Transcript Engine (`Transcript/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `CoreRenderEvent` | `enum` | **Stable** | Low | Generic event vocabulary; new cases may be added safely; added `.blockCancel` and `.thinking` in v1.1.0 |
| `TranscriptRenderer` | `class` | **Stable** | Low | `applyCore(_:)` + `transcriptLines` are the contract |
| `TranscriptRenderOptions` | `struct` | **Stable** | Low | Configurable summary/notification limits; v1.1.0 |
| `StreamingTranscriptAppendState` | `struct` | **Stable** | Low | Delta computation for append-only streaming |
| `RenderMessage` | `enum` | **Deprecated** | N/A | Use `CoreRenderEvent` via `LegacyRenderEventAdapter` |
| `RenderEvent` | `enum` | **Deprecated** | N/A | Use `CoreRenderEvent` instead |
| `LegacyRenderEventAdapter` | `struct` | **Deprecated** | N/A | Bridge from old → new events |

**Consumer dependency points:**
- `TranscriptRenderer.applyCore(_:)` — apply generic events.
- `TranscriptRenderer.transcriptLines` — read-only snapshot.
- `TranscriptRenderer.preferredPinnedRange` — streaming protection hint.
- `StreamingTranscriptAppendState.consume(transcript:activeRange:)` — delta for append-only UIs.

---

## 7. Bridge / AppKit (`Bridge/AppKit/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `HybridRenderState` | `struct` | **Provisional** | Medium | New bridge; may gain fields for richer AppKit metadata |
| `PanelMeta` | `struct` | **Provisional** | Medium | AppKit metadata shape may expand; `subtitle` / `accessoryBadge` added in P0, default nil, backward compatible |
| `TerminalRenderState` | `struct` | **Provisional** | Low | Thin wrapper around `ScreenLayout` |
| `AppKitPanelState` | `struct` | **Provisional** | Medium | Panel shape may expand for new UI regions |
| `HybridRenderAdapter` | `struct` | **Provisional** | Low | Pure adapter; new convenience methods may be added |
| `AppKitEventAdapter` | `struct` | **Provisional** | Low | NSEvent → KeyEvent adapter; for use in NSView.keyDown(with:) |
| `HybridObservableState` | `class` | **Provisional** | Low | `@Observable` + `@MainActor` wrapper; requires macOS 14+; UI state container, not cross-thread Sendable |
| `PanelMetadataProviding` | `protocol` | **Provisional** | Low | Implement on app-side panel data; bridge to `PanelMeta` via `PanelMeta(_:)` init |
| `AppKitBridgeError` | `enum` | **Provisional** | Medium | `AppKitEventAdapter` mapping failures; currently one case |

**Consumer dependency points:**
- `HybridRenderAdapter.renderBoth(state:config:cursorOffset:)` — dual projection entry point.
- `AppKitPanelState.meta` — panel chrome data.
- `TerminalRenderState.layout` + `.config` — terminal projection.

---

## 8. Style (`Style/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `Style` | `enum` | **Stable** | Low | Namespace for semantic styling |
| `Style.RenderingMode` | `enum` | **Stable** | Very low | `.automatic` / `.ansi` / `.plain` |
| `StyleSpec` | `struct` | **Stable** | Low | Structured style spec |
| `Color` | `enum` | **Stable** | Very low | ANSI color model (standard/bright/indexed/rgb) |

**Consumer dependency points:**
- `Style.prompt(...)`, `Style.header(...)`, `Style.error(...)`, etc. — semantic styling.
- `StyleSpec(bold:dim:reverse:foreground:background:)` — custom styles.
- `Color.rgb(r:g:b:)` / `Color.indexed(_:)` / `Color.standard(_:)` — color construction.

---

## 9. Markdown (`Markdown/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `MarkdownEngine` | `protocol` | **Stable** | Medium | New requirements are breaking; prefer `StreamingMarkdownEngine` |
| `MarkdownRenderOptions` | `struct` | **Stable** | Low | Options value type |
| `TableRenderPolicy` | `struct` | **Stable** | Low | Table width/truncation policy |
| `TableOverflowBehavior` | `enum` | **Stable** | Very low | `.degradeImmediately` / `.compactThenTruncateThenDegrade` |
| `WideTableStrategy` | `enum` | **Stable** | Very low | `.alwaysBox` / `.autoReadable` |
| `TableStreamingBehavior` | `enum` | **Stable** | Very low | `.monotonic` / `.strict` |
| `StreamingMarkdownEngine` | `class` | **Stable** | Low | Primary consumer-facing engine |
| `PlainTextMarkdownEngine` | `class` | **Stable** | Low | No-op fallback |
| `prefixedLogicalLines(prefix:text:)` | `func` | **Internal-detail** | High | Use `MarkdownEngine` instead |

**Consumer dependency points:**
- `StreamingMarkdownEngine(options:).render(lines:width:)` — primary rendering.
- `MarkdownRenderOptions(tablePolicy:)` — table behavior tuning.
- `TranscriptRenderer(markdownOptions:)` — inject into transcript pipeline.

---

## 10. ANSI (`ANSI/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `SGRState` | `struct` | **Provisional** | Medium | May gain new attributes (italic, underline, strikethrough) |
| `ANSIParser` | `struct` | **Internal-detail** | High | State machine; consumers should use `Terminal` protocol |
| `ANSIParser.Event` | `enum` | **Internal-detail** | High | Parser events |
| `physicalRows(for:width:)` | `func` | **Internal-detail** | High | Use `LayoutBudget` / `ScreenLayoutRenderer` instead |

**Consumer dependency points:**
- `SGRState` + `Color` — if building custom ANSI-aware components.
- Prefer `Terminal` protocol and `VirtualTerminal` over direct `ANSIParser` usage.

---

## Stability summary

| Stability level | Count | Recommendation |
|-----------------|-------|----------------|
| **Stable** | ~67 | Safe to depend on; breaking changes require MAJOR bump |
| **Provisional** | ~12 | Safe to adopt; monitor release notes for MINOR evolutions |
| **Internal-detail** | ~13 | Avoid direct dependency; may change without SemVer protection |
| **Deprecated** | 3 | Migrate to `CoreRenderEvent` / `TranscriptRenderer.applyCore(_:)` |

---

## API stability commitments

These commitments apply to every API marked **Stable** in this document.

### Defaults
- All initializers accept defaults for any parameter introduced after the 0.1.0 line: existing callers compile unchanged.
- The defaults reflect the **safest backwards-compatible behaviour**, not necessarily the recommended one. The "Migration advice" column highlights when a non-default is recommended (e.g. `liveBudgetMode: .physicalRows`, `cursorPositioningMode: .marker`).

### Errors
- Library APIs throw typed errors only when an unrecoverable invariant is violated by the *caller* (e.g. `KeybindingRegistry.RegistrationError.duplicate` / `.prefixConflict` / `.containsPaste`).
- Internal subsystems (renderers, parsers) do not throw across the public surface; failures surface as null returns, no-ops, or graceful degradation (e.g. non-TTY auto-fallback for cursor positioning).
- `precondition` / `preconditionFailure` is used **only** for misuse that cannot be safely recovered (e.g. `KeyStroke(key: .paste(...))`, `Viewport(width: 0)`). These traps stay in Release builds.

### Concurrency
- Value types (`KeyStroke`, `KeySequence`, `KeyBinding`, `LayoutBudget`, `Viewport`, `MultiLineInputState`, etc.) are `Sendable` and safe to share/copy across actors.
- Stateful classes carry an explicit concurrency contract in their migration advice column:
  - `TUI` is `@unchecked Sendable`. Renders are serialised internally by an `NSLock`; callers can hand the same instance to multiple actors safely.
  - `KeyResolver` is **non-`Sendable`**. Callers must serialise `feed` / `tick` / `flush` / `replaceRegistry` (e.g. always call from the same actor or thread).
  - `HybridObservableState` is `@MainActor`-isolated and not safe to share off-main.
- Enum / struct types added through Step 2–5 (modes, policies, viewport) are `Sendable, Equatable, Hashable` where it makes sense, and intentionally **don't** carry hidden state.

---

## Related documents

- `docs/semver-and-api-stability.md` — SemVer policy and breaking-change definitions
- `docs/release-checklist.md` — Release process that validates this surface
- `docs/integration-guide.md` — How to compose these APIs into an app
