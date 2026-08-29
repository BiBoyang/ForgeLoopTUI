# 第一期计划：修地基 + 门面（纯还债）

> 来源：`notes/audit-2026-08-28.md`（唯一事实来源，条目引用即根因证据）
> 制定：2026-08-28 协作模式规划会话；执行：执行会话按本单逐项推进，一次一个任务，逐任务提审。
> 定位：不动公开 API 形状，semver 友好（patch/minor）。

## 0. 战略拍板记录（2026-08-28 用户已决策）

| 项 | 决策 | 本期动作 |
|----|------|---------|
| Linux 支持 | 删除假分支，明确 macOS-only | TASK-11 |
| Bridge 拆分 | 方向确认：核心库 + AppKit 附加 target，后续单独立项 | 本期仅 TASK-10 文档澄清名实 |
| 组件树路线 | 软着陆退出：标 deprecated + 文档声明未验证，2.0 移除 | TASK-12 |
| 注释语言 | 公开 API doc comment 全英文；内部实现注释不限 | TASK-13 |

## 1. Out of Scope（本期不做）

- Bridge 实际拆分（仅文档澄清）
- P3 倒挂的 ForgeLoop App 侧清理（属第二期；TASK-08 仅做库侧公开）
- P2 其余补测：SGRState、LogicalLines、快照 golden、性能测试 CI 断言
- P4 框架能力（布局/resize/鼠标/alt screen 等，逐项立项再谈）
- 组件树实际移除（留 2.0）
- `Terminal.write` 改 throws（API 形状变更；本期仅写入 docs 已知限制）

## 2. 通用 DoD（每任务适用，提审必附证据）

1. `swift build && swift test` 全绿（本地实跑，结果附 Review Package）
2. 正确性修复必带新增回归测试
3. 涉公开 API 变更：同步 `docs/public-api-surface.md` + `CHANGELOG.md` [Unreleased]；公开 API 的用户可见行为修复（bug fix）同样要加 [Unreleased] Fixed 条目
4. 文档示例实际编译验证，非目测
5. 改动范围清晰、无无关修改；一任务一 commit，用户手动提交
6. 新增或触碰到的公开 API doc comment 一律直接写英文（不待 TASK-13 统一迁移，避免返工）

## 3. 评审标准（Review Gate）

- 正确性修复无回归测试 → Changes Requested
- 公开 API 变更未同步 surface 文档 / CHANGELOG → Changes Requested
- README/文档示例不可编译 → Changes Requested
- 结论只出 `Approved` / `Changes Requested`，findings 按 Blocker / Major / Minor 分级

## 4. 任务单（14 项，建议按序）

### TASK-01 `display-width-grapheme`
- 目标：宽度计算改按 grapheme cluster（EWC）计宽。
- 证据：P0-1（`Sources/ForgeLoopTUI/ANSI/DisplayWidth.swift:34-45`；第二份错误 `Sources/ForgeLoopTUI/Components/MultiLineInputState.swift:451-482` 的 `characterVisibleWidth` 必须同步修；依赖点 `Sources/ForgeLoopTUI/Runtime/TUIRuntime.swift:298-301,330-332`、`MultiLineInputState.swift:160-171`）；P2-1 全库零覆盖。
- 范围：ZWJ 序列 = 2、肤色修饰符合并、VS16 处理、组合附加符（Mn/Me）= 0、国旗 RI 对 = 2。
- 决策点：不引入第三方依赖，基于 `Character` 迭代 + Unicode 属性表实现。
- DoD：新增 DisplayWidthTests 覆盖 ZWJ/肤色/VS16/组合符/国旗/CJK/纯 ASCII；README "CJK / emoji safe cursor positioning" 宣称由假变真。
- 风险：宽度规则与真实终端渲染存在终端间差异——以 Unicode 语义为准；纯函数替换，revert 即回滚。

