# Performance Baseline

Date: 2026-05-13  
Version: 0.2.0 (post Step 6 API stabilisation)

This document records performance baselines for the hot paths that ship with
ForgeLoopTUI's stable API surface. Numbers here are gates, not targets; the
runtime should comfortably out-perform them. The accompanying
`Tests/ForgeLoopTUITests/Runtime/PerformanceBaselineTests.swift` codifies the
gates so regressions surface in CI.

The baselines below are measured on an Apple Silicon laptop in Release
configuration via `swift test -c release --filter PerformanceBaseline`.
Numbers on slower CI runners will be larger; the test asserts a generous
upper bound (≈10× the local measurement) so it stays meaningful across
hardware while still catching algorithmic regressions.

---

## 1. `LiveBudgetPlanner.plan` (Runtime)

### Why this path matters
- Called once per render frame on the (committed, live) buffer pair.
- After Step 3 it is shared by `TUI` and `FrameComposer`; a regression
  doubles its cost everywhere.
- `Review Card / Minor 1` for Step 3 reduced the implementation from
  O(n²) (`while ... totalRows + removeFirst`) to O(n) prefix-accumulation.

### Workload
- `live` length: 10 000 logical lines, each 8 ASCII characters.
- `committed` length: 0.
- Mode: `.logicalLines`, `budget = 100`.
- Repetitions: 50 invocations per measurement.

### Baseline
- p50 wall time per invocation: **<2 ms** on M-series.
- Test gate: 50 invocations finish in **<300 ms** total.

A linear scan is enough for this workload; the gate primarily guards
against accidentally re-introducing the quadratic loop.

---

## 2. `MultiLineInputState` editing (Components)

### Why this path matters
- Every keystroke runs through `handle(_:)`. Long paste / large prompt
  scenarios stress `insertText`, `moveLeft`/`moveRight` and viewport-aware
  vertical navigation.

### Workload
- Start from empty state with `Viewport(width: 80)`.
- `insertText` a 4 000-character single line (no newlines).
- Then run 200 alternating `moveLeft` / `moveRight` actions.
- Then run 50 alternating `moveUp` / `moveDown` actions (viewport-aware).

### Baseline
- p50 wall time for the whole sequence: **<5 ms** on M-series.
- Test gate: total time **<150 ms**.

---

## 3. `KeyResolver.feed` (Input)

### Why this path matters
- Hot per keystroke; chord matching uses a registry lookup plus state
  bookkeeping.

### Workload
- Registry: ~20 bindings including one 2-stroke chord.
- Feed 5 000 `.character("a")` events (passthrough path).

### Baseline
- p50 wall time per 5 000 events: **<10 ms** on M-series.
- Test gate: total time **<200 ms**.

---

## 4. `MultiLineInputState` mixed-width viewport navigation (Components)

### Why this path matters
- Protects the CJK / emoji viewport precision regression surface introduced
  in commit `1d3cfa5` (visibleWidth-aware moveUp/moveDown).
- Mixed-width input forces every viewport vertical move to walk the line
  with `visibleWidth(_:)` and then map the preferred *visible column* back
  to a character index. If either side regresses to O(n²) the impact is
  felt immediately on long pasted prompts.
- Slice-2 (2026-05-13) added this gate explicitly so future optimisation
  passes cannot silently relax the cost.

### Workload
- Start from empty state with `Viewport(width: 80)`.
- `insertText` a 3 996-character line made of the pattern `"ab中🚀cd"`
  repeated 666 times (mixed ASCII + CJK + emoji; ~7 visible cells per
  6 characters → ≈4 662 visible cells total).
- Then run 200 alternating `moveLeft` / `moveRight` actions.
- Then run 50 alternating `moveUp` / `moveDown` actions (viewport-aware,
  visibleWidth-driven geometry).

### Baseline
- p50 wall time for the whole sequence (debug build, M-series): **~0.23 s**;
  variance across 5 consecutive runs <2 %.
- Test gate: total time **<500 ms**.

The gate is intentionally looser than the ASCII case (`<150 ms`) because
the mixed-width path performs additional `visibleWidth` scans plus a
visible-col reverse lookup per move. The bound primarily guards against
algorithmic regressions in the visible-col mapping path, not against
absolute throughput.

---

## 5. How to re-measure

```bash
swift test -c release --filter PerformanceBaseline
```

Replace the assertion bounds in
`Tests/ForgeLoopTUITests/Runtime/PerformanceBaselineTests.swift` if a
deliberate hardware change makes the gate too loose or too tight. Always
update this document in the same commit as the gate change.
