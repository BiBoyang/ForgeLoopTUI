import Foundation
import Testing
@testable import ForgeLoopTUI

@Suite("Committed/Live Rendering")
struct CommittedLiveRenderTests {

    private final class OutputSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _outputs: [String] = []

        var outputs: [String] { lock.withLock { _outputs } }
        var last: String? { lock.withLock { _outputs.last } }

        lazy var writer: FrameWriter = { [weak self] text in
            self?.lock.withLock { self?._outputs.append(text) }
        }
    }

    @Test("first render outputs full frame without clear screen")
    func testFirstRenderNoClearScreen() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)
        tui.render(committed: ["hello"], live: ["world"])

        #expect(spy.last == "hello\r\nworld\r\n")
        #expect(!(spy.last?.contains("\u{1B}[2J") ?? false))
    }

    @Test("live region change only redraws from first changed line")
    func testLiveChangeRedrawsFromDiff() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.render(committed: ["commit"], live: ["old live"])
        let firstOutput = spy.last

        tui.render(committed: ["commit"], live: ["new live"])
        let secondOutput = spy.last

        // 第二帧应回退到首行（startLineIndex 回退一行保证光标位置正确）
        #expect(secondOutput?.contains("\u{1B}[2A") ?? false)
        // 清除旧 tail
        #expect(secondOutput?.contains("\u{1B}[2K") ?? false)
        // 输出新内容
        #expect(secondOutput?.contains("new live") ?? false)
        // startLineIndex 回退一行保证光标位置正确，commit 会被连带重绘
        #expect(secondOutput?.contains("commit") ?? false)
    }

    @Test("committed region append leaves live untouched via fast path")
    func testCommitAppendFastPath() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.render(committed: ["c1"], live: ["live"])
        let firstOutput = spy.last

        tui.render(committed: ["c1", "c2"], live: ["live"])
        let secondOutput = spy.last

        // fast path: 追加 committed，不触发清除/回退到 c1 之前
        #expect(secondOutput?.contains("c2") ?? false)
        #expect(secondOutput?.contains("live") ?? false)
        #expect(!(secondOutput?.contains("\u{1B}[2K") ?? false))
        #expect(!(secondOutput?.contains("\u{1B}[2A") ?? false))
        // 使用 Insert Line 序列在 committed 与 live 之间插入新行
        #expect(secondOutput?.contains("\u{1B}[1L") ?? false)
    }

    @Test("fast path with multiple appended lines and multi-line live")
    func testFastPathMultipleAppendWithMultilineLive() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // live 区 2 行，committed 1 行
        tui.render(committed: ["c1"], live: ["live1", "live2"])

        // 追加 2 行 committed，live 不变
        tui.render(committed: ["c1", "c2", "c3"], live: ["live1", "live2"])
        let secondOutput = spy.last!

        #expect(secondOutput.contains("c2"))
        #expect(secondOutput.contains("c3"))
        #expect(secondOutput.contains("live1"))
        #expect(secondOutput.contains("live2"))
        // 不应触发清除
        #expect(!secondOutput.contains("\u{1B}[2K"))
        // 使用 ESC[2L 插入两行空行
        #expect(secondOutput.contains("\u{1B}[2L"))
    }

    // MARK: - M4-S3: Live budget / overflow settlement

    @Test("live budget settles single overflow line into committed")
    func testLiveBudgetSingleLineOverflow() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, liveBudget: 2, writer: spy.writer)

        // 帧1：3 行 live，budget=2 → settle l1 到 committed
        tui.render(committed: ["c1"], live: ["l1", "l2", "l3"])
        #expect(spy.last == "c1\r\nl1\r\nl2\r\nl3\r\n")

        // 帧2：追加 l4，settle l1,l2 → committed=["c1","l1","l2"], live=["l3","l4"]
        tui.render(committed: ["c1"], live: ["l1", "l2", "l3", "l4"])
        let out2 = spy.last!
        #expect(out2.contains("l4"))
        #expect(!out2.contains("\u{1B}[2J")) // 不应清屏
    }

    @Test("live budget settles multi-line overflow into committed")
    func testLiveBudgetMultiLineOverflow() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, liveBudget: 2, writer: spy.writer)

        // 帧1：5 行 live，budget=2 → settle l1,l2,l3
        tui.render(committed: ["c1"], live: ["l1", "l2", "l3", "l4", "l5"])
        #expect(spy.last == "c1\r\nl1\r\nl2\r\nl3\r\nl4\r\nl5\r\n")

        // 帧2：再追加 l6，settle l1,l2,l3,l4
        tui.render(committed: ["c1"], live: ["l1", "l2", "l3", "l4", "l5", "l6"])
        let out2 = spy.last!
        #expect(out2.contains("l6"))
        #expect(!out2.contains("\u{1B}[2J"))
    }

    // MARK: - M4-S5: Resize-safe anchoring and cursor positioning

    @Test("resize recomputes physical rows for correct diff baseline")
    func testResizeRecomputesPhysicalRows() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, terminalWidth: 10, writer: spy.writer)

        // 帧1：width=10，"longline" (8 chars) = 1 physical row
        tui.render(committed: ["a"], live: ["longline"])
        #expect(spy.last == "a\r\nlongline\r\n")

        // resize 到 width=5，"longline" 变成 2 physical rows
        tui.updateTerminalSize(width: 5)

        // 帧2：live 内容变化，diff 应基于重算后的物理行数
        tui.render(committed: ["a"], live: ["newlive"])
        let out2 = spy.last!
        // prevTotalRows = "a"(1) + "longline"(2) = 3，应回退 3 行
        #expect(out2.contains("\u{1B}[3A"))
        #expect(out2.contains("newlive"))
        #expect(!out2.contains("\u{1B}[2J"))
    }

    @Test("resize stress with alternating shrink and render")
    func testResizeStress() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, terminalWidth: 20, terminalHeight: 50, writer: spy.writer)

        // 连续 resize + 渲染，不应出现清屏或乱序
        for i in 0..<5 {
            tui.updateTerminalSize(width: 20 - i * 2)
            tui.render(committed: ["shared"], live: ["line\(i)"])
        }

        let lastOutput = spy.last!
        #expect(lastOutput.contains("line4"))
        #expect(!lastOutput.contains("\u{1B}[2J"))
    }

    @Test("no change with cursor offset only moves cursor")
    func testCursorOffsetOnly() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.render(committed: ["prompt"], live: [], cursorOffset: 2)
        tui.render(committed: ["prompt"], live: [], cursorOffset: 1)

        #expect(spy.outputs.count == 2)
        #expect(spy.outputs[0] == "prompt\u{1B}[2D")
        #expect(spy.outputs[1] == "\u{1B}[1C")
    }

    @Test("non-TTY mode uses plain newlines")
    func testNonTTYMode() {
        let spy = OutputSpy()
        let tui = TUI(isTTY: false, writer: spy.writer)

        tui.render(committed: ["c1"], live: ["l1"])

        #expect(spy.last == "c1\nl1\n")
        #expect(!(spy.last?.contains("\r\n") ?? false))
    }

    @Test("legacy strategy clears screen")
    func testLegacyStrategy() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .legacyAbsolute, writer: spy.writer)

        tui.render(committed: ["c1"], live: ["l1"])

        #expect(spy.last?.hasPrefix("\u{1B}[2J\u{1B}[H") ?? false)
    }

    @Test("full redraw fallback when frame exceeds terminal height")
    func testFullRedrawFallback() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, terminalHeight: 2, writer: spy.writer)

        // 首帧 3 行超过终端高度 2，应回退到 legacy
        tui.render(committed: ["a", "b", "c"], live: ["d"])

        #expect(spy.last?.hasPrefix("\u{1B}[2J\u{1B}[H") ?? false)
    }

    @Test("resetRetainedFrame clears commit/live state")
    func testResetClearsState() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.render(committed: ["old commit"], live: ["old live"])
        tui.resetRetainedFrame()
        tui.render(committed: ["new commit"], live: ["new live"])

        // reset 后不应有回退序列，因为 retained 状态已清空
        #expect(!(spy.last?.contains("\u{1B}[A") ?? false))
        #expect(spy.last?.contains("new commit") ?? false)
    }

    @Test("requestRender after render uses synchronized previousLines baseline")
    func testRequestRenderAfterRenderUsesCorrectBaseline() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Step 1: 通过 render 建立 commit/live 状态
        tui.render(committed: ["shared"], live: ["base"])
        let out1 = spy.last
        #expect(out1 == "shared\r\nbase\r\n")

        // Step 2: requestRender 应基于已同步的 previousLines 做 diff，不是首帧
        tui.requestRender(lines: ["shared", "base", "extra"])
        let out2 = spy.last
        #expect(out2?.contains("extra") ?? false)
        // 有 ANSI 序列说明进行了 diff 而非全量首帧输出
        #expect(out2?.contains("\u{1B}[") ?? false)
    }

    @Test("fallback to legacy then back to inline uses correct baseline")
    func testFallbackThenInlineUsesCorrectBaseline() {
        let spy = OutputSpy()
        // terminalHeight=2，3 行 committed 会触发 fallback
        let tui = TUI(strategy: .inlineAnchor, terminalHeight: 2, writer: spy.writer)

        // Step 1: inline 渲染建立状态
        tui.render(committed: ["a"], live: ["b"])
        let out1 = spy.last
        #expect(out1 == "a\r\nb\r\n")

        // Step 2: 触发 fallback（4 行 > height=2）
        tui.render(committed: ["f1", "f2", "f3"], live: ["f4"])
        let out2 = spy.last
        #expect(out2?.contains("\u{1B}[2J") ?? false)

        // Step 3: 恢复 inline，diff 基线应基于 fallback 后的状态
        // 如果 fallback 没同步 commit/live，prevCommitted 还是 ["a"] 而非 ["f1","f2","f3"]
        tui.render(committed: ["f1", "f2", "f3"], live: ["newLive"])
        let out3 = spy.last
        #expect(out3?.contains("newLive") ?? false)
        // 基线正确时 committedDiff=nil，应只 diff live 区（含回退/清除序列）
        #expect(out3?.contains("\u{1B}[") ?? false)
    }
}
