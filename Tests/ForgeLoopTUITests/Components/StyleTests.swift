import XCTest
@testable import ForgeLoopTUI

final class StyleTests: XCTestCase {
    func testPlainModeLeavesExistingTextUntouched() {
        XCTAssertEqual(Style.header("Title", mode: .plain), "Title")
        XCTAssertEqual(Style.dimmed("meta", mode: .plain), "meta")
        XCTAssertEqual(Style.running("running", mode: .plain), "running")
        XCTAssertEqual(Style.success("done", mode: .plain), "done")
        XCTAssertEqual(Style.warning("warn", mode: .plain), "warn")
        XCTAssertEqual(Style.error("boom", mode: .plain), "boom")
        XCTAssertEqual(Style.selection("selected", mode: .plain), "selected")
        XCTAssertEqual(Style.user("❯ hi", mode: .plain), "❯ hi")
        XCTAssertEqual(Style.prompt("prompt", mode: .plain), "prompt")
    }

    func testANSIModeWrapsTextWithEscapeSequence() {
        let styled = Style.error("unknown command", mode: .ansi)

        XCTAssertTrue(styled.hasPrefix("\u{1B}[31m"))
        XCTAssertTrue(styled.hasSuffix("\u{1B}[0m"))
        XCTAssertEqual(ansiStripped(styled), "unknown command")
    }

    func testANSIModePreservesVisibleWidthForCJKText() {
        let plain = "中文 status"
        let styled = Style.running(plain, mode: .ansi)

        XCTAssertEqual(ansiStripped(styled), plain)
        XCTAssertEqual(visibleWidth(styled), visibleWidth(plain))
    }

    func testSelectionStyleUsesReverseVideoEscapeSequence() {
        let styled = Style.selection("gpt-4o", mode: .ansi)

        XCTAssertTrue(styled.hasPrefix("\u{1B}[7;1m"))
        XCTAssertEqual(ansiStripped(styled), "gpt-4o")
    }

    func testPromptAndUserStylesStayWidthCompatible() {
        let prompt = Style.prompt("❯ hello", mode: .ansi)
        let user = Style.user("❯ hello", mode: .ansi)

        XCTAssertEqual(visibleWidth(prompt), visibleWidth("❯ hello"))
        XCTAssertEqual(visibleWidth(user), visibleWidth("❯ hello"))
    }
}
