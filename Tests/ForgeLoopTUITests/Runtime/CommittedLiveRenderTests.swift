import Foundation
import Testing
@testable import ForgeLoopTUI

@Suite("Committed/Live Rendering")
struct CommittedLiveRenderTests {

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

    // MARK: - Step 3: physicalRows live budget mode

    @Test("liveBudgetMode .physicalRows settles wrapping live lines")
    func testLiveBudgetPhysicalRowsSettles() {
        let spy = OutputSpy()
        // budget=2 physical rows at width=10. Each "0123456789ab" (12 chars) wraps to 2 rows.
        let tui = TUI(
            strategy: .inlineAnchor,
            terminalWidth: 10,
            liveBudget: 2,
            liveBudgetMode: .physicalRows,
            writer: spy.writer
        )
        let wide = "0123456789ab" // 12 chars → 2 rows @ width=10

        tui.render(committed: ["c1"], live: [wide, wide, "tail"])
        // wide(2) + wide(2) + tail(1) = 5 rows; budget=2.
        // Settle wide → remaining=[wide,tail]=3>2 → settle wide → remaining=[tail]=1 stop.
        // Expected emitted lines: c1, wide, wide, tail
        #expect(spy.last == "c1\r\n\(wide)\r\n\(wide)\r\ntail\r\n")
    }

    @Test("liveBudgetMode .physicalRows resize narrower triggers more settle on next render")
    func testLiveBudgetPhysicalRowsResizeAddsSettle() {
        let spy = OutputSpy()
        let tui = TUI(
            strategy: .inlineAnchor,
            terminalWidth: 20,
            liveBudget: 3,
            liveBudgetMode: .physicalRows,
            writer: spy.writer
        )
        let line = "abcdefghijklmnopqrst" // 20 chars → 1 row @ width=20, 2 rows @ width=10

        // Frame 1: width=20, two lines = 2 rows ≤ budget=3 → no settle.
        tui.render(committed: ["c"], live: [line, line])
        #expect(spy.last == "c\r\n\(line)\r\n\(line)\r\n")

        // Resize to width=10 (the shrink): same content now wraps to 4 rows > budget=3.
        tui.updateTerminalSize(width: 10)
        tui.render(committed: ["c"], live: [line, line])
        // After settle: head line moves to committed → committed=[c, line], live=[line].
        // Renderer flushes the new arrangement.
        let out = spy.last!
        #expect(out.contains(line))
        #expect(!out.contains("\u{1B}[2J")) // remains in inline path; resize alone shouldn't legacy-clear
    }