### TASK-02 `transcript-consume-clamp`
- 目标：`StreamingTranscriptAppendState.consume` 双端 clamp。
- 证据：P0-4（`Sources/ForgeLoopTUI/Transcript/StreamingTranscriptAppendState.swift:25`，仅 clamp lowerBound）。
- DoD：upperBound 超界不 crash 的回归测试。最小任务。

### TASK-03 `csi-empty-param`
- 目标：CSI 空参数保留默认值语义；两文件分隔符规则统一。
- 证据：P0-5（`Sources/ForgeLoopTUI/ANSI/ANSIParser.swift:123-125`、`Sources/ForgeLoopTUI/Input/ByteStreamBuffer.swift:172-175`；`compactMap { Int($0) }` 丢首参默认值 1；一个认 `:` 一个不认）。
- DoD：空参 / `:` / `;` 三 case 两文件行为一致的回归测试。

### TASK-04 `transcript-block-id`
- 目标：`CoreRenderEvent` 的 block `id` 语义：兑现多 block 或收窄 API。
- 证据：P0-3（`Sources/ForgeLoopTUI/Transcript/TranscriptRenderer.swift:67-96`，单一 streamingRange 互相覆盖）。
- 前置：**先调查 ForgeLoop 使用点**是否存在多 block 并发场景；无则收窄 + 文档声明，有则按 id 兑现。调查结论作为本任务第一交付物，结论入 Review Package。
- DoD：两 block 交替事件不串态的测试（或收窄后的误用防护 + 文档）。

### TASK-05 `tui-sendable-audit`
- 目标：`TUI` 的 `@unchecked Sendable` 名实相符。
- 证据：P0-2（`Sources/ForgeLoopTUI/Runtime/TUIRuntime.swift:591-735`，锁内换状态锁外写 :664/:735；`diagnosticsHandler` :54 无锁 public var）。
- 前置：**先调查 ForgeLoop 调用线程模型**再定方向（锁全覆盖 vs 收窄 Sendable 声明）。
- DoD：data race 消除 + 并发 render 回归测试（多线程压力或 TSan）。
- 风险：全期最高风险点——锁内 IO 阻塞/死锁；评审逐行核对锁内操作。

### TASK-06 `p0-minor-batch`
- 目标：P0 次要项打包。
- 证据：P0 末段——force unwrap/precondition（`Sources/ForgeLoopTUI/Input/KeyParser.swift:62,77,98`、`Sources/ForgeLoopTUI/Bridge/AppKitEventAdapter.swift:168`、`Sources/ForgeLoopTUI/Components/Frame.swift:157,170`）；`Sources/ForgeLoopTUI/Terminal/StdoutTerminal.swift:43-44` isTTY/capability 谎报；写失败静默（`StdoutTerminal.swift:36`、`Sources/ForgeLoopTUI/Terminal/RawTTY.swift:80`）。
- 范围：force unwrap 逐个改安全失败路径；isTTY/capability 诚实探测；写失败在不改签名内尽量上报（如诊断回调）。
- 不做：`Terminal.write` 改 throws——仅写入 docs 已知限制。
- DoD：列出点位逐个处理 + 测试；已知限制落文档。

### TASK-07 `renderloop-tests`
- 目标：RenderLoop 补测。
- 证据：P2-2（`Sources/ForgeLoopTUI/Runtime/RenderLoop.swift` 121 行并发组件零测试，ForgeLoop 实际在用）。
- 范围：submit/flush/stop 生命周期、合帧行为、竞态压力。
- 纪律：**只加测试不修实现**；测试暴露 bug 则记录并升级给用户，不顺手修。

### TASK-08 `expose-width-api`
- 目标：`visibleWidth`/`ansiStripped` 转 public。
- 证据：P1-6（`DisplayWidth.swift:3,32` internal；ForgeLoop 手写同款剥离器 `ForgeLoop/Sources/ForgeLoopApp/AppController+Rendering.swift:201-228`——App 侧删除属第二期）。
- 依赖：TASK-01 完成后做（公开的是修好的实现）。
- DoD：英文 doc comment + `docs/public-api-surface.md` 新增条目 + CHANGELOG [Unreleased] Added。

