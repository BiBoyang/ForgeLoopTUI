# 遗留清偿批计划（TASK-15 ~ TASK-20）

> 来源：`plans/PLAN-2026-08-phase1-debt.md` §5 评审遗留登记（根因证据逐条在案）；用户拍板：搁置 ForgeLoop App 层工作，先清遗留。
> 制定：2026-08-28 协作模式规划会话。执行：一次一个任务，逐任务提审，一任务一 commit。

## 1. Out of Scope

- 框架能力（布局系统 / 鼠标 / Alt screen 等）
- ForgeLoop App 侧任何改动（已搁置）
- 2.0 移除工作（含 `ListPickerRenderer`↔`ModalRenderer` 解耦，属 2.0 前置）
- RenderLoop 两个无害记录项维持不动：timer 取消后多跑一个周期（`RenderLoop.swift:69`）、stopped 后 `.immediate` 空转 flush

## 2. 通用 DoD（每任务适用，提审必附证据）

沿用 phase1 任务单 §2 全部六条：

1. `swift build && swift test` 全绿（本地实跑，结果附 Review Package）
2. 正确性修复必带新增回归测试
3. 涉公开 API 变更：同步 `docs/public-api-surface.md` + `CHANGELOG.md` [Unreleased]；公开 API 的用户可见行为修复同样要加 Fixed 条目
4. 文档示例实际编译验证（awk 抽取 + `swiftc -typecheck -I .build/debug/Modules`）
5. 改动范围清晰、无无关修改；一任务一 commit，用户手动提交
6. 新增或触碰到的公开 API doc comment 一律直接写英文

并发相关改动另附 `swift test --sanitize=thread --filter <套件>` 结果。

## 3. 任务单（6 项，建议按序）

### TASK-15 `emoji-width-table-refresh`
- 目标：`scalarIsWide` 区间表刷新到当前 Unicode 版本，覆盖 14/15/16 新区块。
- 证据：phase1 §5（TASK-01 遗留）——新 emoji（U+1FA70 起，如 🫠 U+1FAE0、🩷 U+1FA77）计宽 1 而非终端实际的 2。文件：`Sources/ForgeLoopTUI/ANSI/DisplayWidth.swift:113-212`。
- DoD：新区块测试钉住（🫠/🩷 等 = 2）；既有 DisplayWidthTests 13 例不回归。
- 风险：低（纯函数 + 测试）。

### TASK-16 `csi-zero-default-mapping`
- 目标：消费端兑现「0 = 默认值」契约。
- 证据：phase1 §5（TASK-03 遗留）——`VirtualTerminal` 运动命令（`A/B/C/D/G/L/M`，`Sources/ForgeLoopTUI/Terminal/VirtualTerminal.swift:168-186`）与 `KeyParser` 修饰符提取把 0 当字面值，`ESC[;A`/`ESC[0A` 变 no-op 而非默认 1。
- 前置注意：排查既有测试是否钉住 0 字面值行为，若有需逐条评估改测试的正当性并申报。
- DoD：0→默认映射 + 回归测试（显式 0 与空参两路）。

### TASK-17 `abort-late-blockend`
- 目标：abort 后迟到 `blockEnd` 不再把内容追加到 `[cancelled]` 之后。
- 证据：phase1 §5（TASK-04 遗留）——nil-active 宽松路径 `replaceStreaming` 对 nil range 末尾追加（`Sources/ForgeLoopTUI/Transcript/TranscriptRenderer.swift:235`）。
- **前置调查（第一交付物）**：nil-active 宽松路径的全部库内与测试消费面（含 legacy `"__legacy_block"` 用法），据此定收紧方案（候选：nil-active 且带 id 的 blockEnd 忽略；blockUpdate 隐式收养保留）。方案写入 Review Package 等批准后再动手——行为变更。
- DoD：方案经批准 + 回归测试 + CHANGELOG Fixed。

