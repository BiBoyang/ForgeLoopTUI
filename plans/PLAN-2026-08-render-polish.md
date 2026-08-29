# 渲染观感提升计划（TASK-23 ~ TASK-31）

> 来源：2026-08-29 观感评审会话（四个短板经用户确认：块级元素太素 / 代码块无语法高亮 / HTML+LaTeX 裸奔 / 流式整块弹出）。
> 前置修复已入库：`432ebd2`（stable-prefix 提交契约，本计划所有渲染改动的硬约束）。
> 制定：2026-08-29 协作模式规划会话。执行：一次一个任务，逐任务提审，一任务一 commit，用户手动提交。
> 路径约定：仓库根 = `/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI`，下文路径均相对仓库根。

## 0. 战略拍板记录（2026-08-29 用户已决策）

| 项 | 决策 |
|----|------|
| theme 默认值 | **默认开启**；`.none` 纯文本主题兜底旧字节流，`PlainTextMarkdownEngine` 不受影响 |
| 分期顺序 | 一期样式+HTML/LaTeX（TASK-23~26）→ 二期流式预览（TASK-27~29）→ 三期语法高亮（TASK-30~31），逐期独立 commit |
| LaTeX 边界 | 只做常见宏近似（希腊字母/运算符/上下标/`\sqrt`/简单 `\frac`）；`\begin{...}` 环境保持 raw，不上大件 |
| 语法高亮 | 先只做 **Python + JavaScript** 两种语言验证效果，不引第三方依赖（自研小型 tokenizer） |
| HTML 单元格分隔（2026-08-29 TASK-25 评审追加） | `th`/`td` 降级为空格分隔（不换行）——"挤比松难读"，用户拍板要 |

## 0.1 硬约束（贯穿全部任务）

- **stable-prefix 提交契约不可破坏**：渲染必须是输入文本的确定函数——禁止引入"同一文本前后渲染不同"的全局/时序状态（theme 走 options 注入，不走单例）。
- `Tests/ForgeLoopTUITests/Transcript/StreamingStableCommitTests.swift`、`Tests/ForgeLoopTUITests/Transcript/StreamingTranscriptAppendStateTests.swift` 任何一期后都必须全绿。
- `StreamingMarkdownEngine` 是 Stable API：渲染输出样式变化走 MINOR + CHANGELOG；`.none` 主题保持旧字节流可回退。

## 1. Out of Scope（本计划不做）

- tree-sitter / Splash 等第三方高亮引擎
- HTML `<table>` 转 box-drawing、LaTeX 环境块（matrix/cases）排版、Mermaid 图形化
- 嵌套同级 fence 的容错启发式（偏离 CommonMark，单独立项再谈）
- ForgeLoop App 侧任何改动
- 更多高亮语言（验证效果后另行追加）

## 2. 通用 DoD（每任务适用，提审必附证据）

1. `swift build && swift test` 全绿（本地实跑，结果附 Review Package）
2. 新行为必带新增测试；渲染契约相关必跑 `swift test --filter StreamingStableCommitTests`
3. 涉公开 API 变更：同步 `docs/public-api-surface.md` + `CHANGELOG.md` [Unreleased]（样式新增走 Added；公开 API doc comment 写英文）
4. `Examples/MarkdownShowcase` / `Examples/MinimalAIApp` 可编译，`Examples/MinimalAIApp/pty_smoke.py` 通过
5. 改动范围清晰、无无关修改；一任务一 commit，用户手动提交
6. 人工检查点：`MarkdownShowcase full` 与 `/demo full` 目测（提审附终端截图或字节流片段）

## 3. 评审标准（Review Gate）

- 渲染确定性被引入隐藏状态（单例/全局样式/时间依赖）→ Changes Requested
- 稳定提交契约回归（StreamingStableCommitTests 红）→ Changes Requested
- 公开 API 变更未同步 surface 文档 / CHANGELOG → Changes Requested
- ANSI 截断切断转义序列（样式泄漏到后续输出）→ Changes Requested
- 结论只出 `Approved` / `Changes Requested`，findings 按 Blocker / Major / Minor 分级

