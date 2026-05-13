# TODO

## Current Focus

Ongoing maintenance and stabilization of `ForgeLoopTUI` as a reusable TUI framework.

### Next Slice Queue (Post-1.0)

1. **Performance gate discipline**
   - Keep `PerformanceBaselineTests` / `PerformanceGateTests` snapshots current.
   - Document accepted regressions (if any) before merge.
   - **SOP**：退化处置流程见 `docs/post-m7-maintenance-protocol.md` §7（复现→归因→决策→记录）。
   
2. **Optional cleanup (strictly non-blocking)**
   - Revisit `AgentEventRenderAdapter` semantic cleanup only when event vocabulary stabilizes.

3. **Post-1.0 deferred items**
   - DocC catalog and hosted API reference
   - Swift Package Index integration
   - Additional example packages

4. **CJK viewport precision** — ✅ Completed (commit `1d3cfa5` + Slice-1 docs 收口)
   - `visibleWidth`-aware viewport vertical navigation in `MultiLineInputState` shipped.
   - 4 contract tests (`testViewport*MixedWidth*` / `testViewportResizeThenMoveUsesNewVisibleGeometry*`) all green.
   - Plan: `plans/TASK-cjk-visiblewidth-viewport.md`（status updated to Completed）.

5. **Mixed-width performance baseline** *(Slice-2 — queued)*
   - Add `testMultiLineInputMixedWidthViewportUnderBudget` gate in `PerformanceBaselineTests`.
   - Sync `docs/performance-baseline.md` with new workload + gate.
   - DoD: stable under 5× re-run; full `swift test` green; no threshold relaxation to hide regressions.

6. **TUI hotspot pre-research** *(Slice-3 — queued)*
   - Profile `TUIRuntime.marker` `visibleWidth` re-computation, `LiveBudgetPlanner.physicalRows` long-live scans, and `MultiLineInputState` visible-col ↔ char-index mapping.
   - Output: `notes/local/REPORT-2026-05-13-tui-hotspots.md`（measurements + priorities + risks）.

## Explicitly Stay In ForgeLoopCli

- `Sources/ForgeLoopCli/AgentEventRenderAdapter.swift`
- `Sources/ForgeLoopCli/PromptController.swift`
- `Sources/ForgeLoopCli/SlashCommandRegistry.swift`
- `Sources/ForgeLoopCli/AttachmentStore.swift`
- `Sources/ForgeLoopCli/CredentialStore.swift`
- `Sources/ForgeLoopCli/ModelStore.swift`
- App-specific parts of `Sources/ForgeLoopCli/CodingTUI.swift`

## Notes

- Keep `ForgeLoopTUI` focused on reusable terminal runtime, transcript, markdown, input, and composition primitives.
- Keep app-specific layout semantics, Agent adaptation, model switching, auth, and attachment payload policy in `ForgeLoop`.
