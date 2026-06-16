import XCTest
@testable import ForgeLoopTUI

final class TextInputTests: XCTestCase {
    func testInsertMoveAndBackspace() {
        var state = TextInputState()

        state.handle(.insertText("hello"))
        state.handle(.moveLeft)
        state.handle(.moveLeft)
        state.handle(.insert(Character("X")))
        state.handle(.backspace)

        XCTAssertEqual(state.text, "hello")
        XCTAssertEqual(state.cursorPosition, 3)
    }

    func testHomeEndAndDeleteForward() {
        var state = TextInputState(text: "abcdef")

        state.handle(.moveToStart)
        XCTAssertEqual(state.cursorPosition, 0)

        state.handle(.deleteForward)
        XCTAssertEqual(state.text, "bcdef")
        XCTAssertEqual(state.cursorPosition, 0)

        state.handle(.moveToEnd)
        XCTAssertEqual(state.cursorPosition, 5)
    }

    func testRenderKeepsCursorVisibleWithHorizontalScroll() {
        var state = TextInputState(text: "0123456789")
        let rendered = state.render(prefix: "❯ ", totalWidth: 8)

        XCTAssertEqual(rendered.visibleText, "456789")
        XCTAssertEqual(rendered.line, "❯ 456789")
        XCTAssertEqual(rendered.cursorOffset, 0)
        XCTAssertEqual(rendered.scrollOffset, 4)
    }

    func testRenderPreservesCJKCursorAccounting() {
        var state = TextInputState(text: "ab中文cd")
        state.handle(.moveLeft)
        state.handle(.moveLeft)

        let rendered = state.render(prefix: Style.prompt("❯ ", mode: .ansi), totalWidth: 10)

        XCTAssertEqual(rendered.visibleText, "ab中文cd")
        XCTAssertEqual(rendered.cursorOffset, 2)
        XCTAssertEqual(visibleWidth(rendered.line), visibleWidth("❯ ab中文cd"))
    }

    func testReplaceAndClearNormalizeSingleLineInput() {
        var state = TextInputState()

        state.handle(.replace("line1\nline2\r\nline3"))
        XCTAssertEqual(state.text, "line1 line2 line3")
        XCTAssertEqual(state.cursorPosition, state.text.count)

        state.handle(.clear)
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.cursorPosition, 0)
        XCTAssertEqual(state.scrollOffset, 0)
    }

    // MARK: - CJK insertion and cursor

    func testInsertCJKAdvancesCursor() {
        var state = TextInputState()
        state.handle(.insertText("你好世界"))

        XCTAssertEqual(state.text, "你好世界")
        XCTAssertEqual(state.cursorPosition, 4)
    }

    func testMixedCJKASCIIMoveLeftRight() {
        var state = TextInputState(text: "ab中文cd")
        XCTAssertEqual(state.cursorPosition, 6)

        state.handle(.moveLeft)
        state.handle(.moveLeft)
        XCTAssertEqual(state.cursorPosition, 4)

        state.handle(.moveRight)
        XCTAssertEqual(state.cursorPosition, 5)
    }

    // MARK: - Wide-char rendering and scrolling

    func testRenderCJKScrolling() {
        var state = TextInputState(text: "你好世界")
        let rendered = state.render(totalWidth: 5)

        XCTAssertEqual(rendered.visibleText, "好世")
        XCTAssertEqual(rendered.scrollOffset, 2)
        XCTAssertEqual(rendered.cursorOffset, 0)
    }

    func testRenderMixedWidthScrolling() {
        var state = TextInputState(text: "abc中文defg")
        state.handle(.moveToStart)
        state.handle(.moveRight)
        state.handle(.moveRight)
        state.handle(.moveRight)
        state.handle(.moveRight)
        state.handle(.moveRight)
        XCTAssertEqual(state.cursorPosition, 5)

        let rendered = state.render(totalWidth: 6)

        XCTAssertEqual(rendered.visibleText, "bc中文")
        XCTAssertEqual(rendered.scrollOffset, 1)
        XCTAssertEqual(rendered.cursorOffset, 0)
    }

    // MARK: - Boundary snap

    func testScrollOffsetSnapsToBoundary() {
        var state = TextInputState(text: "你好世界", cursorAtEnd: false, scrollOffset: 3)
        state.handle(.moveRight)
        state.handle(.moveRight)

        let rendered = state.render(totalWidth: 4)

        XCTAssertEqual(rendered.scrollOffset, 2)
        XCTAssertEqual(rendered.visibleText, "好世")
    }

    func testScrollOffsetClampsToMax() {
        var state = TextInputState(text: "hi", scrollOffset: 10)
        let rendered = state.render(totalWidth: 100)

        XCTAssertEqual(rendered.scrollOffset, 0)
        XCTAssertEqual(rendered.visibleText, "hi")
    }

    // MARK: - Viewport edges

    func testRenderOneColumnViewport() {
        var state = TextInputState(text: "abc")
        let rendered = state.render(totalWidth: 1)

        XCTAssertEqual(rendered.visibleText, "c")
        XCTAssertEqual(rendered.line, "c")
        XCTAssertEqual(rendered.cursorOffset, 0)
    }

    func testRenderEmptyText() {
        var state = TextInputState(text: "")
        let rendered = state.render(prefix: "> ", totalWidth: 10)

        XCTAssertEqual(rendered.visibleText, "")
        XCTAssertEqual(rendered.line, "> ")
        XCTAssertEqual(rendered.cursorOffset, 0)
    }
}