## 4. 任务单（9 项，建议按序）

### TASK-23 `markdown-theme-scaffold`
- 目标：`MarkdownTheme` 值类型 + `MarkdownRenderOptions.theme`（默认开启），`.none` 返回当前纯文本字节流。本任务只立骨架，引擎渲染暂不接色。
- 涉及文件：
  - 新增 `Sources/ForgeLoopTUI/Markdown/MarkdownTheme.swift`（SGR 常量 + 主题结构：标题各级/表头/表格边框/引用线/fence 边框/fence 语言标签/任务清单符号 + code 高亮四槽（keyword/string/comment/number，TASK-30/31 的上游槽位）；公开 API doc comment 全英文）
  - 修改 `Sources/ForgeLoopTUI/Markdown/MarkdownRenderOptions.swift`（加 `theme` 字段，默认 `.default`）
  - 新增 `Tests/ForgeLoopTUITests/Markdown/MarkdownThemeTests.swift`
  - 文档：`docs/public-api-surface.md`、`CHANGELOG.md`
- DoD：`MarkdownRenderOptions()` 默认含 theme；`.none` 主题下引擎输出与现状逐字节一致（用现有 `Tests/ForgeLoopTUITests/Markdown/MarkdownEngineTests.swift` golden 反向钉住）；全量测试绿。
- 风险：无渲染接线，纯结构任务；revert 即回滚。

### TASK-24 `block-element-styling`
- 目标：标题/表格/引用/fence 边框接 theme 上色。
- 涉及文件：
  - 修改 `Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift`：
    - `renderHeading`（L515）——各级标题色+粗体
    - `renderTable`（L781）——边框 dim、表头行粗体
    - `renderStructuredLine` 的 blockquote 分支（L467，引用线 `│` 上色）
    - `renderCodeFenceStart`/`renderCodeFenceEnd`（L610/L616，边框+语言标签 dim）
  - 新增 `Tests/ForgeLoopTUITests/Markdown/BlockElementStylingTests.swift`
  - 文档：`docs/public-api-surface.md`、`CHANGELOG.md`
- 关键风险：表格单元格/表头包 SGR 后 `padded()`/`truncate()`（`MarkdownEngine.swift` L843 区域）的宽度计算——`visibleWidth` 声称 ANSI-aware，但**截断落在转义序列中间会切穿 SGR 导致颜色泄漏**；上色只许包整行/整格，不许在 truncate 路径内插色。
- DoD：渲染 golden（默认主题含 SGR、`.none` 与旧输出一致）；ANSI-aware 表格宽度测试（彩色表头下对齐不变、truncate 不切序列）；`StreamingStableCommitTests` 绿；CHANGELOG Added + surface 文档同步。
- 回滚：theme `.none` 即回旧观感。

### TASK-25 `html-degrade`
- 目标：HTML 块降级为可读文本。
- 涉及文件：
  - 新增 `Sources/ForgeLoopTUI/Markdown/HTMLDegrader.swift`（剥标签、实体解码、块级标签换行；纯函数，数据驱动标签表）
  - 修改 `Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift`（`renderFully`/`renderInlineMarkdown` L354 接线；inCodeFence 分支隔离不降级）
  - 新增 `Tests/ForgeLoopTUITests/Markdown/HTMLDegraderTests.swift`
  - 文档：`CHANGELOG.md`
- 范围细节：常见实体（`&amp; &lt; &gt; &quot; &#39; &nbsp;`）；块级标签（`div/table/tr/p/ul/li/details/summary/h1-h6/br`）转换行；标签属性串不输出；`<summary>` 内容保留为前缀行；行内 HTML（如 `<kbd>`）剥标签留文本。
- DoD：降级用例测试（属性串不泄漏、块级换行、实体解码、fence 内不降级）；`Examples/Fixtures/markdown-full-showcase.md` §7/§9 目测从"标签汤"变"可读文本"；CHANGELOG Added。

