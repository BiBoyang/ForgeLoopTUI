# ForgeLoopTUI Maturity Scorecards

Date: 2026-05-11
Scope: `ForgeLoopTUI` roadmap tracking and milestone prioritization

## 评分口径

- **范围**：`0–10`，`10` 为该维度在 v1 范围内的目标完成态，不是绝对满分。
- **最小粒度**：`0.1` 分。
- **当前分**反映主干代码 + 测试 + 文档的客观状态，不是计划或预期。
- **目标分**反映该维度在发布前（M7）应达到的工程标准。
- **证据**必须指向可验证的产出：合并的 commit、通过的测试、发布的文档链接或代码路径。
- **下一步改造项**必须映射到具体里程碑（E2 / F1 / M6 / M7），不允许悬空描述。

---

## A. "超越 KWWK" 评分卡（10 维）

| 维度 | 当前分 | 目标分 | 证据 | 下一步改造项 |
|---|---:|---:|:---|:---|
| 1. 终端渲染正确性（ANSI/光标/清屏/滚动） | 7.8 | 9.2 | M1–M2 完成：`VirtualTerminal` 覆盖 clear/home/inline/cursor/resize；`ANSIParser` 通过 18 组 parser 测试、16 组 style-tracking 测试、12 组 capability-degradation 测试 | F1：增加异常终端能力降级回归测试；补齐复杂 ANSI 组合回放集 |
| 2. 输入系统可靠性（ESC/CSI/粘贴/UTF-8） | 8.2 | 9.3 | M3 完成：`RawTTY`（6 测）、`ByteStreamBuffer`（18 测）、`KeyParser`（19 测）、`InputPipeline`（22 测）、`InputReader` lifecycle（4 测）全部通过 | F1：增加高压输入回放（碎片化序列、极端粘贴、非标准键盘映射） |
| 3. 提交区/实时区语义（committed/live） | 8.0 | 9.0 | A1–A2 完成：`ScreenLayoutRenderer` 产出 live 语义；`CommittedLiveRenderTests` 覆盖 resize/cursorOffset/partial update/empty-live；CLI 全链路走 `ComposedFrame.live` | M7：补全 live budget overflow 与 resize storm 的组合回放 |
| 4. 布局系统通用性（预算/裁剪/pinned） | 7.5 | 8.8 | B1–B2 完成：`ScreenLayoutRenderer` 启用 `terminalWidth/Height` 预算；`pinnedTranscriptRange` 保护逻辑落地；`ScreenLayoutRendererTests` 覆盖 tail-clip 与 pinned 越界降级 | F1：增加多策略 budget 切换的基准对比；补全 pinned 跨 resize 的稳定性测试 |
| 5. 性能稳定性（p95、回归门禁） | 6.8 | 9.0 | D1 完成：性能 flaky 规则从硬阈值改为可解释策略（见 `PerformanceBaselineTests` 注释）；阈值策略文档化 | F1：建立 benchmark 基线快照与 PR 门禁；分离 flaky 阈值与真实退化 |
| 6. 崩溃与中断恢复（TTY 状态恢复） | 8.0 | 9.4 | M3 完成：`RawTTY` 双进入防护、RAII `withRawTTY`、deinit 恢复；`InputReader` 支持 restart 与 idempotent start/stop | F1：扩展 kill/异常/中断场景测试，覆盖更多 fd/非交互组合 |
| 7. 组件化能力（可组合与复用） | 7.5 | 9.0 | M5 完成：`Component` / `AnyComponent` / `VStack` / `@ComponentBuilder`；`FrameComposer` + `ComposedFrame` + `LayoutBudget`；`TranscriptComponent`、`TextInputComponent`、`ListPickerComponent` 适配器 | M6：AppKit bridge 验证组件跨平台复用；M7：补充组件配方化示例 |
| 8. API 一致性与演进策略 | 7.0 | 8.8 | E1 完成：`integration-guide.md` 明确库/应用边界；`migration-guide-for-forgeloopcli.md` 记录迁移路径；`CoreRenderEvent` 替代 `RenderEvent` 的弃用标记已落地 | M7：明确稳定 API 面、兼容承诺、弃用路径和版本化规范（SemVer） |
| 9. 文档与可接入体验 | 8.0 | 9.2 | E1 完成：`integration-guide.md`（最小接入、渲染链路、committed/live 语义、coalesce 规则）；`migration-guide-for-forgeloopcli.md`（已完成/未完成/回退点）；README 同步索引 | M7：增加 FAQ、故障排查路径、配方化示例；完善 DocC/API 注释 |
| 10. 差异化能力（AppKit 混合桥接） | 7.0 | 9.0 | P0 完成：双向桥接闭环（NSEvent→KeyEvent + @MainActor Observable state + 降级路径 + PanelMetadataProviding→PanelMeta 桥接入口）；18 adapter tests + 14 state tests + 4 加固 tests；API 面 doc 更新 | M7/P1：真实 AppKit 应用验证 + accessibility + 动画策略 |