### TASK-09 `readme-fix`
- 目标：README 门面修复。
- 证据：P1-1（`README.md:90-109` Quick Start 缺 `thinking:` 参数且整段用 deprecated API）；P1-2（L255-264 Event Model 通篇弃用 API；L132 弃用 API 列为 stable，与 `docs/public-api-surface.md` 矛盾）；`README.md:78` 版本号 1.2.0→1.2.1。
- DoD：Quick Start 代码段拷出实际编译通过；Event Model 重写为 CoreRenderEvent 九事件；stable 列表与 surface 文档一致。

### TASK-10 `docs-fix-batch`
- 目标：docs/ 打包修复 + Bridge 名实澄清 + README 残余 fence 修复（TASK-09 评审并入）。
- 证据：P1-3（`docs/integration-guide.md` §5 L168-174 示例不编译）；P1-4（`TESTING.md` 路径过期；`docs/markdown-table-rendering.md` 停更）；P1-5（`docs/public-api-surface.md` RenderLoop.submit、StreamingMarkdownEngine.render 两处签名错误）。TASK-09 评审发现：README fence4（Customizing Wide Tables 第一段）缺 `@MainActor` 上下文不可独立编译、fence5 为无 import 接续片段。
- 附加：Bridge 文档澄清一段（实为双投影数据模型 + NSEvent 适配器；未来拆分为核心库 + AppKit 附加 target）。
- README fence 修法：fence4 包 `@MainActor` 上下文（参照 Quick Start 的 `demo()` 写法）；fence5 与 fence4 合并为单一代码段，或显式标注为接续片段（标注后豁免独立编译探测，但合并后必须过同一 awk+swiftc 探测）。
- 依赖：TASK-08（surface 文档一次改到位）。
- DoD：示例编译验证（README 各 fence 用 awk 抽取 + `swiftc -typecheck -I .build/debug/Modules` 实测）；签名与源码逐条一致。

### TASK-11 `drop-glibc-branches`
- 目标：删 8 处 `#if canImport(Glibc)` 假分支；README 加支持矩阵（macOS 14+）。
- 依据：拍板 Q1。证据：§7-1（`Sources/ForgeLoopTUI/Terminal/StdoutTerminal.swift:20` 写死 Darwin.write、Bridge 无条件 import AppKit，Linux 实际不可构建）。
- DoD：grep `canImport(Glibc)` 零残留；build && test 绿。

### TASK-12 `component-tree-deprecate`
- 目标：声明式组件树公开 API 标 deprecated + 文档声明未验证。
- 依据：拍板 Q3 软着陆第一步。证据：P4-5 / §5 零真实消费（VStack/@ComponentBuilder/FrameComposer/ModalHost 仅自带 Example 使用）。
- DoD：`@available(*, deprecated, message:…)` 标注；自带 Example 编译无新 error（警告可接受）；CHANGELOG [Unreleased] Deprecated 节；surface 文档标注。

### TASK-13 `doc-comments-en`
- 目标：公开 API doc comment 全英文；规矩写入 `CONTRIBUTING.md`（公开 API 注释英文，内部实现注释不限）。
- 依据：拍板 Q4。证据：P1-7（如 `CursorPositioningMode` 整段中文）。
- 排序说明：故意排最后，避免与前面任务在同文件反复冲突。
- DoD：公开 API 注释无中文残留；CONTRIBUTING.md 规矩落地。

### TASK-14 `ci-examples-gate`
- 目标：CI 加 Examples 编译门禁（4 个 SPM 包逐个 `swift build`）。
- 证据：P2-4（`.github/workflows/ci.yml` 仅 macos-15 build+test；Examples 不进 CI 是 P1 腐烂直接原因）。
- 依赖：TASK-09/12 完成后 Examples 干净编译。
- 不做：性能测试 CI 自我跳过（CI=true 不断言）问题仅记录，列后续任务。
- DoD：CI 绿。

## 5. 全局风险与纪律

