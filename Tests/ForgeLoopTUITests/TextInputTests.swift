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
}
