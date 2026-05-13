# TUI Hotspot Pre-Research Report

Date: 2026-05-13  
Repo: `/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI`  
Baseline ref: `main` post Slice-2 (`3bc3ecf`)  
Scope: identify the next P0/P1/P2 optimisation candidates on `TUI` hot paths
without committing to implementation in this slice.

---

## 1. Measurement Environment

| Item | Value |
|------|-------|
| Hardware | Apple M-series laptop (arm64e) |
| OS | Darwin 25.5.0 (macOS) |
| Swift build | `swift test` (default debug — same as CI gates) |
| Test framework | Swift Testing 1743 |
| Commands fixed for this slice | `swift test --filter PerformanceBaselineTests` / `… --filter CommittedLiveRenderTests` / `… --filter TUITests` |

The numbers below come from a single `swift test --filter PerformanceBaselineTests`
run (debug build, same configuration as the gates in
`Tests/ForgeLoopTUITests/Runtime/PerformanceBaselineTests.swift`). Release-mode
numbers will be lower; debug numbers are what the CI gates actually see.

---

## 2. Data Snapshot

| Test | Workload | Elapsed (debug) | Gate | Headroom |
|------|----------|-----------------|------|----------|
| `KeyResolver.feed character passthrough` | 5 000 chars | **12 ms** | <200 ms | 16.7× |
| `LiveBudgetPlanner.plan large live` | 50 × 10 000-line live | **71 ms** | <300 ms | 4.2× |
| `MultiLineInputState long paste (ASCII)` | 4 000-char ASCII + 200 LR + 50 UD | **81 ms** | <150 ms | 1.85× |
| `MultiLineInputState mixed-width viewport` | 3 996-char `ab中🚀cd`×666 + 200 LR + 50 UD | **229 ms** | <500 ms | 2.18× |

Cross-test comparison: at identical workload shape, mixed-width is **2.83×**
the ASCII case (`229 ms / 81 ms`). The delta is the entire CJK/emoji
visibleWidth + visible-col mapping overhead.

---

## 3. Candidate Hotspots

### 3.1 `MultiLineInputState.charIndex(in:atVisibleColumn:)` — **P0**

**Where:** `Sources/ForgeLoopTUI/Components/MultiLineInputState.swift:428–447`

**Issue:** the function maps a target visible column back to a character index
by iterating Characters and calling `visibleWidth(String(character))` on each
one. Per-character call into `visibleWidth` is expensive because `visibleWidth`:

1. Constructs an intermediate `String` from a single Character.
2. Calls `ansiStripped` over that string (returns another fresh string).
3. Then walks scalars through the large `isWide` range chain.

Each viewport `moveUp`/`moveDown` in our mixed-width workload triggers one
`charIndex` call. For a 3 996-character line the worst case is **3 996
`visibleWidth(String(character))` invocations per move**.

**Cost evidence:** 50 viewport vertical moves take roughly `229 - 81 = 148 ms`
of "mixed-width tax" over the ASCII baseline. ~3 ms/move is consistent with
~4 000 per-character allocations + ansi-strips.

**Proposed fix sketch (P0, low risk):**
- Add a cheap per-`Character` width helper (no allocation, no ANSI strip):
  inspect the Character's `unicodeScalars` directly and apply the same wide
  range table inline. Skip the `String(character)` round-trip entirely.
- `charIndex` keeps its outer loop but stops allocating per step.

Expected impact: ≥40% drop on the mixed-width viewport gate (back into the
<150 ms range of the ASCII case). Algorithmic complexity unchanged; only the
constant factor moves.

**Risk:** the inline width table must remain in sync with `visibleWidth`'s
range list. Mitigation: keep one source of truth (a `static let` table or
private helper file) and have both call sites use it.

---

### 3.2 `MultiLineInputState.visualRowCount` + `visibleColumn` redundant
full-line scans — **P1**

**Where:**
- `visualRowCount(forLine:width:)` — `MultiLineInputState.swift:356–360`
- `visibleColumn(in:charIndex:)` — `MultiLineInputState.swift:421–426`

**Issue:** every viewport `moveUp`/`moveDown` runs:

1. `visibleColumn(in:charIndex:)` over the cursor prefix.
2. `currentPreferredVisualColumn()` (may also run `visibleColumn` if the flag
   says refresh).
3. `visualRowCount(forLine:width:)` which calls `visibleWidth(line)` over the
   **whole** line.
4. `charIndex(in:atVisibleColumn:)` (covered by §3.1).

So each move pays at minimum two O(line-length) scans (prefix + full line)
*before* the per-character work in §3.1. On a 4 000-character line this is
substantial constant overhead.

