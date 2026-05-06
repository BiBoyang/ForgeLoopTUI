import XCTest
@testable import ForgeLoopTUI

final class TUITests: XCTestCase {
    private final class OutputSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _outputs: [String] = []

        var outputs: [String] { lock.withLock { _outputs } }
        var last: String? { lock.withLock { _outputs.last } }

        lazy var writer: FrameWriter = { [weak self] text in
            self?.lock.withLock { self?._outputs.append(text) }
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
}