### TASK-26 `latex-approx`
- 目标：LaTeX 常见宏 Unicode 近似渲染。
- 涉及文件：
  - 新增 `Sources/ForgeLoopTUI/Markdown/LaTeXApproximator.swift`（映射表数据驱动；`$...$`/`$$...$$` 区段内转换；未知宏原样透传；`\begin{...}` 环境整块保持 raw）
  - 修改 `Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift`（`renderInlineMarkdown` L354 接线行内 `$...$`；`renderFully` 接线 `$$` 块）
  - 新增 `Tests/ForgeLoopTUITests/Markdown/LaTeXApproximatorTests.swift`
  - 文档：`CHANGELOG.md`
- 范围细节：希腊字母表、常见运算符（`\int \infty \pm \geq \leq \neq \cdot \times`）、`\sqrt{...}`、`\frac{a}{b}→(a)/(b)`、单字符上下标（`x_1→x₁`、`x^2→x²`，多字符上标覆盖 `e^{i\pi}` 类常见形）。
- DoD：宏映射单测（含未知宏透传、环境块 raw）；fixture §5 目测；CHANGELOG Added。

### TASK-32 `html-degrade-cell-separator`（一期追加，微任务）
- 目标：HTML 表格单元格降级加空格分隔——`th`/`td` 剥标签时在单元格间留空格，不再无分隔连接（`DB_HOST192.168.1.53仅运维` → `DB_HOST 192.168.1.53 仅运维`）。
- 来源：TASK-25 评审披露的已知风险，用户拍板"要的"（§0 拍板表）。
- 涉及文件：
  - 修改 `Sources/ForgeLoopTUI/Markdown/HTMLDegrader.swift`（单元格标签走"空格分隔"而非"整段剥除"；多空格折叠/首尾 trim 走现有 postProcess）
  - 修改 `Tests/ForgeLoopTUITests/Markdown/HTMLDegraderTests.swift`（追加用例：td/th 分隔、连续单元格不多余空格、行内 td 与块级 tr 组合）
  - 文档：`CHANGELOG.md`（TASK-25 条目补一句即可）
- DoD：新增用例全绿 + 既有 19 用例不回归；全量 `swift test` 绿。
- 风险：无；纯数据/分支小改。**前置**：TASK-25/26 先提交，本任务在其 diff 上落地。

### TASK-27 `preview-anchor-oracle`（二期前置闸门）
- 目标：**先证后建**——VirtualTerminal 预言机测试证明"`render(committed: 非空, live: …)` 与帧间 `appendFrame` 共存时帧锚定正确、无错位无重复"。
- 涉及文件：
  - 新增 `Tests/ForgeLoopTUITests/Runtime/CommittedPreviewAnchorTests.swift`（参考 `Tests/ForgeLoopTUITests/Runtime/CommittedLiveRenderTests.swift` 与 5434 帧 oracle 先例 `Tests/ForgeLoopTUITests/Markdown/StreamingGarbleTUIRegressionTests.swift`）
  - 预言机：`Sources/ForgeLoopTUI/Terminal/VirtualTerminal.swift`（只读使用）
  - 被测面：`Sources/ForgeLoopTUI/Runtime/TUIRuntime.swift` 的 `render(committed:live:)`（L318/L345）与 `appendFrame`
- 证据：`LiveBudgetPlanner` 只结算 live（`Sources/ForgeLoopTUI/Runtime/LiveBudgetPlanner.swift:59-75`），committed 区由帧间 diff 原地更新、不进 scrollback——预览行必须且只许走 committed 通道；现有用法全是 `render(committed: [], …)`，非空 committed + appendFrame 组合从未走过。
- DoD：oracle 测试覆盖"预览行内容变/行数增减 + 间歇 appendFrame"全组合，字节流与预言机逐帧一致。**测试不过 → 不实现 TASK-28，降级备选**（预览只放 live 尾部压进 liveBudget，约 2 行），回本计划登记变更。

