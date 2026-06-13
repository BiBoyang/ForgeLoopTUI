# Pre-Release Drill Report

## 0. Basic Info

| Field | Value |
|-------|-------|
| Date | 2026-06-13 |
| Target release | 1.1.0 |
| Scope | `ForgeLoopTUI` + sibling `ForgeLoop` cross-repo gate |
| Command | `./Scripts/cross-repo-gate.sh --full` |
| ForgeLoopTUI SHA | `f99b81b3aeebc29d70cf31017400a5f382b2107c` |
| ForgeLoop SHA | `7ba0d269be4a0781fda71e2f21fa871ceb6106d7` |
| Executor | `@boyang` |

## 1. Goal

Run the full pre-release rehearsal and classify release risks before tag and release actions.

Special focus for this drill:

- Verify new v1.1.0 public APIs (`TranscriptRenderOptions`, `TUIRenderDiagnostic`, `CoreRenderEvent.blockCancel`, `CoreRenderEvent.thinking`, `Modifiers.command`) do not destabilize the sibling `ForgeLoop` consumer.
- Confirm performance gates remain green after recent rendering and Markdown engine changes.

## 2. Execution Summary

Command:

```bash
./Scripts/cross-repo-gate.sh --full
```

Paste the summary block:

```text
=== Summary ===
PASS: 7
FAIL: 0
Result: PASS
```

Gate details:

| # | Gate | Result | Notes |
|---|------|--------|-------|
| 1 | ForgeLoopTUI build | PASS | |
| 2 | ForgeLoopTUI tests | PASS | 321 tests passed |
| 3 | ForgeLoopTUI integration / public API smoke | PASS | CapabilityEndToEndTests + PublicAPISmokeTests |
| 4 | ForgeLoop build | PASS | |
| 5 | ForgeLoop integration tests | PASS | ScreenLayoutIntegrationTests |
| 6 | ForgeLoop performance baseline | PASS | PerformanceBaselineTests |
| 7 | ForgeLoop performance regression gate | PASS | PerformanceGateTests |

## 3. Risk Classification

### Blocker

- None

### High

- None

### Medium

- None

### Low

- None

## 4. Performance Snapshot Delta

Compared against the previous accepted baseline snapshot in sibling `ForgeLoop` (`docs/perf-baseline-snapshots.md`, dated 2026-05-11).

| Metric | Previous p50 | Current p50 | Delta | Verdict |
|--------|--------------|-------------|-------|---------|
| render-small-first | 0.049 ms | 0.050 ms | +2.0% | pass |
| render-small-nochange | 0.049 ms | 0.049 ms | 0.0% | pass |
| render-small-partial | 0.052 ms | 0.049 ms | -5.8% | pass |
| render-medium-first | 0.350 ms | 0.344 ms | -1.7% | pass |
| render-medium-append | 0.358 ms | 0.348 ms | -2.8% | pass |
| render-medium-rapid-refresh | 0.345 ms | 0.340 ms | -1.4% | pass |
| render-large-first | 1.854 ms | 1.831 ms | -1.2% | pass |
| render-large-stream-append | 1.888 ms | 1.825 ms | -3.3% | pass |
| transcript-apply | 0.010 ms | 0.009 ms | -10.0% | pass |

Verdict rules:

- `<= 5%`: pass
- `> 5%` and `<= 10%`: warn; explain in release notes
- `> 10%`: fail unless an explicit exception is approved with an issue, time box, and rollback plan

All primary rendering metrics are flat or improved. The `transcript-apply` metric improved by approximately 10% and remains well within gate thresholds; no action required.

## 5. Rollback Point

- Last known good ForgeLoopTUI SHA: `f99b81b3aeebc29d70cf31017400a5f382b2107c` (HEAD)
- Last known good ForgeLoop SHA: `7ba0d269be4a0781fda71e2f21fa871ceb6106d7` (HEAD)
- Revert plan: If a critical issue is found after release, do not delete the tag. Publish a PATCH release immediately and document the issue and fix in `CHANGELOG.md`.

## 6. Release Decision

| Decision | Selected |
|----------|----------|
| GO: full gate passes and no blocker/high risk remains | [x] |
| NO-GO: blocker or unapproved `>10%` regression exists | [ ] |
| GO with watch: no blocker, but follow-up risk remains | [ ] |

Decision rationale:

> Full cross-repo gate passes. All performance deltas are within the `<= 5%` pass band (rendering) or represent a measured improvement (`transcript-apply`). No new public Stable API was removed; only new Stable/Provisional symbols were added. Public API surface document has been updated to reflect new symbols. Release is approved for `v1.1.0`.

## 7. Next Minimal Actions

1. Commit the version bump and changelog updates.
2. Tag `v1.1.0` and push the tag.
3. Create GitHub Release with the `CHANGELOG.md` `[1.1.0]` section.
4. Verify Swift Package Manager resolves the new tag.

## Related Documents

- `docs/release-checklist.md`
- `docs/semver-and-api-stability.md`
- `docs/performance-baseline.md`
- Sibling `ForgeLoop` performance baseline and regression policy documents