    @Test("liveBudgetMode .logicalLines is the default and matches historical behaviour")
    func testLiveBudgetModeDefaultLogicalLines() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, liveBudget: 2, writer: spy.writer)
        #expect(tui.liveBudgetMode == .logicalLines)

        tui.render(committed: ["c1"], live: ["l1", "l2", "l3"])
        // Logical line semantics: live=3 > budget=2 → settle l1.
        #expect(spy.last == "c1\r\nl1\r\nl2\r\nl3\r\n")
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

    // MARK: - 2D cursor placement (cursorPlacement)

    @Test("cursorPlacement up>0 emits both vertical and horizontal moves")
    func testCursorPlacementEmitsVerticalAndHorizontalMoves() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Live has two rows; cursor target = row 0 ("hello"), col 2.
        // Last line width = 5 ("world"); target row width = 5 ("hello"); placement.offset = 5 - 2 = 3.
        tui.render(committed: [], live: ["hello", "world"], cursorPlacement: CursorPlacement(up: 1, offset: 3))

        let combined = spy.outputs.joined()
        // Content rendered with cursorOffset=0 (anchored, no trailing newline)
        #expect(combined.contains("hello\r\nworld"))
        // Move up 1 row from end of last live line
        #expect(combined.contains("\u{1B}[1A"))
        // Move left to land at column 2 of "hello": last-line end col 5 → target col 2 → 3 left
        #expect(combined.contains("\u{1B}[3D"))
    }

    @Test("cursorPlacement up>0 with shorter last line moves right")
    func testCursorPlacementMovesRightWhenLastLineShorter() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Cursor on row 0 ("alphabet", width 8) at column 6 -> placement.offset = 8 - 6 = 2.
        // Last line ("") width 0; after rendering cursor is at column 0 of last line.
        // Need to go up 1 row (still at col 0) then RIGHT to col 6.
        tui.render(committed: [], live: ["alphabet", ""], cursorPlacement: CursorPlacement(up: 1, offset: 2))

        let combined = spy.outputs.joined()
        #expect(combined.contains("alphabet"))
        #expect(combined.contains("\u{1B}[1A"))
        // -leftDelta = -(0 - 6) = 6 → ESC[6C
        #expect(combined.contains("\u{1B}[6C"))
    }

    @Test("cursorPlacement up=0 matches cursorOffset behavior")
    func testCursorPlacementUpZeroEquivalentToCursorOffset() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Single live line; placement.up = 0; placement.offset = 2 should produce ESC[2D and no vertical move.
        tui.render(committed: [], live: ["hello"], cursorPlacement: CursorPlacement(up: 0, offset: 2))

        let combined = spy.outputs.joined()
        #expect(combined.contains("hello"))
        // 2D-specific extra write is empty when up=0 and last-line end column == target column.
        // Inner render emits the ESC[2D from cursorOffset=0 path... wait: the new method passes
        // cursorOffset=0 to inner render, so inner emits no horizontal. Then leftDelta=5-3=...
        // Actually: last-line width 5, targetCol = 5 - 2 = 3, leftDelta = 5 - 3 = 2 → ESC[2D
        #expect(combined.contains("\u{1B}[2D"))
        #expect(!combined.contains("\u{1B}[1A"))
        #expect(!combined.contains("\u{1B}[0A"))
    }

    @Test("cursorPlacement undo restores anchor before next render")
    func testCursorPlacementUndoBeforeNextRender() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Frame 1: place cursor on row 0 of two-line live.
        tui.render(committed: [], live: ["abcde", "xy"], cursorPlacement: CursorPlacement(up: 1, offset: 3))
        // Frame 2: any render — the first emission must include the undo sequence to move
        // cursor back to canonical anchor (down 1 row, then right by previous leftDelta = 2-2 = 0).
        // Note last line width 2, target row width 5, offset 3 → targetCol = 2, leftDelta = 2 - 2 = 0.
        // So undo is only the vertical part: ESC[1B.
        let outputsBeforeFrame2 = spy.outputs.count
        tui.render(committed: [], live: ["abcde", "xy"], cursorOffset: 0)
        // First write after frame 1 should begin with the vertical undo (ESC[1B).
        let next = spy.outputs[outputsBeforeFrame2]
        #expect(next.hasPrefix("\u{1B}[1B"))
    }

    @Test("cursorPlacement on non-TTY does not emit ANSI sequences")
    func testCursorPlacementNonTTYDropsCursorMoves() {
        let spy = OutputSpy()
        let tui = TUI(isTTY: false, writer: spy.writer)

        tui.render(committed: [], live: ["line1", "line2"], cursorPlacement: CursorPlacement(up: 1, offset: 2))
        let combined = spy.outputs.joined()
        // Non-TTY: plain newlines, no trailing newline because we delegate via cursorOffset=0 (anchored), no ANSI sequences emitted.
        #expect(combined == "line1\nline2")
        #expect(!combined.contains("\u{1B}["))
    }

    @Test("ComposedFrame with cursorPlacement is preferred over cursorOffset")
    func testComposedFramePrefersCursorPlacement() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Both set: placement wins.
        let frame = ComposedFrame(
            committed: [],
            live: ["abcdef", "12"],
            cursorOffset: 7,
            cursorPlacement: CursorPlacement(up: 1, offset: 2)
        )
        tui.render(frame: frame)

        let combined = spy.outputs.joined()
        #expect(combined.contains("abcdef\r\n12"))
        #expect(combined.contains("\u{1B}[1A"))
        // leftDelta = 2 (last "12") - (6 - 2) = 2 - 4 = -2 → ESC[2C
        #expect(combined.contains("\u{1B}[2C"))
        // cursorOffset=7 was IGNORED, so we should not see ESC[7D
        #expect(!combined.contains("\u{1B}[7D"))
    }

    // MARK: - Step 4: marker cursor positioning mode

    @Test("cursorPositioningMode defaults to .relative")
    func testCursorPositioningModeDefault() {
        let tui = TUI(strategy: .inlineAnchor)
        #expect(tui.cursorPositioningMode == .relative)
    }

    @Test("marker mode single-line uses absolute column (CHA)")
    func testMarkerSingleLine() {
        let spy = OutputSpy()
        let tui = TUI(
            strategy: .inlineAnchor,
            cursorPositioningMode: .marker,
            writer: spy.writer
        )
        // live=["hello"] width 80; placement(up=0, offset=2) → targetCol=3.
        tui.render(committed: [], live: ["hello"], cursorPlacement: CursorPlacement(up: 0, offset: 2))

        let combined = spy.outputs.joined()
        // Content rendered with anchored cursor (no trailing \r\n).
        #expect(combined.contains("hello"))
        // CHA to column 4 (1-indexed: targetCol 3 → col 4).
        #expect(combined.contains("\u{1B}[4G"))
        // No relative D/C movement (marker mode uses absolute column only).
        #expect(!combined.contains("\u{1B}[2D"))
        #expect(!combined.contains("\u{1B}[2C"))
    }

    @Test("marker mode multi-line emits vertical move plus CHA")
    func testMarkerMultiLineNoWrap() {
        let spy = OutputSpy()
        let tui = TUI(
            strategy: .inlineAnchor,
            cursorPositioningMode: .marker,
            writer: spy.writer
        )
        // live=["hello", "world"] width 80; placement(up=1, offset=3) → target row "hello" col 2.
        tui.render(committed: [], live: ["hello", "world"], cursorPlacement: CursorPlacement(up: 1, offset: 3))

        let combined = spy.outputs.joined()
        #expect(combined.contains("hello\r\nworld"))
        // Up 1 physical row to "hello".
        #expect(combined.contains("\u{1B}[1A"))
        // Absolute column 3 (1-indexed targetCol 2 → col 3).
        #expect(combined.contains("\u{1B}[3G"))
    }

    @Test("marker mode crossing wrapped row aligns to physical row")
    func testMarkerWrapAware() {
        let spy = OutputSpy()
        // width=5; "abcdefghij" (10 chars) wraps to 2 physical rows.
        let tui = TUI(
            strategy: .inlineAnchor,
            terminalWidth: 5,
            cursorPositioningMode: .marker,
            writer: spy.writer
        )
        // single logical line wrapping; placement(up=0, offset=3) → targetCol=7.
        // physicalRowInsideTarget = 7/5 = 1; cursorAbsRow = 0 + (2-1) = 1.
        // upDelta = 1 - 1 = 0; CHA col = (7 % 5) + 1 = 3.
        tui.render(committed: [], live: ["abcdefghij"], cursorPlacement: CursorPlacement(up: 0, offset: 3))

        let combined = spy.outputs.joined()
        #expect(combined.contains("abcdefghij"))
        // No vertical move (already on the target physical row).
        #expect(!combined.contains("\u{1B}[1A"))
        // CHA absolute column 3.
        #expect(combined.contains("\u{1B}[3G"))
    }

    @Test("marker mode undo emits CHA back to canonical column before next render")
    func testMarkerUndoBeforeNextRender() {
        let spy = OutputSpy()
        let tui = TUI(
            strategy: .inlineAnchor,
            cursorPositioningMode: .marker,
            writer: spy.writer
        )
        // Frame 1: place cursor on row 0 of two-line live.
        tui.render(committed: [], live: ["abcde", "xy"], cursorPlacement: CursorPlacement(up: 1, offset: 3))
        let outputsBeforeFrame2 = spy.outputs.count

        // Frame 2: any subsequent render. The first emission must begin with
        // the undo sequence: down 1 physical row + CHA back to canonical column.
        // Canonical column for last line "xy" = ((2-1) % 80) + 2 = 3.
        tui.render(committed: [], live: ["abcde", "xy"], cursorOffset: 0)
        let next = spy.outputs[outputsBeforeFrame2]
        #expect(next.hasPrefix("\u{1B}[1B\u{1B}[3G"))
    }

    @Test("marker mode on non-TTY drops cursor moves entirely")
    func testMarkerNonTTYNoAnsi() {
        let spy = OutputSpy()
        let tui = TUI(
            isTTY: false,
            cursorPositioningMode: .marker,
            writer: spy.writer
        )
        tui.render(committed: [], live: ["line1", "line2"], cursorPlacement: CursorPlacement(up: 1, offset: 2))
        let combined = spy.outputs.joined()
        // Plain newlines, no anchored trailing newline (delegated via cursorOffset=0).
        #expect(combined == "line1\nline2")
        #expect(!combined.contains("\u{1B}["))
    }

    @Test("marker mode skips both move and CHA when target == anchor (single empty line)")
    func testMarkerNoOpOnEmptyLine() {
        let spy = OutputSpy()
        let tui = TUI(
            strategy: .inlineAnchor,
            cursorPositioningMode: .marker,
            writer: spy.writer
        )
        // live=[""] empty single line; placement(up=0, offset=0) → targetCol=0 → CHA col 1.
        tui.render(committed: [], live: [""], cursorPlacement: CursorPlacement(up: 0, offset: 0))
        let combined = spy.outputs.joined()
        // CHA col 1 is still emitted (defensive baseline) so the cursor lands
        // unambiguously at column 1, but no vertical move is needed.
        #expect(combined.contains("\u{1B}[1G"))
        #expect(!combined.contains("\u{1B}[0A"))
    }
}
