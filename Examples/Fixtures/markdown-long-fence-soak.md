```markdown
本 fixture 用于 TASK-29 长未闭合 fence 预览浸泡测试。
整篇文档被单个 code fence 包裹，流式期间 fence 长时间未闭合，
引擎稳定前缀回退到 fence 之前，全部内容走 committed 预览区。
SOAKMARK-EARLY：前段 sentinel，流式开始后应早在预览中可见。
fence 内的表格状行必须按纯文本渲染，不允许变成真表格。
以下行刻意保留管道字符，模拟模型输出里的伪表格。

| step | owner | status |
| ---- | ----- | ------ |
| boot | alice | done   |
| scan | bob   | done   |
| soak | carol | wip    |
| SOAKMARK-TABLE-ROW | dave | queued |
| trim | erin  | queued |
| pack | frank | queued |
| ---- | ----- | ------ |
| 汇总行不触发表格渲染 | n/a | n/a |
伪表格结束，下面进入代码片段段落。

def render(frame):
    cells = split_columns(frame)
    return "|".join(cells)  # SOAKMARK-PY

class SoakRunner:
    def __init__(self, width=80):
        self.width = width
        self.frames = []

    def push(self, frame):
        self.frames.append(frame)
        if len(self.frames) > 4096:
            self.frames.pop(0)

段落 01：预览帧在流式期间逐行生长，而不是末尾整段弹出。
段落 02：committed 预览区超出终端高度时走 full-redraw 回退。
段落 03：这是文档化的库行为，本 soak 专门覆盖该路径。
段落 04：稳定前缀契约要求渲染是输入文本的确定函数。
段落 05：未闭合 fence 内任何行都不允许提前沉降。
段落 06：闭合 fence 到达时，整块一次性 appendFrame 落卷轴。
段落 07：沉降序列是空渲染擦除、appendFrame、再重绘预览。
段落 08：每一帧都保持锚定，帧间 diff 不跨越锚定边界。
SOAKMARK-MID：脚本看到本行后立即把 PTY 从 24x80 改为 30x100。
段落 09：resize 之后宽度变化，后续预览帧按新宽度重排。
段落 10：resize 不应导致重复提交、错位或预览卡死。
段落 11：行宽刻意压在 70 列以内，避免自动换行干扰断言。
段落 12：sentinel 均为唯一字符串，按字节匹配即可定位。
段落 13：middleware 风格的流水行继续把篇幅拉长。
段落 14：pipeline stage alpha completed without remarks.
段落 15：pipeline stage bravo completed without remarks.
段落 16：稳定前缀只会在源行边界前进，绝不倒退。
段落 17：渲染输出必须是同一文本的确定字节流。
段落 18：预览帧之间只允许 live 区原地 diff。
段落 19：committed 区超屏时整帧清屏重画是文档化回退。
段落 20：本段落块把 fence 中段篇幅继续拉长。
段落 21：middleware note, nothing to settle yet.

const total = items.reduce((acc, it) => acc + it.cost, 0);
function renderRow(cells) {
  return cells.join(" | "); // SOAKMARK-JS
}
const settled = frames.filter(Boolean);
if (settled.length > 0) {
  flush(settled[0]);
}

中文段落一：长 fence 内的中文行也应逐行预览，不整段弹出。
中文段落二：宽字符在两种终端宽度下都不应破坏锚定。
SOAKMARK-CJK：本行用于校验 CJK 内容在终态中的位置。
中文段落三：预览区重绘时宽字符占两格，宽度计算须一致。
中文段落四：沉降之后这些行只许在卷轴里出现一次。

check 001: anchor invariants hold at eighty columns.
check 002: anchor invariants hold at one hundred columns.
check 003: preview frame rewrite keeps scrollback intact.
check 004: preview frame rewrite keeps scrollback intact.
check 005: stable prefix advances on line boundaries only.
check 006: stable prefix advances on line boundaries only.
check 007: unclosed fence holds back every content line.
check 008: unclosed fence holds back every content line.
check 009: closing fence settles the whole block at once.
check 010: closing fence settles the whole block at once.
check 011: erase step renders an empty anchored frame first.
check 012: erase step renders an empty anchored frame first.
check 013: appended lines land between history and preview.
check 014: appended lines land between history and preview.
check 015: redraw step repaints only the remaining preview.
check 016: redraw step repaints only the remaining preview.
check 017: terminal width is polled on every render pass.
check 018: terminal width is polled on every render pass.
check 019: resize mid-stream changes wrapping of later frames.
check 020: resize mid-stream changes wrapping of later frames.
check 021: no sentinel may be committed more than once.
check 022: no sentinel may be committed more than once.
check 023: settled order equals the static render order.
check 024: settled order equals the static render order.
check 025: full redraw fallback stays byte deterministic.
check 026: full redraw fallback stays byte deterministic.
check 027: soak padding line, nothing to report.
check 028: soak padding line, nothing to report.
check 029: soak padding line, nothing to report.
check 030: soak padding line, nothing to report.

log 001: heartbeat ok, frame diff applied in place.
log 002: heartbeat ok, frame diff applied in place.
log 003: heartbeat ok, preview region repainted.
log 004: heartbeat ok, preview region repainted.
log 005: heartbeat ok, committed region stable.
log 006: heartbeat ok, committed region stable.
log 007: heartbeat ok, live region within budget.
log 008: heartbeat ok, live region within budget.
log 009: heartbeat ok, cursor placement marker mode.
log 010: heartbeat ok, cursor placement marker mode.
log 011: heartbeat ok, no scrollback ejection observed.
log 012: heartbeat ok, no scrollback ejection observed.
log 013: heartbeat ok, terminal size polled per frame.
log 014: heartbeat ok, terminal size polled per frame.
log 015: heartbeat ok, erase-then-append settle sequence.
log 016: heartbeat ok, erase-then-append settle sequence.
log 017: heartbeat ok, anchored frames end to end.
log 018: heartbeat ok, anchored frames end to end.
log 019: heartbeat ok, soak continues past one hundred lines.
log 020: heartbeat ok, soak continues past one hundred lines.
SOAKMARK-LATE：本行在 resize 之后才到达，首次出现应处于流式预览帧。
log 021: heartbeat ok, post-resize preview still alive.
log 022: heartbeat ok, post-resize preview still alive.
log 023: heartbeat ok, final stretch of the fixture.
log 024: heartbeat ok, final stretch of the fixture.
log 025: heartbeat ok, closing fence approaching.

收尾段落一：所有内容行都将在闭合 fence 到达后一次沉降。
收尾段落二：终态行序必须与静态渲染完全一致。
收尾段落三：沉降完成后任何强制重绘都不得再次输出这些行。
SOAKMARK-TAIL：fixture 最后一行内容，闭合 fence 紧随其后。
```