### TASK-18 `tui-dims-lock`
- 目标：`TUI.terminalWidth/terminalHeight` 读侧线程安全化。
- 证据：phase1 §5（TASK-05 遗留）——读侧无锁；直接给 getter 加 `lock` 会重入死锁（`shouldFallbackToFullRedraw` 等在 `lock.withLock` 闭包内读这些属性，已核实，见 `Sources/ForgeLoopTUI/Runtime/TUIRuntime.swift`）。
- **已批准方案（2026-08-29 评审门通过）：方案 A——专用叶子锁 `dimsLock` + computed getter**。存储改私有 `_terminalWidth/_terminalHeight`；公开只读 computed 属性各自 `dimsLock.withLock` 返回；锁序扩展为三级全序 `renderLock → lock → dimsLock`，`dimsLock` 为叶子锁（临界区内不取任何其他锁，doc comment 钉死此约定）；`updateTerminalSize` 在 `lock` 内嵌 `dimsLock` 写；init 直写存储。跨字段组合不保证同一快照（与现状一致，文档声明）。方案 B（getter 复用 `lock` + 热路径快照重构）已否决：回归风险高、快照时机难审计。
- DoD：TSan 复验 `TUIRuntimeConcurrencyTests` 全绿（含新增混合 lane 并发 resize 测试：resize lane + render lane + dims-read lane）；无重入；无 ABBA；既有全量测试不回归。
- 评审时必查两点：(a) `updateTerminalSize` 的 dimsLock 写作用域在物理行缓存重算（经 getter 再取 dimsLock）之前已闭合，不得跨着重算持锁；(b) 存储私有化后类型内全部 9 处读点必须经 computed getter（编译器强制）。
- 风险：全批最高，排最后代码项。

### TASK-19 `tui-default-istty-honest`
- 目标：`TUI` init 未传 `isTTY` 时默认真实探测，替代 `?? true`。
- 证据：phase1 §5（TASK-06 拍板留项）。
- DoD：复用 `StdoutTerminal.isTTY`（isatty）探测逻辑；CHANGELOG Fixed/Changed 条目（用户可见行为变更：pipe 中自动降级 plain，ForgeLoop 显式传值不受影响）。
- 风险：低。

### TASK-20 `testing-doc-suites`
- 目标：`TESTING.md` 补录新套件与 TSan 跑法。
- 证据：phase1 §5（TASK-10 遗留）——补 DisplayWidth / TUIRuntimeConcurrency / RenderLoop 三套件 + `swift test --sanitize=thread --filter` 用法。
- DoD：文档与现状一致（套件名、路径、命令实测过）。
- 风险：无。

## 4. 纪律与硬停止

- 一次一个任务；完成即停，输出 Review Package 等提审。
- 硬停止条件（命中任一即停并上报，不硬试、不回滚）：同一处修改超 3 次未过 / 需改动任务单之外文件 / 失败原因超出任务描述。
- 禁止任何 git 提交/推送/回滚；改动留工作区由用户手动提交。
- 任务单见 `plans/PLAN-2026-08-phase1-debt.md` §5 的遗留登记原文（含精确文件：行号证据）。
- 执行中发现（TASK-17 调查附带，已登记待立项）：`blockCancel` 存在同型 nil-active 宽松路径——迟到 cancel 会在后续内容之后追加 `[cancelled]`。TASK-17 只收紧 blockEnd，cancel 路径不动，后续单独立项。
- 渲染保真候选（TASK-21 dogfood 附带观察，非 bug）：引用块内嵌套代码围栏/嵌套表格按原文逐字降级显示；如需引用内嵌套结构解析，单独立项评估。