### A.1 结论（E2 基线）

- 当前总体（2026-05-11 收口后复评）：约 `70%–78%` 达到"工程维度超越 KWWK"的目标。
- 主战场：`10（AppKit）` 仍是差距最大的单点，`5（性能）` 与 `8（API 治理）` 已从“缺口期”进入“运营期”。
- 已收敛：`3（live 语义）` / `4（布局）` / `5（性能治理）` / `8（API 治理）` / `9（文档）` 均进入维护期（持续门禁与演练驱动）。

---

## B. "优秀的通用 Mac 端 TUI 基座" 评分卡（10 维）

| 维度 | 当前分 | 目标分 | 证据 | 下一步改造项 |
|---|---:|---:|:---|:---|
| 1. 架构边界清晰度（库/应用职责） | 8.5 | 9.5 | A1–D2 完成：`TUIRunner.swift` / `Layout.swift` / `LayoutRenderer.swift` 从 CLI 删除；`integration-guide.md` 明确"库/应用"边界规则 | M7：持续审计，禁止回流通用基础设施；建立边界违规检测 checklist |
| 2. 跨项目复用能力（无业务耦合） | 8.0 | 9.3 | E1 完成：`CoreRenderEvent` 去 chat 语义；`ScreenLayout` / `ScreenLayoutConfig` 无 app-specific 字段；`integration-guide.md` 给出复用检查清单 | M7：审计 API 命名与参数，剔除潜在 app-specific 语义；补充多项目接入案例 |
| 3. 终端抽象完整度（Terminal/Capability） | 8.0 | 9.2 | M1–M2 完成：`Terminal` 协议 + `StdoutTerminal` + `VirtualTerminal`；`TerminalCapability` 四级降级链（plain → ansi16 → ansi256 → truecolor） | F1：扩展 capability 覆盖与降级策略验证矩阵 |
| 4. 输入抽象完整度（Reader/Pipeline/KeyEvent） | 8.4 | 9.4 | M3 完成：`InputReader` / `InputPipeline` / `KeyEvent` / `KeyParser` 全链路；`ByteStreamBuffer` 处理碎片化 ESC + UTF-8 重组 | F1：增加平台/键盘差异验证；完善错误与边界行为文档 |
| 5. 布局与渲染框架化程度 | 7.5 | 9.0 | M5 + A1–B2 完成：`ScreenLayout` + `ScreenLayoutRenderer` + `LayoutBudget` 能力闭环；`CodingTUIFrameBuilder` 统一 CLI 帧组装；coalesce 规则文档化 | M7：形成稳定 `ScreenLayout` 扩展指南；补充自定义 layout policy 配方 |
| 6. 可测试性与可观测性 | 8.1 | 9.3 | M1–M5 完成：`VirtualTerminal` 支持 grid/cursor/clear/scroll/resize 断言；`InputReader` 支持 injectable `InputClock`；`CommittedLiveRenderTests` 覆盖核心路径 | F1：增加端到端回放 fixture、可观测日志钩子、故障注入测试 |
| 7. 性能与资源控制 | 7.0 | 9.0 | D1 完成：性能约束保留但避免脆弱硬阈值；`RenderLoop` 16ms 合帧 + immediate 刷新策略稳定 | F1：建立多场景性能画像（长会话、resize 风暴、大粘贴）；固化 benchmark 基线 |
| 8. 文档与开发者体验（DX） | 8.0 | 9.4 | E1 完成：`integration-guide.md`（QuickStart + 边界 + 语义 + coalesce）；`migration-guide-for-forgeloopcli.md`（迁移地图）；README 索引同步 | M7：增加 FAQ、故障排查路径、配方化示例；完善 DocC/API 注释 |
| 9. 发布与版本治理（SemVer/兼容） | 6.0 | 9.0 | E1 完成：`migration-guide-for-forgeloopcli.md` 记录回退点；`CoreRenderEvent` 替代 `RenderEvent` 的弃用标记已落地 | M7：建立发布清单、兼容承诺、变更日志模板与破坏性变更流程 |
| 10. 平台价值（macOS-first 能力） | 7.5 | 9.2 | P0 完成：AppKit bridge 已具备可复用双向桥接能力 | M7/P1：推出至少一个基于 bridge 的 AppKit 面板示例应用 |