### TASK-28 `unstable-region-live-preview`
- 目标：MinimalAIApp 流式期间实时显示不稳定区，恢复"逐行流出"体感。
- 涉及文件：
  - 修改 `Examples/MinimalAIApp/Sources/MinimalAIApp/main.swift`（`render()` L263：改 `tui.render(committed: 不稳定尾部, live: 状态+输入)`；不稳定尾部 = active block 内 `activeStreamingStableLineCount` 之后的行；行变稳定 → `appendFrame` 落卷轴 → 下一帧从 committed 区移除）
  - 修改 `Examples/MinimalAIApp/pty_smoke.py`（新增断言：表格/fence 流式期间中间态可见、终态无重复、`/demo table` 终态行序 == 静态渲染）
  - 文档：`Examples/MinimalAIApp/README.md`（渲染模式说明）、`CHANGELOG.md`
- 依赖：TASK-27 闸门通过。
- DoD：pty 断言全绿；`pty_smoke.py` 全 PASS；DeepSeek 实际问答一轮人工体感（长 fence 回复逐行流出而非末尾整弹）。

### TASK-29 `preview-long-fence-soak`
- 目标：长未闭合 fence（>100 行）的预览稳定性专项。
- 涉及文件：
  - 新增 `Examples/Fixtures/markdown-long-fence-soak.md`（整篇 fence 包裹的长文）
  - 修改 `Examples/MinimalAIApp/pty_smoke.py` 或新增专项脚本（流式灌入 + resize 中断）
  - 文档：`CHANGELOG.md`（视实现触碰面补 Fixed/Added）
- DoD：无重复提交、无错位、resize 后预览不错乱，自动化断言全绿。

### TASK-30 `highlight-python`
- 目标：自研小型 tokenizer + Python 高亮，挂上 theme。
- 涉及文件：
  - 新增 `Sources/ForgeLoopTUI/Markdown/Highlighting/SyntaxHighlighter.swift`（协议：`highlight(line:) -> [Segment]`，Segment = 文本+样式；行级无隐藏状态，跨行字符串/注释状态由 fence 渲染循环显式传递）
  - 新增 `Sources/ForgeLoopTUI/Markdown/Highlighting/PythonHighlighter.swift`（关键字/字符串/注释/数字四类，三引号字符串跨行状态）
  - 修改 `Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift`（`renderCodeFenceContent` L620 接线，按 fence info string 选高亮器；未识别语言回退纯文本）
  - 新增 `Tests/ForgeLoopTUITests/Markdown/Highlighting/PythonHighlighterTests.swift`
  - 文档：`docs/public-api-surface.md`（协议如公开）、`CHANGELOG.md`
- DoD：Python 高亮单测（含跨行三引号、字符串内 `#` 不当注释）；`.none` 主题下输出不变；全量绿。

### TASK-31 `highlight-javascript`
- 目标：JavaScript 高亮（验证第二语言接入成本）。
- 涉及文件：
  - 新增 `Sources/ForgeLoopTUI/Markdown/Highlighting/JavaScriptHighlighter.swift`（关键字/字符串含模板字符串/注释含块注释跨行/数字）
  - 新增 `Tests/ForgeLoopTUITests/Markdown/Highlighting/JavaScriptHighlighterTests.swift`
  - 文档：`CHANGELOG.md`、（如协议公开）`docs/public-api-surface.md`
- DoD：JS 高亮单测（模板字符串内 `${}` 不炸、块注释跨行）；`/demo full` 目测两段代码块上色；CHANGELOG Added。

## 5. 风险登记

| 风险 | 等级 | 缓解 |
|------|------|------|
| TASK-27 闸门不过（committed+appendFrame 锚定有坑） | 中 | 预案已定义（live 尾部压预算），降级不阻塞一三期 |
| 表格内 ANSI 截断切穿 SGR | 中 | TASK-24 关键风险项，专项测试 |
| theme 默认开启导致存量 golden 测试大面积更新 | 低 | TASK-23 用 `.none` 反钉旧输出，默认主题新增 golden |
| LaTeX 映射表覆盖面争议 | 低 | 边界已拍板；争议宏一律 raw，后续追加不加逻辑 |

## 6. 建议先做的 step