**Proposed fix sketch (P1, medium risk):**
- Cache `(lineId → totalVisibleWidth)` keyed by line content version. The
  cache must invalidate on every mutating action that touches the cursor's
  line. Use a thin "line revision counter" in `MultiLineInputState` rather
  than hashing the whole line.
- Avoid double-computing `currentPreferredVisualColumn`'s prefix when it was
  just refreshed during the same handler call.

Expected impact: another 10–20% off the mixed-width gate. Less significant
than §3.1; only worth doing **after** §3.1 lands and we re-measure.

**Risk:** caches and editor state interact badly when mutations are missed.
The line-revision-counter approach localises the invariant to one place, but
unit tests must cover insertion, deletion, replacement, and viewport resize.

---

### 3.3 `TUIRuntime` marker/relative placement `visibleWidth(live[i])`
duplication — **P2**

**Where:** `Sources/ForgeLoopTUI/Runtime/TUIRuntime.swift:271,273,303,305`

**Issue:** `emitRelativePlacement` calls `visibleWidth(live[targetRowIndex])`
and `visibleWidth(live[liveCount - 1])`. `emitMarkerPlacement` does the same
two calls plus a `physPerRow = live.map { physicalRows(for: $0, width: w) }`,
which internally is another `visibleWidth(line)` per live line.

If `targetRowIndex == liveCount - 1` (cursor on the bottom live row — the
common case during streaming), `visibleWidth` runs twice on the same line in
both paths.

**Cost evidence:** the `LiveBudgetPlanner` test (which is dominated by the
same `physicalRows` chain) takes only **71 ms** for 50 × 10 000 lines. So
the marker/relative paths are **not** the dominant cost. This is a
correctness-preserving micro-optimisation, not a hot fix.

**Proposed fix sketch (P2, very low risk):**
- Compute `lastLineWidth` and `targetRowWidth` once at the top of each
  function. When `targetRowIndex == liveCount - 1`, reuse the same value.
- In `emitMarkerPlacement`, derive `lastRowPhys` from
  `physPerRow[liveCount - 1]` (already done) and use it instead of any
  redundant computation.

Expected impact: <5% on render path latency under heavy live streaming. Real
win is code clarity (one shared local for "last row width").

**Risk:** essentially none if guarded by the `liveCount > 0` precondition
that already exists.

---

## 4. Optional A/B Experiment (Step 3.3) — Skipped

A/B was scoped as optional. The data above already gives a confident
ordering, and §3.1's expected impact (≥40%) is large enough that an
experimental sub-slice is unwarranted before committing the actual
optimisation. The next slice should run the A/B as part of its DoD, not as
prep work here.

---

## 5. Conclusions

| Hotspot | Decision | Priority | Next slice DoD |
|---------|----------|----------|----------------|
| §3.1 `charIndex` per-Character visibleWidth allocations | **Do** | **P0** | mixed-width gate <150 ms; full `swift test` green; no threshold change |
| §3.2 `visualRowCount` / `visibleColumn` cache | **Do (after §3.1)** | **P1** | additional ≥10% off mixed-width gate; cache invariant covered by tests |
| §3.3 marker/relative dedupe | **Do (opportunistic)** | **P2** | piggyback on the next TUIRuntime touch; no dedicated slice |

The dominant cost on the mixed-width path is allocation-per-Character inside
`charIndex`, not the algorithm itself. The fix is a constant-factor micro
change that the existing performance gate will detect immediately.

---

## 6. Risks and Rollback Points

1. **Inline width table drift (§3.1):** keep a single source of truth (a
   private static table) and reuse it from both `visibleWidth` and the new
   per-Character helper. Add a unit test that asserts equivalence over a
   curated sample (ASCII, CJK, emoji, control, combining marks).
2. **Cache invalidation (§3.2):** use a line-revision counter that
   increments on every mutating handler. Tests must cover insert, delete,
   replace, kill-line, and `setViewport` width change.
3. **Rollback:** §3.1 and §3.2 will land as separate commits behind the
   existing `PerformanceBaselineTests` gates. Rolling either back is a
   `git revert` of the corresponding commit; gates will catch the
   regression on the next CI run.
4. **No threshold relaxation:** under any optimisation slice, the gate
   numbers in `PerformanceBaselineTests` must not be raised to hide an
   incomplete improvement. If the optimisation does not clear the budget,
   investigate further or back out.

---

## 7. Pointers

- Performance gates: `Tests/ForgeLoopTUITests/Runtime/PerformanceBaselineTests.swift`
- Baseline doc: `docs/performance-baseline.md`
- Slice plan (this work): `notes/local/TMP-2026-05-13-TUI-slices-1-2-3.md`
- Maintenance protocol (regression handling SOP):
  `docs/post-m7-maintenance-protocol.md` §7
