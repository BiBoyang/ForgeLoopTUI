# Pre-Release Drill Report Template

> 用途：每次 RC（Release Candidate）前执行 `--full` gate 后，按此模板产出演练报告。  
> 目标：新同学可在 15 分钟内完成一份合格报告。  
> 历史样例：`docs/pre-release-drill-YYYY-MM-DD.md`

---

## 0) 基本信息（必填）

| 字段 | 内容 |
|------|------|
| **Date** | `YYYY-MM-DD` |
| **Scope** | `ForgeLoopTUI` + `ForgeLoop` cross-repo pre-release rehearsal |
| **Command** | `./Scripts/cross-repo-gate.sh --full` |
| **TUI SHA** | `git -C /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI rev-parse HEAD` |
| **ForgeLoop SHA** | `git -C /Users/boyang/Desktop/WebKit_build/ForgeLoop rev-parse HEAD` |
| **Executor** | `@username` |
| **Target release** | `X.Y.Z`（或 `RC-n`） |

---

## 1) Drill Goal

Run a full pre-release rehearsal on both repositories and classify release risks before final release actions.

> 若本次演练有特殊关注点（如新增性能 case、重大重构），在此补充 1-2 句。

---

## 2) Execution Summary

### 2.1 命令输出

```bash
cd /Users/boyang/Desktop/WebKit_build/ForgeLoopTUI && ./Scripts/cross-repo-gate.sh --full
```

粘贴 `=== Summary ===` 区块：

```
=== Summary ===
  PASS: N
  FAIL: N
Result: PASS / FAIL
```

### 2.2 各 gate 明细

| # | Gate | 命令 | 结果 |
|---|------|------|------|
| 1 | ForgeLoopTUI build | `swift build` | PASS / FAIL |
| 2 | ForgeLoopTUI integration gate | `swift test --filter CapabilityEndToEndTests` | PASS / FAIL |
| 3 | ForgeLoopTUI public API smoke gate | `swift test --filter PublicAPISmokeTests` | PASS / FAIL |
| 4 | ForgeLoop build | `swift build` | PASS / FAIL |
| 5 | ForgeLoop screen-layout integration gate | `swift test --filter ScreenLayoutIntegrationTests` | PASS / FAIL |
| 6 | ForgeLoop performance baseline gate | `swift test --filter PerformanceBaselineTests` | PASS / FAIL |
| 7 | ForgeLoop performance regression gate | `swift test --filter PerformanceGateTests` | PASS / FAIL |

> 若有 FAIL，在对应行后附注失败测试名和错误摘要（≤2 行）。

---

## 3) Risk Classification

按以下四级分类，每级必须留一行结论（即使为 "None"）。

### Blocker

- 定义：导致发布不可用的缺陷，或无已批准例外的 `>10%` 性能回归。
- 记录格式：`- <问题简述> | 关联 issue/PR | 建议动作`

<!-- 样例：
- `ScreenLayoutIntegrationTests` 3/11 失败 | #42 | 阻塞发布，待修复后重跑 full gate
-->

### High

- 定义：不会立即阻塞发布，但需在发布后 48h 内跟进；或 `>5%` 且 `<=10%` 的 warn 级退化未解释。
- 记录格式同上。

### Medium

- 定义：已知限制、监控项、文档缺口；不影响当前发布，但需在下一里程碑处理。

### Low

- 定义：纯优化建议、输出格式改进、非用户可见的噪音。

---

## 4) Performance Snapshot Delta（若涉及发布）

对比本次 `PerformanceBaselineTests` 与上一版本基线：

| Metric | Previous p50 | Current p50 | Delta | Verdict |
|--------|-------------|-------------|-------|---------|
| render-small-first | 0.049 ms | | | pass / warn / fail |
| render-small-nochange | 0.049 ms | | | pass / warn / fail |
| render-small-partial | 0.052 ms | | | pass / warn / fail |
| render-medium-first | 0.350 ms | | | pass / warn / fail |
| render-medium-append | 0.358 ms | | | pass / warn / fail |
| render-medium-rapid-refresh | 0.345 ms | | | pass / warn / fail |
| render-large-first | 1.854 ms | | | pass / warn / fail |
| render-large-stream-append | 1.888 ms | | | pass / warn / fail |
| transcript-apply | 0.010 ms | | | pass / warn / fail |

> Verdict 规则见 `ForgeLoop/docs/perf-regression-policy.md`：
> - `<= 5%` → pass
> - `> 5%` 且 `<= 10%` → warn（需解释）
> - `> 10%` → fail（需修复或回滚，或已批准例外）

---

## 5) Rollback Point

- 若本次 drill **无代码变更**（纯验证）：回滚点为「上一次 green full gate 的 commit SHA」。
- 若本次 drill **包含代码变更**：回滚点为各仓库中可单独 revert 的 PR/ commit。
- 回滚命令示例：
  ```bash
  git revert < offending-commit >
  # 或
  git checkout < last-green-sha >
  ```

---

## 6) Release Decision

| 选项 | 勾选 |
|------|------|
| **GO** — full gate passes，无 blocker/high，可进入 tag & release 流程。 | [ ] |
| **NO-GO** — 存在 blocker 或未批准的 `>10%` 回归，必须先修复或取得例外批准。 | [ ] |
| **GO with watch** — 无 blocker，但存在 high/medium 项，需在发布后按约定时间跟进。 | [ ] |

决策理由（1-3 句）：

> 

---

## 7) Next Minimal Actions（最多 3 条）

1. 
2. 
3. 

> 原则：可执行、可验收、有负责人或截止日期。

---

## 附录：快速生成新报告（3 步）

1. **复制模板**：`cp docs/pre-release-drill-template.md docs/pre-release-drill-YYYY-MM-DD.md`
2. **填写 0) 基本信息** 和 **粘贴命令输出** 到 §2。
3. **按风险分级填写 §3–§7**，参考上一次报告样例保持口径一致。

---

## Related documents

- `docs/release-checklist.md` — 发布前完整检查单
- `docs/post-m7-maintenance-protocol.md` §7 — 性能退化处理 SOP
- `ForgeLoop/docs/perf-regression-policy.md` — 回归阈值与例外规则
- `ForgeLoop/docs/perf-baseline-snapshots.md` — 当前与历史基线
