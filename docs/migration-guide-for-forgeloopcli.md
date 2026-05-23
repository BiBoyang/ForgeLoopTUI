# Migration Guide for ForgeLoopCli

> Scope: changes landed in `ForgeLoopTUI` A1–D2 and their adoption in `ForgeLoopCli`.  
> Audience: maintainers of `ForgeLoopCli` and future apps migrating onto `ForgeLoopTUI`.

---

## 1. Completed Migrations

### 1.1 TerminalSize / TTYFlags — sunk into the library

| Before (app-owned) | After (library-owned) |
|--------------------|-----------------------|
| `ForgeLoop/Sources/ForgeLoopCli/Layout.swift` contained `TerminalSize` and `getTerminalSize()` | `Sources/ForgeLoopTUI/Terminal/TerminalSize.swift` |
| `ForgeLoop/Sources/ForgeLoopCli/TUIRunner.swift` contained `hasUTF8EraseFlag(_:)` and `withUTF8EraseFlag(_:)` | `Sources/ForgeLoopTUI/Input/TTYFlags.swift` |

**Action required**: none.  `ForgeLoopCli` now imports these from `ForgeLoopTUI`.

### 1.2 TUIRunner — deleted

`ForgeLoopCli/TUIRunner.swift` (app-local `KeyEvent`, reader loop, raw-tty helpers) has been **removed**.

- `ForgeLoopCli` now uses `ForgeLoopTUI.InputReader` + `ForgeLoopTUI.KeyEvent`.
- `ForgeLoopCli` now uses `ForgeLoopTUI.RawTTY` / `InputPipeline` stack.

**Action required**: none for existing builds; the switch is already landed.

### 1.3 Layout / LayoutRenderer — deleted

| Before | After |
|--------|-------|
| `ForgeLoopCli/Layout.swift` — app-specific layout model with `TerminalSize` | `ForgeLoopTUI.ScreenLayout` + `ForgeLoopTUI.ScreenLayoutConfig` |
| `ForgeLoopCli/LayoutRenderer.swift` — raw `[String]` renderer | `ForgeLoopTUI.ScreenLayoutRenderer` producing `ComposedFrame` |

`ForgeLoopCli` no longer owns a local layout renderer.  It assembles `ScreenLayout` and lets the library render it.

### 1.4 CodingTUI — unified through `CodingTUIFrameBuilder` + `ComposedFrame`

All frame assembly in `CodingTUI.swift` now flows through:

```swift
let frame = CodingTUIFrameBuilder.build(input: .init(
    headerLines: …,
    transcriptLines: …,
    queueLines: …,
    statusLines: …,
    inputLines: …,
    pinnedTranscriptRange: …,
    terminalHeight: …,
    terminalWidth: …,
    showHeader: …,
    cursorOffset: …
))
```

`CodingTUIFrameBuilder` is a thin app-side wrapper around `ScreenLayoutRenderer`.  It keeps app-specific state mapping in the CLI layer while removing duplicated "layout → render" boilerplate.

### 1.5 InputHistory → PromptHistory — extracted to library

| Before (app-owned) | After (library-owned) |
|--------------------|-----------------------|
| `ForgeLoop/Sources/ForgeLoopCli/CodingTUI.swift` contained a local `struct InputHistory` | `Sources/ForgeLoopTUI/Input/PromptHistory.swift` |
| `var inputHistory = InputHistory()` in `runCodingTUIInternal` | `var inputHistory = PromptHistory()` (same call-site, no semantic change) |

`PromptHistory` is a minimal input-history navigation struct with `commit` / `prev` / `next` / `reset` / `isAtCurrent`.
`ForgeLoopCli` now composes it from the library instead of owning a local implementation.

**Action required**: none.  The type change is a drop-in replacement; all call-sites use identical method signatures.

---

## 2. Unfinished Items

| Item | Status | Next Step |
|------|--------|-----------|
| `InputHistory` → `PromptHistory` extraction | **Done** (2026-05-11) | Extracted as `PromptHistory` in `ForgeLoopTUI/Input/PromptHistory.swift`; CLI adopts via drop-in replacement (see §1.5) |
| `AgentEventRenderAdapter` semantic cleanup | **Pending** | Not a migration blocker; can be refined when `CoreRenderEvent` vocabulary stabilises |
| Performance regression gates | **Pending** | See F1; needs benchmark baseline snapshots and statistical sampling strategy |
| Cross-module replay tests (input + layout) | **Pending** | See F1; expand `Integration/` test tree in `ForgeLoopTUI` and `ForgeLoopCliTests` |

---

## 3. Recommendations for Future Maintainers

1. **Never re-introduce app-local render loops**  
   If you need a new input or runtime primitive, extend `ForgeLoopTUI` first, then adopt it in `ForgeLoopCli`.

2. **Keep `CodingTUI.swift` as a thin orchestrator**  
   Agent subscriptions, slash commands, model picker flow, and footer-notice policy stay here.  Terminal plumbing does not.

3. **Prefer `ComposedFrame` over raw `[String]` for all new output paths**  
   This preserves live-region semantics and cursor-offset integrity.

4. **Respect the coalesce guard**  
   Only flatten a `ComposedFrame` to `RenderLoop` when `live.isEmpty && cursorOffset == nil && priority == .normal`.  All other frames must go directly to `TUI.render(frame:)`.

5. **Update docs in the same slice as code changes**  
   `README.md` and this file should be kept in sync with every public-API or boundary change.

---

## 4. From Internal Consumer to Third-Party Consumer

If you are migrating from an internal `ForgeLoopCli`-style consumer to a standalone third-party consumer, watch these differences:

1. **Version pinning**
   - Internal consumers often track `main` or a local path dependency.
   - Third-party consumers should pin to a released version (`from: "1.0.0"`) and review `CHANGELOG.md` before upgrading.

2. **API stability expectations**
   - Internal consumers may use **Internal-detail** APIs (e.g. `ByteStreamBuffer`, `KeyParser`) because they are co-located.
   - Third-party consumers should stick to **Stable** APIs listed in `docs/public-api-surface.md`.

3. **Deprecation discipline**
   - Internal consumers can migrate immediately when an API is deprecated.
   - Third-party consumers may need to support multiple library versions; plan for the deprecation window documented in `docs/semver-and-api-stability.md`.

4. **Test strategy**
   - Internal consumers rely on `ForgeLoopTUI`'s own test suite.
   - Third-party consumers should add their own integration tests using `VirtualTerminal` to guard against upstream behavioral changes.

## 5. Rollback Points

If a regression is detected:

- **TerminalSize / TTYFlags**: revert imports in `CodingTUI.swift` to local copies; restore deleted `TUIRunner.swift` helpers.
- **Layout / LayoutRenderer**: re-create `ForgeLoopCli/Layout.swift` and `ForgeLoopCli/LayoutRenderer.swift` from git history; revert `CodingTUI.swift` frame-assembly sites.
- **FrameBuilder**: inline `CodingTUIFrameBuilder.build` back into `CodingTUI.swift`; delete `CodingTUIFrameBuilder.swift`.

All rollback paths are file-level and do not require library-side reverts.
