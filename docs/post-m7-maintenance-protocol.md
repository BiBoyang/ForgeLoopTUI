# Post-M7 Maintenance Protocol (Lightweight)

Date: 2026-05-11
Applies to: `ForgeLoopTUI` + `ForgeLoopCli` collaboration workflow

## 1) One Slice Per Task

- Each task must have one primary objective.
- No "while I am here" unrelated refactors.
- Delivery must include:
  - Goal
  - File list
  - Validation commands
  - Rollback point

## 2) Boundary Before Feature

- Decide boundary first for every new capability:
  - Generic/reusable capability -> `ForgeLoopTUI`
  - App-specific orchestration/business flow -> `ForgeLoopCli`
- No boundary backflow (do not re-implement library primitives in CLI).

### 2.1 PromptHistory boundary (hard rule)

- `PromptHistory` is a library-side primitive in `ForgeLoopTUI/Input/PromptHistory.swift`.
- **Forbidden**: re-introducing an app-local input history implementation in `ForgeLoopCli` (e.g. a local `struct InputHistory`, or equivalent mutable state with `prev`/`next` navigation).
- Any PR that touches input history navigation MUST:
  1. reference `PromptHistory` as the single source of truth
  2. include the cross-repo gate result (`./Scripts/cross-repo-gate.sh --quick`) in the PR description
- **Evolution gate**: before adding new capabilities to `PromptHistory` (capacity limit, dedup, persistence, multi-group, etc.), the three triggers in `docs/prompt-history-api-decision.md` §4 must all be met: real-world evidence, contract test coverage, and cross-repo gate pass.
- **Frozen for current phase**: `commit`, `prev`, `next`, `reset`, `isAtCurrent`. See `docs/prompt-history-api-decision.md` §3 for the full list of deferred enhancements.

## 3) Test Gate Must Not Regress

- Minimum gate set for relevant changes:
  - `ScreenLayoutRendererTests`
  - `CodingTUIStatusTests`
  - `ScreenLayoutIntegrationTests`
  - `Performance` filters
- Semantic changes must add or update contract tests.

## 4) Docs Updated In Same Slice

- Any API/behavior/milestone change must update docs in the same slice:
  - `README.md`
  - Primary planning docs
  - `todo.md`
- Documentation state must match code state at merge time.

## 5) Scorecard Changes Need Evidence

- Score updates require evidence from at least one of:
  - code merge
  - passing tests
  - performance snapshots/gates
  - synced docs
- No evidence, no score change.
- Regressions must be recorded and scored down per governance rules.

## 6) Cross-Repo Gate Is Mandatory Before Pre-Release

- Post-M7 validation must include both repositories:
  - `ForgeLoopTUI`
  - `ForgeLoop` (`ForgeLoopCli` integration + performance gates)
- Use:
  - `./Scripts/cross-repo-gate.sh --quick` for routine slices
  - `./Scripts/cross-repo-gate.sh --full` for pre-release rehearsal
- If quick/full gate fails:
  - block score increase
  - record blocker/high risk items
  - define rollback points before merge
- Performance regressions follow the delta thresholds and exception rules in `ForgeLoop/docs/perf-regression-policy.md`:
  - `<= 5%` → pass
  - `> 5%` and `<= 10%` → warn (requires explanation)
  - `> 10%` → fail (fix or roll back)
  - One-time exceptions are allowed only with a linked issue, time-box, rollback plan, and maintainer approval.

## 7) Performance Regression Handling SOP

当 gate 或 baseline 采集发现性能退化时，按以下固定流程处置，禁止口头绕开。

### 7.1 复现（Reproduce）

1. **同机同命令重跑** — 使用与首次发现完全相同的命令：
   - Baseline: `cd /Users/boyang/Desktop/WebKit_build/ForgeLoop && swift test --filter PerformanceBaselineTests`
   - Gate: `cd /Users/boyang/Desktop/WebKit_build/ForgeLoop && swift test --filter PerformanceGateTests`
   - Cross-repo: `cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI && ./Scripts/cross-repo-gate.sh --quick`
2. **环境降噪** — 关闭重应用、接电源、避免备份/索引时段；记录 OS / CPU / Swift 版本。
3. **独立运行 3 次** — 记录每次 p50 与 p95。
   - 若 0/3 失败 → 瞬态噪音，忽略。
   - 若 1/3 失败 → 持续观察，不阻塞。
   - 若 2/3 或 3/3 失败 → 进入归因。

### 7.2 归因（Attribute）

按以下顺序排查，每步必须留下记录（issue comment 或 PR 描述）：

1. **代码变更** — `git diff <last-good-sha>..HEAD` 检查是否有渲染路径、数据结构、锁粒度改动。
2. **环境变更** — OS 更新、Xcode/Swift 升级、硬件差异。
3. **样本/测量变更** — 迭代次数、warm-up 轮次、测试数据规模是否被修改。
4. **基线漂移** — 上一次基线是否本身就是在异常环境下采集的。

### 7.3 决策（Decide）

| 退化幅度 | 决策 | 必要条件 |
|----------|------|----------|
| `<= 5%` | **接受** | 无需额外流程，正常合并/发布。 |
| `> 5%` 且 `<= 10%` | **接受（带解释）** | 在 PR / release notes / snapshot `note` 中说明原因；需 maintainer 知情。 |
| `> 10%` | **修复或回滚** | 阻塞合并/发布；必须在修复后重新跑通 gate。 |
| `> 10%`（例外） | **接受（一次性受控例外）** | 必须同时满足：① linked issue 说明原因；② 明确 time-box（截止日期）；③ 已识别回滚 commit/PR；④ maintainer 书面批准。 |

**禁止**：为通过测试而放宽阈值（thresholdFactor / 基线常量）。阈值调整必须走基线更新规则（见 `perf-regression-policy.md` §5）。

### 7.4 记录（Record）

无论最终决策如何，必须留下可追溯记录：

1. **更新快照文档** — 在 `ForgeLoop/docs/perf-baseline-snapshots.md` 追加新快照，填写标准模板字段（date / git_sha / machine / os / swift_version / test_filter / sample_count / p50 / p95 / baseline_delta(%) / verdict / note）。
2. **关联 issue** — 若退化 >5%，必须创建或引用已有 issue，标题格式建议：`perf(regression): <metric> +<delta>% since <sha>`。
3. **更新发布检查单** — 若涉及发布，在 `release-checklist.md` §4 中勾选并附注。
4. **关闭循环** — issue 状态随修复/回滚/例外到期而更新；修复后必须附上新 baseline 数据再关闭。

### 7.5 Gate 命令映射

| 场景 | 命令 | 用途 |
|------|------|------|
| 日常切片 | `./Scripts/cross-repo-gate.sh --quick` | 快速验证，包含性能 gate 子集 |
| RC 前彩排 | `./Scripts/cross-repo-gate.sh --full` | 全量验证，包含完整 PerformanceBaseline + PerformanceGate |
| 单仓库基线 | `swift test --filter PerformanceBaselineTests` | 采集/更新快照 |
| 单仓库门禁 | `swift test --filter PerformanceGateTests` | PR 合并前阈值检查 |