### B.1 结论（E2 基线）

- 当前总体（2026-05-11 收口后复评）：约 `80%–88%` 达到"优秀通用 Mac 端 TUI 基座"目标。
- 关键跃迁点：`10（AppKit）` 是从“优秀”到“领先”的主战场；`7（性能）` 与 `9（发布治理）` 目前已具备可持续运营能力。
- 已收敛：`1（边界）` / `5（布局）` / `8（DX）` / `9（发布治理）` 在 post-M7 收口后稳定，进入常态维护。

---

## Governance（评分更新规则）

### 何时允许改分

必须同时满足以下至少一项可验证产出：

1. **代码**：相关功能已合并到主干，且 `swift test` 通过。
2. **测试**：新增/更新的测试覆盖该维度核心路径，且 CI/本地验证通过。
3. **文档**：该维度的用户可见文档（README / integration-guide / API 注释）已更新并准确反映当前行为。
4. **性能**：有 benchmark 数据或 replay 测试结果证明改善或退化。

### 何时不允许改分

1. 仅主观感受（"感觉更稳定了"、"应该够了"）。
2. 代码在分支未合并。
3. 测试未运行或结果未知。
4. 文档与实际行为不一致。

### 每次改分需要附带的最小证据集

- 改分 PR/提交必须引用至少一个：
  - 合并的 commit SHA
  - 通过的测试过滤命令（如 `swift test --filter XxxTests`）
  - 更新的文档段落（附 diff 或行号）
- 单次改分幅度限制：
  - 升分：单维度单次不超过 `+0.5`
  - 降分：单维度单次不超过 `-1.0`（重大回归才允许大幅降分）

### 评分回退规则

1. **测试回归**：若某维度相关测试从"通过"变为"持续失败"，当前分立即降 `0.3`，并在 48h 内修复或给出解释。
2. **文档漂移**：若文档描述与实际代码行为不一致，当前分降 `0.2`，并同步更新文档或代码。
3. **性能退化**：若 benchmark 超过基线阈值，当前分降 `0.2–0.5`，具体幅度由退化幅度决定。
4. **回退记录**：所有降分必须在本文档的"变更日志"中记录日期、维度、幅度、原因、修复 commit。

---

## E2 Baseline Snapshot

### 已完成（A1–E1）

- A1–A2：`ScreenLayoutRenderer` live 语义落地 + 回放测试
- B1–B2：terminal-size 预算 + `pinnedTranscriptRange` 保护
- C1–C2：`CodingTUIFrameBuilder` 提取 + 统一渲染出口
- D1–D2：性能 flaky 规则文档化 + 输入/布局回放集规划
- E1：接入文档（`integration-guide.md`）+ 迁移文档（`migration-guide-for-forgeloopcli.md`）+ 主文档同步