**TASK-23**（骨架零风险，后续全部挂在 theme 上）→ TASK-24（观感见效最快）。一期完成后即可可用；二期是体感增强，三期是锦上添花。

---

## 7. 执行提示词（逐任务可复制，供执行 agent 使用）

通用模板已填入各任务；每个提示词自包含（执行 agent 零上下文）。依赖关系：23→24；25、26 独立；27→28→29；23→30→31。

### 提示词 TASK-23

```text
你在 ForgeLoopTUI 仓库执行 TASK-23 `markdown-theme-scaffold`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-23 节及 §0 拍板、§0.1 硬约束、§2 通用 DoD）

目标：新增 MarkdownTheme 值类型并接入 MarkdownRenderOptions（默认开启），本任务只立骨架，引擎渲染不接色。
涉及文件：
- 新增 Sources/ForgeLoopTUI/Markdown/MarkdownTheme.swift（SGR 常量+主题结构：标题各级/表头/表格边框/引用线/fence 边框/fence 语言标签/任务清单符号；公开 API doc comment 全英文）
- 修改 Sources/ForgeLoopTUI/Markdown/MarkdownRenderOptions.swift（加 theme 字段，默认 .default）
- 新增 Tests/ForgeLoopTUITests/Markdown/MarkdownThemeTests.swift
- 文档：docs/public-api-surface.md、CHANGELOG.md [Unreleased]
验收标准：
- MarkdownRenderOptions() 默认含 theme
- .none 主题下引擎输出与现状逐字节一致（现有 MarkdownEngineTests golden 不改即过即视为钉住）
- swift build && swift test 全绿（实跑附结果）
硬约束：不引第三方依赖；公开 API doc comment 英文。
上游产出：无。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-24

```text
你在 ForgeLoopTUI 仓库执行 TASK-24 `block-element-styling`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-24 节及 §0、§0.1、§2、§3 评审标准）

目标：标题/表格/引用/fence 边框接 theme 上色。
涉及文件：
- 修改 Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift：renderHeading(L515 各级标题色+粗体)、renderTable(L781 边框 dim、表头粗体)、renderStructuredLine blockquote 分支(L467 引用线上色)、renderCodeFenceStart/End(L610/L616 边框+语言标签 dim)
- 新增 Tests/ForgeLoopTUITests/Markdown/BlockElementStylingTests.swift
- 文档：docs/public-api-surface.md、CHANGELOG.md [Unreleased]
验收标准：
- 渲染 golden：默认主题含 SGR、.none 主题与旧输出逐字节一致
- ANSI-aware 表格宽度测试：彩色表头对齐不变；truncate 不切断转义序列
- swift test --filter StreamingStableCommitTests 绿；全量 swift test 绿
关键风险（评审红线）：上色只许包整行/整格，禁止在 padded()/truncate() 路径内插色——截断切穿 SGR 会把颜色泄漏到后续输出。
上游产出：TASK-23 的 MarkdownTheme/MarkdownRenderOptions.theme。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-25

```text
你在 ForgeLoopTUI 仓库执行 TASK-25 `html-degrade`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-25 节及 §0、§0.1、§2）

目标：HTML 块降级为可读文本（剥标签/实体解码/块级标签换行）。
涉及文件：
- 新增 Sources/ForgeLoopTUI/Markdown/HTMLDegrader.swift（纯函数，数据驱动标签表）
- 修改 Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift（renderFully/renderInlineMarkdown L354 接线；inCodeFence 分支隔离不降级）
- 新增 Tests/ForgeLoopTUITests/Markdown/HTMLDegraderTests.swift
- 文档：CHANGELOG.md [Unreleased]
范围细节：实体 &amp; &lt; &gt; &quot; &#39; &nbsp;；块级标签 div/table/tr/p/ul/li/details/summary/h1-h6/br 转换行；标签属性串不输出；<summary> 内容保留为前缀行；行内 HTML（如 <kbd>）剥标签留文本。
验收标准：
- 用例测试：属性串不泄漏、块级换行、实体解码、fence 内 <...> 不降级
- Examples/Fixtures/markdown-full-showcase.md §7/§9 渲染目测为可读文本（无标签汤）
- 全量 swift test 绿
上游产出：无（独立任务，可与 23/24 并行）。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-26

```text
你在 ForgeLoopTUI 仓库执行 TASK-26 `latex-approx`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-26 节及 §0、§0.1、§2）

