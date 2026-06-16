import XCTest
@testable import ForgeLoopTUI

final class TUITests: XCTestCase {
    private final class DiagnosticCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [TUIRenderDiagnostic] = []
        var events: [TUIRenderDiagnostic] { lock.withLock { _events } }
        func append(_ event: TUIRenderDiagnostic) {
            lock.withLock { _events.append(event) }
        }
    }

    func testInlineFirstFrameHasNoClearScreen() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.requestRender(lines: ["hello", "world"])

        XCTAssertEqual(spy.last, "hello\r\nworld\r\n")
        XCTAssertFalse(spy.last!.contains("\u{1B}[2J"))
    }

    func testInlineNormalizesEmbeddedNewlines() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.requestRender(lines: ["hello\nworld"])

        XCTAssertEqual(spy.last, "hello\r\nworld\r\n")
    }

    func testLegacySupportsCursorOffset() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .legacyAbsolute, writer: spy.writer)

        tui.requestRender(lines: ["prompt"], cursorOffset: 2)

        XCTAssertEqual(spy.last, "\u{1B}[2J\u{1B}[Hprompt\u{1B}[2D")
    }

    func testAppendFrameWritesPlainOutput() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.appendFrame(lines: ["line1", "line2"])

        XCTAssertEqual(spy.last, "line1\r\nline2\r\n")
        XCTAssertFalse(spy.last!.contains("\u{1B}["))
    }

    func testResetRetainedFrameRestartsInlineRendering() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.requestRender(lines: ["old"])
        tui.appendFrame(lines: ["stream"])
        tui.resetRetainedFrame()
        tui.requestRender(lines: ["new"])

        XCTAssertEqual(spy.outputs.last, "new\r\n")
    }

    func testInlineSameFrameCursorOffsetMovesRelative() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.requestRender(lines: ["prompt"], cursorOffset: 2)
        tui.requestRender(lines: ["prompt"], cursorOffset: 1)
        tui.requestRender(lines: ["prompt"], cursorOffset: 3)

        XCTAssertEqual(spy.outputs[0], "prompt\u{1B}[2D")
        XCTAssertEqual(spy.outputs[1], "\u{1B}[1C")
        XCTAssertEqual(spy.outputs[2], "\u{1B}[2D")
    }

    func testTerminalInitRendersFrameToVirtualScreen() {
        // writer 路径已在 testInlineFirstFrameHasNoClearScreen 等测试中验证。
        // 此处直接验证 Terminal 路径在 TTY 模式下的输出与 writer 路径等价。
        let vt = VirtualTerminal()
        let terminalTUI = TUI(isTTY: true, terminal: vt)
        terminalTUI.requestRender(lines: ["hello", "world"])
        // TTY 模式下 TUI 输出 \r\n，VirtualTerminal 将其解析为两行
        XCTAssertEqual(vt.buffer, "hello\nworld")
        XCTAssertTrue(vt.screenLines[0].hasPrefix("hello"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("world"))
    }

    func testVirtualTerminalDefaultsToNonTTYBehavior() {
        let vt = VirtualTerminal()
        let tui = TUI(terminal: vt)

        tui.requestRender(lines: ["hello", "world"])

        XCTAssertFalse(tui.isTTY)
        // 非 TTY 模式下 TUI 输出 \n，VirtualTerminal 将其作为 line feed，
        // 因此 buffer 不会包含 \r\n，且内容按终端语义分布。
        XCTAssertFalse(vt.buffer.contains("\r\n"))
        XCTAssertTrue(vt.screenLines[0].contains("hello"))
        XCTAssertTrue(vt.screenLines[1].contains("world"))
    }

    // MARK: - M1-S7 VirtualTerminal 屏幕状态断言

    func testLegacyClearAndHomeOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .legacyAbsolute, isTTY: true, terminal: vt)

        tui.requestRender(lines: ["prompt"], cursorOffset: 2)

        // ESC[2J + ESC[H 清屏归位后写入 "prompt"，再 ESC[2D 左移 2
        XCTAssertTrue(vt.screenLines[0].hasPrefix("prompt"))
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 4) // "prompt" 长度 6，左移 2 -> col 4
    }

    func testInlineFirstFrameOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .inlineAnchor, isTTY: true, terminal: vt)

        tui.requestRender(lines: ["hello", "world"])

        XCTAssertTrue(vt.screenLines[0].hasPrefix("hello"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("world"))
        XCTAssertEqual(vt.cursorRow, 2) // \r\n 后光标在第 3 行
        XCTAssertEqual(vt.cursorCol, 0)
    }

    func testInlineSecondUpdateRedrawsOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .inlineAnchor, isTTY: true, terminal: vt)

        tui.requestRender(lines: ["old"])
        tui.requestRender(lines: ["new"])

        // 第二次渲染应通过 ESC[A / ESC[2K / ESC[A 重绘当前行
        XCTAssertTrue(vt.screenLines[0].hasPrefix("new"))
        // 旧内容 "old" 应被清除
        XCTAssertFalse(vt.screenLines[0].contains("old"))
        XCTAssertEqual(vt.cursorRow, 1) // trailing \r\n 后光标下移
        XCTAssertEqual(vt.cursorCol, 0)
    }

    func testInlineCursorOffsetRelativeMoveOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .inlineAnchor, isTTY: true, terminal: vt)

        tui.requestRender(lines: ["prompt"], cursorOffset: 2)
        // 首帧写入 "prompt" 后 ESC[2D，光标在 col 4
        XCTAssertEqual(vt.cursorCol, 4)

        tui.requestRender(lines: ["prompt"], cursorOffset: 1)
        // 同帧右移 1：ESC[1C
        XCTAssertEqual(vt.cursorCol, 5)

        tui.requestRender(lines: ["prompt"], cursorOffset: 3)
        // 同帧左移 2：ESC[2D
        XCTAssertEqual(vt.cursorCol, 3)
    }

    func testAppendFrameOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(isTTY: true, terminal: vt)

        tui.appendFrame(lines: ["line1", "line2"])

        // TTY 模式下 appendFrame 使用 \r\n，两行分别落在 row 0/1
        XCTAssertTrue(vt.screenLines[0].hasPrefix("line1"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("line2"))
        XCTAssertEqual(vt.cursorRow, 2)
        XCTAssertEqual(vt.cursorCol, 0)
    }

    func testResetRetainedFrameRestartsInlineOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .inlineAnchor, isTTY: true, terminal: vt)

        tui.requestRender(lines: ["old"])
        tui.appendFrame(lines: ["stream"])
        tui.resetRetainedFrame()
        tui.requestRender(lines: ["new"])

        // reset 不清屏，只丢弃 retained 状态；下一次 requestRender 在当前位置继续
        // "old" 在 row 0，"stream" 在 row 1，"new" 在 row 2（当前光标位置）
        XCTAssertTrue(vt.screenLines[0].hasPrefix("old"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("stream"))
        XCTAssertTrue(vt.screenLines[2].hasPrefix("new"))
        // 验证不含清屏序列（间接：如果清屏则 row 0 会为空）
        XCTAssertFalse(vt.screenLines[0].allSatisfy { $0 == " " })
    }

    // MARK: - M4-S5: Resize-safe anchoring (VirtualTerminal screen-state assertion)

    func testResizeRecomputesPhysicalRowsOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .inlineAnchor, isTTY: true, terminalWidth: 10, terminalHeight: 5, terminal: vt)

        // 帧1：width=10，"longline" = 8 chars → 1 physical row
        tui.requestRender(lines: ["a", "longline"])
        XCTAssertTrue(vt.screenLines[0].hasPrefix("a"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("longline"))

        // resize 到 width=5（VirtualTerminal 截断，TUI 重算物理行缓存）
        vt.resize(width: 5, height: 5)
        tui.updateTerminalSize(width: 5, height: 5)

        // 帧2：内容变化，diff 应基于重算后的物理行数正确回退
        tui.requestRender(lines: ["a", "abcde"])
        XCTAssertTrue(vt.screenLines[0].hasPrefix("a"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("abcde"))
    }

    // MARK: - A1: invalidate() 行为测试

    func testInvalidateDoesNotChangeTerminalDimensions() {
        let tui = TUI(terminalWidth: 80, terminalHeight: 24)
        let w = tui.terminalWidth
        let h = tui.terminalHeight
        tui.invalidate()
        XCTAssertEqual(tui.terminalWidth, w)
        XCTAssertEqual(tui.terminalHeight, h)
    }

    func testInvalidateIsIdempotent() {
        let tui = TUI(terminalWidth: 80, terminalHeight: 24)
        // Multiple invalidate calls should not crash or corrupt state
        tui.invalidate()
        tui.invalidate()
        tui.invalidate()
        // 后续渲染正常（不抛错不崩溃）
        tui.requestRender(lines: ["hello"])
        // 二次 invalidate + 渲染
        tui.invalidate()
        tui.requestRender(lines: ["world"])
    }

    func testInvalidateAfterResizeProducesCorrectNextFrame() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(strategy: .inlineAnchor, isTTY: true, terminalWidth: 10, terminalHeight: 5, terminal: vt)

        // 帧1：width=10
        tui.requestRender(lines: ["header", "content"])
        XCTAssertTrue(vt.screenLines[0].hasPrefix("header"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("content"))

        // 外部 resize（如窗口变化），不通过 updateTerminalSize 通知 TUI
        vt.resize(width: 4, height: 5)
        // 手动让 TUI 感知新尺寸 + 标记失效
        tui.updateTerminalSize(width: 4)
        tui.invalidate()

        // 帧2：内容不变，diff 应基于新重算的物理行缓存正确渲染
        tui.requestRender(lines: ["new"])
        // 验证渲染输出不含残留的旧行（stale rows from old cache）
        // "header" 和 "content" 已被清除，"new" 是唯一条目
        XCTAssertTrue(vt.screenLines[0].hasPrefix("new"))
        // row 1 应为空（被 ESC[2K 清除）
        XCTAssertTrue(vt.screenLines[1].allSatisfy { $0 == " " })
    }

    // MARK: - C5: diagnostics handler

    func testDiagnosticsHandlerReceivesEvents() {
        let collector = DiagnosticCollector()
        let tui = TUI(isTTY: true, terminalHeight: 3)
        tui.diagnosticsHandler = { [weak collector] event in
            collector?.append(event)
        }

        // First render — exceeds height=3 with default width=80, triggers full redraw
        tui.requestRender(lines: ["line1", "line2", "line3", "line4"])

        let events = collector.events
        XCTAssertFalse(events.isEmpty, "Should emit at least one diagnostic")
        let hasFullRedraw = events.contains(where: {
            if case .fullRedraw = $0 { return true }; return false
        })
        XCTAssertTrue(hasFullRedraw, "Frame exceeding terminal height should trigger fullRedraw")
    }

    func testDiagnosticsHandlerDefaultIsNil() {
        let tui = TUI()
        XCTAssertNil(tui.diagnosticsHandler)
    }

    func testMarkerModeOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(
            strategy: .inlineAnchor,
            isTTY: true,
            terminalWidth: 10,
            cursorPositioningMode: .marker,
            terminal: vt
        )

        tui.render(committed: [], live: ["prompt"], cursorPlacement: CursorPlacement(up: 0, offset: 2))

        XCTAssertTrue(vt.screenLines[0].hasPrefix("prompt"))
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 4) // ESC[5G → 1-indexed col 5 → 0-indexed col 4
    }

    func testMarkerModeUndoOnVirtualTerminal() {
        let vt = VirtualTerminal(width: 10, height: 5)
        let tui = TUI(
            strategy: .inlineAnchor,
            isTTY: true,
            terminalWidth: 10,
            cursorPositioningMode: .marker,
            terminal: vt
        )

        tui.render(committed: [], live: ["abcde", "xy"], cursorPlacement: CursorPlacement(up: 1, offset: 3))
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 2)

        tui.render(committed: [], live: ["abcde", "xy"], cursorOffset: 0)

        // Undo moves down 1 row and emits CHA to canonical column 3 (0-indexed col 2).
        XCTAssertEqual(vt.cursorRow, 1)
        XCTAssertEqual(vt.cursorCol, 2)
    }
}