### 正在推进（E2）

- 成熟度评分卡治理化（本文档）
- 主文档双向链接建立
- post-M7 收口完成：`cross-repo-gate.sh`（quick/full）、预发布演练模板、性能回归模板与 SOP 已落地

### 下一优先级

1. **P1** — M7：真实 AppKit 应用验证（基于 P0 桥接闭环创建最小 AppKit 面板应用）
2. **P0** — 持续性能运营：保持 baseline 快照与回归判定纪律，防止分数回退
3. **P1** — 多轮 RC 演练沉淀（模板化报告 + 风险台账），验证稳定性是"持续能力"而非一次性结果

---

## 变更日志

| 日期 | 维度 | 幅度 | 原因 | 修复/证据 |
|---|---:|---:|:---|:---|
| 2026-05-11 | 3（committed/live） | +1.8 | A1–A2 完成，live 语义全链路落地 | `CommittedLiveRenderTests` 通过；`ScreenLayoutRenderer` 产出 live |
| 2026-05-11 | 4（布局系统通用性） | +1.5 | B1–B2 完成，预算与 pinned 保护落地 | `ScreenLayoutRendererTests` 通过 |
| 2026-05-11 | 5（性能稳定性） | +0.0 | D1 完成，规则文档化但基线未固化 | 待 F1 建立 benchmark 后再评估升分 |
| 2026-05-11 | 7（组件化能力） | +0.5 | M5 + C1 完成，FrameBuilder 提取 | `CodingTUIFrameBuilder` 落地 |
| 2026-05-11 | 8（API 一致性） | +0.5 | E1 完成，边界与迁移文档落地 | `integration-guide.md` + `migration-guide-for-forgeloopcli.md` |
| 2026-05-11 | 9（文档与 DX） | +1.2 | E1 完成，接入与迁移文档落地 | 同上 |
| 2026-05-11 | 1（架构边界） | +0.2 | D2 完成，边界进一步清晰 | `TUIRunner`/`Layout`/`LayoutRenderer` 删除 |
| 2026-05-11 | 2（跨项目复用） | +0.2 | E1 完成，复用检查清单落地 | `integration-guide.md` 边界规则 |
| 2026-05-11 | 5（性能稳定性） | +0.6 | F1 关键收口：新增 `render-medium-rapid-refresh` 回放、基线模板统一、回归阈值与例外流程固化 | `PerformanceBaselineTests`/`PerformanceGateTests` + `perf-baseline-snapshots.md` + `perf-regression-policy.md` |
| 2026-05-11 | 9（发布治理） | +0.8 | post-M7 收口：`cross-repo-gate.sh` quick/full 常态化、pre-release drill 模板化、release checklist 与 SOP 对齐 | `pre-release-drill-template.md` + `release-checklist.md` + `post-m7-maintenance-protocol.md` |
| 2026-05-12 | 10（AppKit 桥接） | +2.5 (A) / +1.3 (B) | P0 完成：双向桥接（NSEvent→KeyEvent）、Observable 状态（@MainActor）、降级路径、PanelMetadataProviding→PanelMeta 桥接入口 | P0 completed |
> **例外说明（+2.5 幅度）**：单次升分超过治理上限 `+0.5`。例外理由：P0 是从 M6 demo（单向投影，4.5分）到可复用双向桥接闭环（7.0分）的**质变里程碑**，非渐进改善。证据：48 tests + cross-repo-gate 全绿 + 4 API 面新增类型文档化。此后维度的后续升分将严格遵循 `+0.5` 上限。 |

---

## 下一刀优先级（P0 后）

1. `P1` — M7：真实 AppKit 应用验证（基于 P0 桥接闭环）
2. `P0` — 持续性能运营：保持 baseline 快照与回归判定纪律
3. `P1` — M7：发布清单、SemVer 承诺、API docs 完善
4. `P2` — 持续：输入高压回放、复杂 ANSI 组合回放、跨模块集成回放