目标：LaTeX 常见宏 Unicode 近似渲染（边界已拍板：只做常见形，环境块 raw）。
涉及文件：
- 新增 Sources/ForgeLoopTUI/Markdown/LaTeXApproximator.swift（映射表数据驱动；$...$ 与 $$...$$ 区段内转换；未知宏原样透传；\begin{...} 环境整块 raw）
- 修改 Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift（renderInlineMarkdown L354 接线行内 $...$；renderFully 接线 $$ 块）
- 新增 Tests/ForgeLoopTUITests/Markdown/LaTeXApproximatorTests.swift
- 文档：CHANGELOG.md [Unreleased]
范围细节：希腊字母、运算符（\int \infty \pm \geq \leq \neq \cdot \times）、\sqrt{...}、\frac{a}{b}→(a)/(b)、单字符上下标（x_1→x₁、x^2→x²，多字符上标覆盖 e^{i\pi} 类常见形）。
验收标准：
- 宏映射单测：含未知宏透传、\begin{...} 环境 raw、不吞字符
- fixture §5（markdown-full-showcase.md）目测
- 全量 swift test 绿
上游产出：无（独立任务）。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-27

```text
你在 ForgeLoopTUI 仓库执行 TASK-27 `preview-anchor-oracle`（二期前置闸门，只写测试不实现功能）。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-27 节及 §0.1、§2）

目标：用 VirtualTerminal 预言机测试证明 render(committed: 非空, live: …) 与帧间 appendFrame 共存时帧锚定正确、无错位无重复。
涉及文件：
- 新增 Tests/ForgeLoopTUITests/Runtime/CommittedPreviewAnchorTests.swift（参考 Tests/ForgeLoopTUITests/Runtime/CommittedLiveRenderTests.swift 与 oracle 先例 Tests/ForgeLoopTUITests/Markdown/StreamingGarbleTUIRegressionTests.swift）
- 只读使用：Sources/ForgeLoopTUI/Terminal/VirtualTerminal.swift
- 被测面（只读）：Sources/ForgeLoopTUI/Runtime/TUIRuntime.swift L318/L345 render(committed:live:) 与 appendFrame
背景约束：LiveBudgetPlanner 只结算 live（Sources/ForgeLoopTUI/Runtime/LiveBudgetPlanner.swift:59-75），committed 区由帧间 diff 原地更新、不进 scrollback。
验收标准：
- 覆盖"预览行内容变化/行数增减 + 间歇 appendFrame"组合，字节流与预言机逐帧一致
- 测试红也是有效交付：闸门不过即上报，禁止改库代码让测试变绿
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件（本任务尤其：发现库 bug 只上报，不修）；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果（绿=闸门通过 / 红=闸门不过附失败帧）/ 已知风险。
```

### 提示词 TASK-28

```text
你在 ForgeLoopTUI 仓库执行 TASK-28 `unstable-region-live-preview`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-28 节及 §0.1、§2）

目标：MinimalAIApp 流式期间实时显示不稳定区，恢复逐行流出体感。
涉及文件：
- 修改 Examples/MinimalAIApp/Sources/MinimalAIApp/main.swift（render() L263：改 tui.render(committed: 不稳定尾部, live: 状态+输入)；不稳定尾部 = active block 内 activeStreamingStableLineCount 之后的行；行变稳定 → appendFrame 落卷轴 → 下一帧从 committed 区移除）
- 修改 Examples/MinimalAIApp/pty_smoke.py（新增断言：表格/fence 流式期间中间态可见、终态无重复、/demo table 终态行序 == 静态渲染）
- 文档：Examples/MinimalAIApp/README.md、CHANGELOG.md
验收标准：
- pty_smoke.py 全 PASS（含新断言）
- 全量 swift test 绿；swift test --filter StreamingStableCommitTests 绿
- 人工体感：DeepSeek 实际问答一轮，长 fence 回复逐行流出而非末尾整弹
上游产出：TASK-27 闸门通过的 oracle 测试（Tests/ForgeLoopTUITests/Runtime/CommittedPreviewAnchorTests.swift 必须全绿）。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-29

```text
你在 ForgeLoopTUI 仓库执行 TASK-29 `preview-long-fence-soak`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-29 节及 §0.1、§2）

