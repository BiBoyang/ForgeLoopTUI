# ForgeLoopTUI Public API Surface

Date: 2026-05-11  
Version: 0.1.2  
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
| `TUI` | `class` | **Stable** | Low | Core entry point; unlikely to change signature |
| `RenderLoop` | `class` | **Stable** | Low | Scheduler internals may evolve; public API (`.submit`) is frozen |
| `RenderLoop.Priority` | `enum` | **Stable** | Very low | `.normal` / `.immediate` only |
| `RenderStrategy` | `enum` | **Stable** | Low | `.legacyAbsolute` / `.inlineAnchor` unlikely to change |

**Consumer dependency points:**
- `TUI.render(frame:)` — the primary output path.
- `TUI.render(committed:live:cursorOffset:)` — two-region path.
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
| `ComposedFrame` | `struct` | **Stable** | Low | Core frame model; fields (`committed`, `live`, `cursorOffset`) frozen |
| `LayoutBudget` | `struct` | **Stable** | Low | Simple value type |
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
| `ListPickerState` | `struct` | **Stable** | Low | Selection state machine |
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
- `ListPickerState.handle(_:)` — process picker actions.
- `ListPickerRenderer.render(state:)` — render picker to lines.

---

## 5. Input Pipeline (`Input/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `KeyEvent` | `struct` | **Stable** | Low | Normalized key event model |
| `Key` | `enum` | **Stable** | Low | Key types (character, arrows, f-keys, etc.) |
| `Modifiers` | `struct` | **Stable** | Low | OptionSet for shift/alt/ctrl |
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
- `RawTTY.enter()` / `RawTTY.restore()` — manual TTY management.
- `withRawTTY(fd:body:)` — RAII raw mode.

---

## 6. Transcript Engine (`Transcript/`)

| Type | Kind | Stability | Breaking-change risk | Migration advice |
|------|------|-----------|----------------------|------------------|
| `CoreRenderEvent` | `enum` | **Stable** | Low | Generic event vocabulary; new cases may be added safely |
| `TranscriptRenderer` | `class` | **Stable** | Low | `applyCore(_:)` + `transcriptLines` are the contract |
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
| **Stable** | ~55 | Safe to depend on; breaking changes require MAJOR bump |
| **Provisional** | ~15 | Safe to adopt; monitor release notes for MINOR evolutions |
| **Internal-detail** | ~20 | Avoid direct dependency; may change without SemVer protection |
| **Deprecated** | 3 | Migrate to `CoreRenderEvent` / `TranscriptRenderer.applyCore(_:)` |

---

## Related documents

- `docs/semver-and-api-stability.md` — SemVer policy and breaking-change definitions
- `docs/release-checklist.md` — Release process that validates this surface
- `docs/integration-guide.md` — How to compose these APIs into an app