### TASK-22 `minimal-app-scrollback`（Example 层，不动库）
- 背景：TASK-21 修复消除了 erase 循环滚动副作用后，MinimalAIApp 的全屏原位重绘（`ScreenLayoutRenderer` + `tui.render(frame:)`）不再向 scrollback 泄漏内容，用户失去"往上滚动回看聊天记录"的能力（该能力原是 bug 副作用）。用户拍板走方案 a：改用库的原生 committed-append 范式。
- 目标：MinimalAIApp 的 transcript 区改为 committed-append 渲染——每条完成的 transcript 行只打印一次、自然流入 scrollback；live 区（输入框 + 状态行）保持原位重绘。
- 参照模式（库原生，勿自造）：`TranscriptRenderer`（CoreRenderEvent 块事件）+ `StreamingTranscriptAppendState.consume(transcript:activeRange:)` 取增量 → `tui.appendFrame(lines:)` 打印增量；live 区用 `tui.render(committed:live:…)`。ForgeLoop CLI（`CodingTUISession+Render.swift`）与 `docs/integration-guide.md` 是现成参照。
- 范围约束：**只动 `Examples/MinimalAIApp/`**。发现库侧缺口（如 API 不够用）立即停手上报，不改 `Sources/`。
- 保留行为：全部既有 keybindings（Enter 提交 / Esc 中断或清输入 / Ctrl-C 退出 / ↑↓ 历史 / ←→ 光标 / Home/End）；Esc 中断后 `[cancelled]` 语义；pipe 非交互回退（`echo "hello" | swift run`）；FauxAIProvider 无 key 回退。
- DoD：
  1. `swift build`（Example 目录）通过，无新警告（TASK-12 既有的 2 条库内 deprecation 警告除外）
  2. 人工验证脚本级描述 + 实测：流式结束后向上滚动可看到完整历史回复；多轮问答历史连续；Esc 中断正常；resize 不错位；pipe 模式输出无 ANSI
  3. 主仓 `swift build && swift test` 全绿（双框架计数）
  4. README/KEYS（Example 内）如有行为变化同步更新；无需主 CHANGELOG（Example 非发布物）
- 风险：appendFrame 与 render 混用的锚定算术是易错点——增量打印只发生在 committed 增长时，live 重绘锚定在所有已打印内容之后；提审时附多轮问答+resize 的实测录屏式文字记录。

## 5. 追加任务

### TASK-21 `streaming-markdown-garble`（调查优先）
- 背景：2026-08-29 用户 dogfood（MinimalAIApp + 真实 DeepSeek 流式）发现复杂 Markdown 流式渲染缺陷：代码块行乱序/重复、整行丢失（表头/首行/章节标题跳号）、异常空行。终态 scrollback 即坏，非流式瞬态。既有 49 Markdown + 40 Transcript 测试未覆盖。
- 嫌疑区（待证实，不预设结论）：(1) `MarkdownEngine.stableAdvance` retreat 逻辑（v1.2.1 刚修过 code fence retreat）；(2) `liveBudget: .physicalRows` 沉降与流式块行数变化交互（MinimalAIApp 开了最激进组合）；(3) TASK-01 宽度变更对 physicalRows 预算计算的波及面。
- 调查协议（三步，第一交付物）：
  1. **确定性复现**：把缺陷响应的原始 Markdown 存 fixture（用户可提供原文；拿不到就用等长复杂 fixture：多级标题/嵌套列表/多语言代码块/宽表格/任务列表/引用），测试内回放 `TranscriptRenderer`（blockStart → 累积 blockUpdate 序列 → blockEnd），断言最终 `transcriptLines` 与一次性静态渲染逐行一致。
  2. **三路二分**：(a) 一次性 blockEnd 全文（隔离静态渲染）；(b) 流式 + 关 liveBudget（隔离沉降）；(c) 流式 + liveBudget（现状缺陷路径）。确定缺陷落在哪条路径。
  3. **根因报告**：根因 + 证据（最小复现用例）+ 修复方案候选与取舍。
- **硬门**：根因报告与修复方案先入 Review Package 等批准，批准前禁止改 `Sources/` 下任何实现代码。调查过程中允许新增测试/fixture（失败的复现测试正是目标产出物），但不得修实现让它们通过。
- 修复阶段 DoD（批准后）：回归测试（复现用例转绿）+ CHANGELOG Fixed + 全量绿 + 现有套件零回归。
- 不在范围：MinimalAIApp 构建时的两条 deprecation 警告（TASK-12 已接受的已知项）。
