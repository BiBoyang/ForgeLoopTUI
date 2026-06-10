# Pre-Release Drill Report Template

Use this template for release-candidate rehearsals that run the full cross-repo
gate before tagging a release.

Copy it to `docs/pre-release-drill-YYYY-MM-DD.md` or attach an equivalent
report to the release issue.

---

## 0. Basic Info

| Field | Value |
|-------|-------|
| Date | `YYYY-MM-DD` |
| Target release | `X.Y.Z` or `RC-n` |
| Scope | `ForgeLoopTUI` + sibling `ForgeLoop` cross-repo gate |
| Command | `./Scripts/cross-repo-gate.sh --full` |
| ForgeLoopTUI SHA | `git rev-parse HEAD` |
| ForgeLoop SHA | `git -C ../ForgeLoop rev-parse HEAD` or explicit checkout path |
| Executor | `@username` |

## 1. Goal

Run the full pre-release rehearsal and classify release risks before tag and
release actions.

Special focus for this drill:

-

## 2. Execution Summary

Command:

```bash
./Scripts/cross-repo-gate.sh --full
```

Paste the summary block:

```text
=== Summary ===
PASS: N
FAIL: N
Result: PASS / FAIL
```

Gate details:

| # | Gate | Result | Notes |
|---|------|--------|-------|
| 1 | ForgeLoopTUI build | PASS / FAIL | |
| 2 | ForgeLoopTUI tests | PASS / FAIL | |
| 3 | ForgeLoopTUI integration / public API smoke | PASS / FAIL | |
| 4 | ForgeLoop build | PASS / FAIL | |
| 5 | ForgeLoop integration tests | PASS / FAIL | |
| 6 | ForgeLoop performance baseline | PASS / FAIL | |
| 7 | ForgeLoop performance regression gate | PASS / FAIL | |

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

Compare the current performance results against the latest baseline snapshot in
the sibling `ForgeLoop` repository.

| Metric | Previous p50 | Current p50 | Delta | Verdict |
|--------|--------------|-------------|-------|---------|
| render-small-first | | | | pass / warn / fail |
| render-small-nochange | | | | pass / warn / fail |
| render-small-partial | | | | pass / warn / fail |
| render-medium-first | | | | pass / warn / fail |
| render-medium-append | | | | pass / warn / fail |
| render-medium-rapid-refresh | | | | pass / warn / fail |
| render-large-first | | | | pass / warn / fail |
| render-large-stream-append | | | | pass / warn / fail |
| transcript-apply | | | | pass / warn / fail |

Verdict rules:

- `<= 5%`: pass
- `> 5%` and `<= 10%`: warn; explain in release notes
- `> 10%`: fail unless an explicit exception is approved with an issue, time
  box, and rollback plan

## 5. Rollback Point

- Last known good ForgeLoopTUI SHA:
- Last known good ForgeLoop SHA:
- Revert plan:

## 6. Release Decision

| Decision | Selected |
|----------|----------|
| GO: full gate passes and no blocker/high risk remains | [ ] |
| NO-GO: blocker or unapproved `>10%` regression exists | [ ] |
| GO with watch: no blocker, but follow-up risk remains | [ ] |

Decision rationale:

>

## 7. Next Minimal Actions

1.
2.
3.

## Related Documents

- `docs/release-checklist.md`
- `docs/semver-and-api-stability.md`
- `docs/performance-baseline.md`
- Sibling `ForgeLoop` performance baseline and regression policy documents
