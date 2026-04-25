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
}
