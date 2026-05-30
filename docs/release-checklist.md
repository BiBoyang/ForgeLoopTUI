# Release Checklist

Date: 2026-05-11  
Applies to: `ForgeLoopTUI` Swift Package  
Policy: `docs/semver-and-api-stability.md`

---

## Pre-flight

- [ ] Confirm release version follows SemVer (`docs/semver-and-api-stability.md` §1).
- [ ] Confirm no `WIP` / `TODO` / `FIXME` comments in `public` API surface.
- [ ] Confirm `Package.swift` `platforms` and `swiftLanguageModes` are correct.

---

## 1. Code & test gate

Run every command. All must pass.

- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift test --filter ScreenLayoutRendererTests`
- [ ] `swift test --filter ComponentTests`
- [ ] `swift test --filter LayoutBudgetTests`
- [ ] `swift test --filter CommittedLiveRenderTests`
- [ ] `swift test --filter TUITests`
- [ ] `swift test --filter InputPipelineTests`
- [ ] `swift test --filter KeyParserTests`
- [ ] `swift test --filter ANSIParserTests`
- [ ] `swift test --filter VirtualTerminalTests`
- [ ] `swift test --filter HybridRenderAdapterTests`
- [ ] `swift test --filter CapabilityEndToEndTests`
- [ ] `swift test --filter PublicAPISmokeTests`
- [ ] In sibling `ForgeLoop` repo: `swift build`
- [ ] In sibling `ForgeLoop` repo: `swift test --filter ScreenLayoutIntegrationTests`
- [ ] `./Scripts/cross-repo-gate.sh --quick`

---

## 2. Documentation sync check

- [ ] `README.md` references the current version in the SwiftPM example.
- [ ] `README.md` links to `docs/integration-guide.md`, `docs/public-api-surface.md`, `docs/semver-and-api-stability.md`.
- [ ] `docs/integration-guide.md` is up to date with the latest API shape.
- [ ] `docs/migration-guide-for-forgeloopcli.md` has no stale "pending" items that are now done.
- [ ] `docs/public-api-surface.md` lists every new `public` type added since the last release.
- [ ] `docs/semver-and-api-stability.md` has no contradictions with the actual API surface.
- [ ] `CHANGELOG.md` `[Unreleased]` reflects the current focus.

---

## 3. API change audit

- [ ] Run `git diff <last-tag>..HEAD -- Sources/ForgeLoopTUI/` and review every `public` change.
- [ ] For every removed or changed `public` symbol:
  - [ ] Confirm it was marked **Deprecated** in a previous release (if **Stable**).
  - [ ] Or confirm the change is to a **Provisional** / **Internal-detail** API.
- [ ] For every new `public` symbol:
  - [ ] Confirm it is marked **Stable** or **Provisional** in `docs/public-api-surface.md`.
- [ ] Confirm no accidental `public` exposure of internal types (check `internal` → `public` diffs).

---

## 4. Performance / regression gate

- [ ] In sibling `ForgeLoop` repo: `swift test --filter PerformanceBaselineTests`
- [ ] In sibling `ForgeLoop` repo: `swift test --filter PerformanceGateTests`
- [ ] `./Scripts/cross-repo-gate.sh --full`
- [ ] Compare p50 results against the last baseline snapshot in `ForgeLoop/docs/perf-baseline-snapshots.md`.
- [ ] If any p50 regresses `>10%`:
  - **必须阻塞发布**，或
  - **给出已批准的例外记录**：linked issue + time-box + rollback plan + maintainer 书面批准（记录在 issue 与 release notes 中）。
  - 禁止通过放宽阈值来“放过”回归。
- [ ] 若存在 `>5%` 且 `<=10%` 的 warn 级退化，在 release notes 中说明原因并知会 maintainer。
- [ ] 附上前一次 `--full` 演练报告（`docs/pre-release-drill-YYYY-MM-DD.md`），或本次 RC 新产出的报告。报告必须包含：gate 结果汇总、风险分级、发布决策（go/no-go）。

---

## 5. Tag & release notes

- [ ] Update `CHANGELOG.md` with the new version entry (follow format in `docs/semver-and-api-stability.md` §7).
- [ ] Commit: `git add CHANGELOG.md && git commit -m "chore: bump changelog for X.Y.Z"`
- [ ] Tag: `git tag -a X.Y.Z -m "Release X.Y.Z"`
- [ ] Push tag: `git push origin X.Y.Z`
- [ ] Create GitHub Release with:
  - [ ] Release title: `ForgeLoopTUI X.Y.Z`
  - [ ] Copy `CHANGELOG.md` section into release body
  - [ ] Attach `.xcframework` if distributing binaries (optional)

---

## 6. Post-release

- [ ] Verify Swift Package Manager resolves the new tag:
  ```bash
  swift package resolve
  ```
- [ ] Verify the badge in `README.md` updates (GitHub caches badges; may take minutes).
- [ ] Announce in relevant channels (if applicable).

---

## Rollback

If a critical issue is found after release:

1. Do **not** delete the tag (breaks SPM resolution).
2. Publish a PATCH release immediately.
3. Document the issue and fix in `CHANGELOG.md`.

---

## Related documents

- `docs/semver-and-api-stability.md` — SemVer policy and breaking-change definitions
- `docs/public-api-surface.md` — Per-type stability assignment
- `docs/integration-guide.md` — Consumer guidance