- TASK-04/05 的 ForgeLoop 使用点调查结论若推翻假设：先回本会话更新计划再动手（协议 §7 需求漂移）。
- 每任务单独 commit，回滚 = revert 单 commit。
- 提审前置门槛：基础校验结果必须附在 Review Package，未附直接退回（WORKFLOW §4.5）。
- 硬停止条件（执行会话）：同一处修改超 3 次未过 / 需改动任务清单外文件 / 失败原因超出任务描述 → 停并上报，不硬试不回滚。
- 评审遗留（TASK-01）：`scalarIsWide` 区间表定格在旧版 Unicode，新 emoji（U+1FA70 起的 Unicode 14/15/16 区块）计宽 1 而非 2——记录为已知限制候选，后续单开任务刷新区间表并补测试钉住。
- 评审遗留（TASK-03）：`parseCSIParameters` 的「0 = 默认值」契约在消费端未兑现——VirtualTerminal 运动命令（`A/B/C/D/G/L/M`）与 KeyParser 把 0 当字面值（`ESC[;A`/`ESC[0A` 变 no-op 而非默认 1）。显式 0 场景修复前已存在，空参新语义使其更易到达；后续单开任务在消费端补 0→默认值映射并加测试。
- 评审遗留（TASK-04）：ForgeLoop abort 路径的迟到 `blockEnd("__assistant")` 仍会经 nil-active 宽松路径（`replaceStreaming` 对 nil range 末尾追加，`TranscriptRenderer.swift:235`）把最终内容追加到 `[cancelled]` 之后——本任务未修（声明失实已纠正）。候选解法：(a) 库侧对 nil-active 的带 id blockEnd 收紧（行为变更，需拍板）；(b) ForgeLoop 侧 abort 后抑制迟到事件。属后续任务候选。
- 评审遗留（TASK-05）：`TUI.terminalWidth/terminalHeight` 读侧无锁（`public private(set)` 直读 vs `updateTerminalSize` 锁内写）。Int 直读无撕裂风险、仅可能读到旧值；直接改锁保护 getter 会造成 NSLock 重入死锁（`shouldFallbackToFullRedraw` 等在 `lock.withLock` 闭包内读这些属性，已核实），需配合重构。登记后续候选，本期不动。
- 评审遗留（TASK-06 拍板）：`TUI` init 未传 `isTTY` 时默认分支仍 `?? true`——本期不动。理由：审计未点名；改默认值是用户可见行为变更（pipe 中自动降级 plain）；ForgeLoop 显式传值不受影响。若日后改，配 release note 单独立项。
- 评审记录（TASK-07，仅记录不动作）：(a) `RenderLoop` 的 render 回调在锁外执行（`RenderLoop.swift:93,104`），多线程 `.immediate` 可并发进入——拍板：库侧文档声明契约即可（随 TASK-07 提交补英文类注释），实现串行化属行为变更不单独立项；TUI 消费方已被 renderLock 保护。(b) `try? await Task.sleep` 吞取消导致 timer 多跑一个周期（:69）——现状无害，记录。(c) stopped 后 `.immediate` 空转一次 flush——无害，记录。
- 评审遗留（TASK-10）：(a) **TASK-12 注意**：integration-guide §5 新示例使用 `TranscriptComponent`/`TextInputComponent`（组件树家族），TASK-12 标 deprecated 时本节需同步加 deprecation 指向。(b) TESTING.md 可补录新套件（DisplayWidth/TUIRuntimeConcurrency/RenderLoop + TSan 跑法）——扩写候选，本期未做。
- 评审遗留（TASK-12）：**2.0 移除组件树的前置依赖**——`ListPickerRenderer`（Stable，ForgeLoop CLI 真实消费）在 `ListPicker.swift:88/93` 内嵌 `ModalRenderer`（已弃用）。2.0 移除前必须先解耦（内联 modal 渲染或迁移实现），否则 Stable 类型随弃用族一起死。本期接受 3 处同模块弃用警告（行为不变）。另：审计"组件树仅自带 Example 使用"表述已过时——现状 Examples 零引用，仅 Tests 引用（已核实）。
