# Task Plan: CJK `visibleWidth`-Aware Viewport Precision

Date: 2026-05-13  
Scope: `MultiLineInputState` visual-row navigation (`moveUp` / `moveDown`)  
Status: Planned (implementation not started)

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

### Step A — Test Matrix (Failing-First)

Add focused tests in `Tests/ForgeLoopTUITests/Components/MultiLineInputTests.swift`
for viewport visual moves with wide-cell text:

1. Single-line mixed-width wrap (`"ab中文cd"` with narrow viewport).
2. Multi-line cross-boundary move preserving visual column.
3. Clamp behavior when target visual column lands beyond short next line.
4. Emoji + CJK mixed sequences (grapheme clusters + wide cells).
5. Resize scenario (`setViewport` width change) preserving expected next move.

DoD:
- New tests are deterministic and document expected visible-row semantics.
- Existing viewport tests remain green.

### Step B — Geometry Refactor (Internal Only)

Refactor `MultiLineInputState` internal visual movement helpers to:

1. Compute cursor visual column from prefix `visibleWidth`.
2. Compute line visual row count from `visibleWidth(line)` + viewport width.
3. Map target visual column back to character index by scanning grapheme
   boundaries and accumulating `visibleWidth`.
4. Preserve preferred visual column intent across repeated up/down moves.

DoD:
- No public signature changes.
- All viewport + CJK tests pass.

### Step C — Regression and Performance Guard

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

---

## Risk Notes

1. Grapheme-to-cell mapping can introduce off-by-one behavior at wrap edges.
2. Repeated `visibleWidth` scans may regress hot-path latency if not cached or
   bounded carefully.
3. Behavior changes are user-visible; contract tests must define exact intent.

---

## Rollback Point

If regression appears, rollback only the Step B commit and keep Step A tests as
specification guards (marking expected failures temporarily if needed).