目标：长未闭合 fence（>100 行）的预览稳定性专项。
涉及文件：
- 新增 Examples/Fixtures/markdown-long-fence-soak.md（整篇 fence 包裹的长文）
- 修改 Examples/MinimalAIApp/pty_smoke.py 或新增专项脚本（流式灌入 + 中途 resize）
- 文档：CHANGELOG.md（视触碰面）
验收标准：
- 无重复提交、无错位；resize 后预览不错乱
- 自动化断言全绿；pty_smoke.py 回归全 PASS
上游产出：TASK-28 的预览实现。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-30

```text
你在 ForgeLoopTUI 仓库执行 TASK-30 `highlight-python`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-30 节及 §0、§0.1、§2）

目标：自研小型 tokenizer + Python 高亮，挂上 theme。
涉及文件：
- 新增 Sources/ForgeLoopTUI/Markdown/Highlighting/SyntaxHighlighter.swift（协议：行级 highlight，Segment=文本+样式；无隐藏状态，跨行状态由调用方显式传递）
- 新增 Sources/ForgeLoopTUI/Markdown/Highlighting/PythonHighlighter.swift（关键字/字符串/注释/数字四类；三引号字符串跨行状态）
- 修改 Sources/ForgeLoopTUI/Markdown/MarkdownEngine.swift（renderCodeFenceContent L620 接线，按 fence info string 选高亮器；未识别语言回退纯文本）
- 新增 Tests/ForgeLoopTUITests/Markdown/Highlighting/PythonHighlighterTests.swift
- 文档：docs/public-api-surface.md（协议如公开）、CHANGELOG.md [Unreleased]
验收标准：
- 单测：跨行三引号、字符串内 # 不误判注释、未识别语言纯文本回退
- .none 主题下输出与旧字节流一致
- 全量 swift test 绿；StreamingStableCommitTests 绿
硬约束：不引第三方高亮依赖；高亮器为确定纯函数。
上游产出：TASK-23 的 theme（fence 内容样式槽位）。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```

### 提示词 TASK-31

```text
你在 ForgeLoopTUI 仓库执行 TASK-31 `highlight-javascript`。

- 仓库根：/Users/boyang/Desktop/WebKit_build/ForgeLoopTUI
- 任务单：plans/PLAN-2026-08-render-polish.md（先读 TASK-31 节及 §0、§0.1、§2）

目标：JavaScript 高亮（验证第二语言接入成本）。
涉及文件：
- 新增 Sources/ForgeLoopTUI/Markdown/Highlighting/JavaScriptHighlighter.swift（关键字/字符串含模板字符串/注释含块注释跨行/数字）
- 新增 Tests/ForgeLoopTUITests/Markdown/Highlighting/JavaScriptHighlighterTests.swift
- 文档：CHANGELOG.md、（如协议公开）docs/public-api-surface.md
验收标准：
- 单测：模板字符串内 ${} 不炸、块注释跨行
- /demo full 目测两段代码块上色
- 全量 swift test 绿
上游产出：TASK-30 的 SyntaxHighlighter 协议与 fence 接线。
硬停止条件（命中即停并上报，不硬试、不回滚）：
1) 同一处修改尝试超过 3 次仍未通过；
2) 需要改动上述清单之外的文件；
3) 测试/构建失败原因超出任务描述范围。
完成后输出 Review Package：Step 编号 / 改动文件列表 / 关键 diff 摘要 / 自测命令 / 自测结果 / 已知风险。
```
