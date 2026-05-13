# Task Plan: CJK `visibleWidth`-Aware Viewport Precision

Date: 2026-05-13  
Scope: `MultiLineInputState` visual-row navigation (`moveUp` / `moveDown`)  
Status: **Completed** (Step A + Step B + Step C all done; landed in `1d3cfa5`)

---

## Goal

Upgrade viewport-based vertical navigation from character-count geometry to
`visibleWidth` geometry, so mixed ASCII/CJK/emoji lines move exactly by visual
cells and rows.

Current behavior is documented in source as character-count based. This plan
targets a behavior-level precision upgrade while keeping the public API shape
unchanged.

---

## Out of Scope

- No public API rename/removal (`Viewport`, `setViewport(_:)`, action enums stay unchanged).
- No changes to non-viewport logical navigation paths.
- No rendering engine rewrite (`TUIRuntime` cursor positioning remains separate).

---

## Milestones and Steps

### Step A — Test Matrix (Failing-First) — ✅ Done

Added focused tests in `Tests/ForgeLoopTUITests/Components/MultiLineInputTests.swift`
for viewport visual moves with wide-cell text:

1. Single-line mixed-width wrap (`"ab中文cd"` with narrow viewport).
2. Multi-line cross-boundary move preserving visual column.
3. Clamp behavior when target visual column lands beyond short next line.
4. Emoji + CJK mixed sequences (grapheme clusters + wide cells).
5. Resize scenario (`setViewport` width change) preserving expected next move.

DoD:
- New tests are deterministic and document expected visible-row semantics.
- Existing viewport tests remain green.

**Result:** 4 contract tests added, all expectedly failing against the old
character-count implementation. Original 32 tests remained green throughout.

### Step B — Geometry Refactor (Internal Only) — ✅ Done

Refactored `MultiLineInputState` internal visual movement helpers to:

1. Compute cursor visual column from prefix `visibleWidth`.
2. Compute line visual row count from `visibleWidth(line)` + viewport width.
3. Map target visual column back to character index by scanning grapheme
   boundaries and accumulating `visibleWidth`.
4. Preserve preferred visual column intent across repeated up/down moves.

DoD:
- No public signature changes.
- All viewport + CJK tests pass.

**Result:** Introduced `preferredVisualColumn` (refresh-on-demand),
`visibleColumn(in:charIndex:)` helper, and visible-col ↔ char-index lookup;
landed in commit `1d3cfa5`. Public API surface unchanged.

### Step C — Regression and Performance Guard — ✅ Done

Run:

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
swift test --filter MultiLineInputTests
swift test --filter PerformanceBaselineTests
swift test
```

DoD:
- `MultiLineInputTests` all pass.
- `PerformanceBaselineTests` pass without relaxing thresholds.
- Full `swift test` remains green.

**Result:** All three commands pass. The four mixed-width contract tests now
report the expected `cursorColumn` (2 / 4 / 2 / 2) on the corresponding cases.
Existing thresholds in `PerformanceBaselineTests` were not relaxed.

---

## Risk Notes

1. Grapheme-to-cell mapping can introduce off-by-one behavior at wrap edges.
2. Repeated `visibleWidth` scans may regress hot-path latency if not cached or
   bounded carefully.
3. Behavior changes are user-visible; contract tests must define exact intent.

## Verification Summary (post-landing)

- Contract tests: `testViewportMoveUpWithinMixedWidthLineUsesVisibleColumn`,
  `testViewportMoveUpAcrossBoundaryPreservesVisibleColumnForMixedWidth`,
  `testViewportMoveDownAcrossBoundaryUsesVisibleColumnForMixedWidth`,
  `testViewportResizeThenMoveUsesNewVisibleGeometryForMixedWidth` — all green.
- Doc / source-comment alignment closed under Slice-1 (this iteration).
- Mixed-width performance baseline tracked under Slice-2 follow-up.

---

## Rollback Point

If regression appears, rollback only the Step B commit (`1d3cfa5`) and keep
Step A tests as specification guards (marking expected failures temporarily
if needed).
