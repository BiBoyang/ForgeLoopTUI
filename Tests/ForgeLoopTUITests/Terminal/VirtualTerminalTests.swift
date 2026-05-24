import XCTest
@testable import ForgeLoopTUI

final class VirtualTerminalTests: XCTestCase {

    // MARK: - M1-S2 骨架测试（buffer 语义兼容）

    func testWriteRecordsOutput() {
        let vt = VirtualTerminal()
        XCTAssertEqual(vt.buffer, "")

        vt.write("hello")
        XCTAssertEqual(vt.buffer, "hello")

        vt.write(" world")
        XCTAssertEqual(vt.buffer, "hello world")
    }

    func testClearEmptiesBuffer() {
        let vt = VirtualTerminal()
        // 使用 \r\n 让每行从 col 0 开始，与真实终端行为一致
        vt.write("line1\r\nline2")
        XCTAssertEqual(vt.buffer, "line1\nline2")

        vt.clear()
        XCTAssertEqual(vt.buffer, "")

        vt.write("after clear")
        XCTAssertEqual(vt.buffer, "after clear")
    }

    func testIsTTYIsFalse() {
        let vt = VirtualTerminal()
        XCTAssertFalse(vt.isTTY)
    }

    // MARK: - M1-S5 终端模拟测试

    func testClearScreenAndHome() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello")
        XCTAssertEqual(vt.buffer, "hello")

        vt.write("\u{1B}[2J")
        XCTAssertEqual(vt.buffer, "")
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 0)
    }

    func testCursorUpAndDown() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("a\r\nb")
        XCTAssertEqual(vt.cursorRow, 1)
        XCTAssertEqual(vt.cursorCol, 1) // 'b' 写入后 col + 1

        vt.write("\u{1B}[1A") // 上移
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 1)
        vt.write("X") // 覆盖 (0,1)
        XCTAssertEqual(vt.screenLines[0], "aX        ")

        vt.write("\u{1B}[1B") // 下移
        XCTAssertEqual(vt.cursorRow, 1)
        XCTAssertEqual(vt.cursorCol, 2) // 'X' 写入后 col + 1
        vt.write("Y") // 覆盖 (1,2)
        XCTAssertEqual(vt.screenLines[1], "b Y       ")
    }

    func testCursorLeftAndRight() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("abc")
        XCTAssertEqual(vt.cursorCol, 3)

        vt.write("\u{1B}[2D") // 左移 2，到 col 1
        XCTAssertEqual(vt.cursorCol, 1)
        vt.write("X") // 覆盖 (0,1)，写入后 col=2
        XCTAssertEqual(vt.cursorCol, 2)
        XCTAssertEqual(vt.screenLines[0], "aXc       ")

        vt.write("\u{1B}[1C") // 右移 1，到 col 3
        XCTAssertEqual(vt.cursorCol, 3)
        vt.write("Y") // 覆盖 (0,3)，写入后 col=4
        XCTAssertEqual(vt.cursorCol, 4)
        XCTAssertEqual(vt.screenLines[0], "aXcY      ")
    }

    func testClearLine() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello")
        vt.write("\u{1B}[2K")
        XCTAssertEqual(vt.buffer, "")
        XCTAssertTrue(vt.screenLines[0].allSatisfy { $0 == " " })
    }

    func testNewlineAndScroll() {
        let vt = VirtualTerminal(width: 10, height: 3)
        vt.write("line1\r\nline2\r\nline3\r\nline4")

        XCTAssertEqual(vt.screenLines, ["line2     ", "line3     ", "line4     "])
    }

    func testSGRSequenceIsIgnored() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[7;1mX\u{1B}[0m")
        XCTAssertEqual(vt.buffer, "X")
        XCTAssertEqual(vt.cursorCol, 1)
    }

    func testSGRMulticolorSequenceIsIgnored() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1;36mhello\u{1B}[0m")
        XCTAssertEqual(vt.buffer, "hello")
        XCTAssertEqual(vt.cursorCol, 5)
    }

    // MARK: - M1-S6 resize 测试

    func testResizeLargerPreservesContentAndPads() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("ab")
        XCTAssertEqual(vt.screenLines[0], "ab   ")

        vt.resize(width: 8, height: 5)
        XCTAssertEqual(vt.width, 8)
        XCTAssertEqual(vt.height, 5)
        XCTAssertEqual(vt.screenLines[0], "ab      ")
        XCTAssertTrue(vt.screenLines[3].allSatisfy { $0 == " " })
        XCTAssertTrue(vt.screenLines[4].allSatisfy { $0 == " " })
    }

    func testResizeSmallerCropsContent() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello\r\nworld")
        XCTAssertEqual(vt.buffer, "hello\nworld")

        vt.resize(width: 4, height: 2)
        XCTAssertEqual(vt.width, 4)
        XCTAssertEqual(vt.height, 2)
        XCTAssertEqual(vt.screenLines[0], "hell")
        XCTAssertEqual(vt.screenLines[1], "worl")
    }

    func testResizeClampsCursor() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello\r\nworld")
        // 写入后光标在 (1,5)
        XCTAssertEqual(vt.cursorRow, 1)
        XCTAssertEqual(vt.cursorCol, 5)

        vt.resize(width: 3, height: 2)
        XCTAssertEqual(vt.cursorRow, 1)
        XCTAssertEqual(vt.cursorCol, 2)
    }

    func testResizePreservesMultilineContent() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello\r\nworld")
        XCTAssertEqual(vt.buffer, "hello\nworld")

        vt.resize(width: 8, height: 3)
        XCTAssertTrue(vt.screenLines[0].hasPrefix("hello"))
        XCTAssertTrue(vt.screenLines[1].hasPrefix("world"))
    }

    func testInitClampsIllegalSizeToOne() {
        let vt = VirtualTerminal(width: 0, height: -1)
        XCTAssertEqual(vt.width, 1)
        XCTAssertEqual(vt.height, 1)
        XCTAssertEqual(vt.screenLines, [" "])
    }

    func testResizeClampsIllegalSizeToOne() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("ab")
        XCTAssertEqual(vt.screenLines[0], "ab   ")

        vt.resize(width: 0, height: -2)
        XCTAssertEqual(vt.width, 1)
        XCTAssertEqual(vt.height, 1)
        XCTAssertEqual(vt.screenLines[0], "a")
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 0)
    }

    // MARK: - Cursor Position (CUP)

    func testCursorPositionWithRowCol() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[3;4H")
        XCTAssertEqual(vt.cursorRow, 2)
        XCTAssertEqual(vt.cursorCol, 3)
    }

    func testCursorPositionDefaultsToHome() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello")
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 5)

        vt.write("\u{1B}[H")
        XCTAssertEqual(vt.cursorRow, 0)
        XCTAssertEqual(vt.cursorCol, 0)
    }

    func testCursorPositionClampsToBounds() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("\u{1B}[100;200H")
        XCTAssertEqual(vt.cursorRow, 2)
        XCTAssertEqual(vt.cursorCol, 4)
    }

    func testCursorPositionPartialH() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[2")
        vt.write(";5H")
        XCTAssertEqual(vt.cursorRow, 1)
        XCTAssertEqual(vt.cursorCol, 4)
    }

    // MARK: - CSI L/M (Insert/Delete Lines)

    func testInsertLinesShiftsContentDown() {
        let vt = VirtualTerminal(width: 8, height: 5)
        // Populate rows 1-5 with explicit CUP, avoiding autowrap interaction
        vt.write("\u{1B}[1;1Haaaaa\u{1B}[2;1Hbbbbb\u{1B}[3;1Hccccc\u{1B}[4;1Hddddd\u{1B}[5;1Heeeee")
        // Move to row 3, insert 2 lines
        vt.write("\u{1B}[3;1H\u{1B}[2L")
        XCTAssertEqual(vt.screenLines[0], "aaaaa   ")
        XCTAssertEqual(vt.screenLines[1], "bbbbb   ")
        XCTAssertTrue(vt.screenLines[2].allSatisfy { $0 == " " })
        XCTAssertTrue(vt.screenLines[3].allSatisfy { $0 == " " })
        XCTAssertEqual(vt.screenLines[4], "ccccc   ")
    }

    func testInsertLinesDefaultCountIsOne() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("\u{1B}[1;1HAAAA\u{1B}[2;1HBBBB\u{1B}[3;1HCCCC")
        // Go to row 2, verify, insert 1 line
        vt.write("\u{1B}[2;1H")
        XCTAssertEqual(vt.screenLines[1], "BBBB ")
        vt.write("\u{1B}[L")
        XCTAssertEqual(vt.screenLines[0], "AAAA ")
        XCTAssertTrue(vt.screenLines[1].allSatisfy { $0 == " " })
        XCTAssertEqual(vt.screenLines[2], "BBBB ")
    }

    func testInsertLinesClampsToRemainingHeight() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("\u{1B}[1;1HA\u{1B}[2;1HB\u{1B}[3;1HC")
        vt.write("\u{1B}[3;1H\u{1B}[10L") // request 10, clamps to 1
        XCTAssertEqual(vt.screenLines[0], "A    ")
        XCTAssertEqual(vt.screenLines[1], "B    ")
        XCTAssertTrue(vt.screenLines[2].allSatisfy { $0 == " " })
    }

    func testDeleteLinesShiftsContentUp() {
        let vt = VirtualTerminal(width: 8, height: 5)
        vt.write("\u{1B}[1;1Haaaaa\u{1B}[2;1Hbbbbb\u{1B}[3;1Hccccc\u{1B}[4;1Hddddd\u{1B}[5;1Heeeee")
        // Move to row 2, delete 2 lines
        vt.write("\u{1B}[2;1H\u{1B}[2M")
        XCTAssertEqual(vt.screenLines[0], "aaaaa   ")
        XCTAssertEqual(vt.screenLines[1], "ddddd   ")
        XCTAssertEqual(vt.screenLines[2], "eeeee   ")
        XCTAssertTrue(vt.screenLines[3].allSatisfy { $0 == " " })
        XCTAssertTrue(vt.screenLines[4].allSatisfy { $0 == " " })
    }

    func testDeleteLinesDefaultCountIsOne() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("\u{1B}[1;1HAAAA\u{1B}[2;1HBBBB\u{1B}[3;1HCCCC")
        vt.write("\u{1B}[1;1H\u{1B}[M") // delete 1 line at top
        XCTAssertEqual(vt.screenLines[0], "BBBB ")
        XCTAssertEqual(vt.screenLines[1], "CCCC ")
        XCTAssertTrue(vt.screenLines[2].allSatisfy { $0 == " " })
    }

    func testDeleteLinesClampsToRemainingHeight() {
        let vt = VirtualTerminal(width: 5, height: 3)
        vt.write("\u{1B}[1;1HA\u{1B}[2;1HB\u{1B}[3;1HC")
        vt.write("\u{1B}[3;1H\u{1B}[10M") // request 10, clamps to 1
        XCTAssertEqual(vt.screenLines[0], "A    ")
        XCTAssertEqual(vt.screenLines[1], "B    ")
        XCTAssertTrue(vt.screenLines[2].allSatisfy { $0 == " " })
    }

    func testInsertDeleteLinesAreIdempotent() {
        let vt = VirtualTerminal(width: 5, height: 4)
        vt.write("\u{1B}[1;1HAAAA\u{1B}[2;1HBBBB\u{1B}[3;1HCCCC")
        vt.write("\u{1B}[2;1H\u{1B}[1L") // insert 1 line at row 2
        XCTAssertTrue(vt.screenLines[1].allSatisfy { $0 == " " })
        XCTAssertEqual(vt.screenLines[2], "BBBB ")
        XCTAssertEqual(vt.screenLines[3], "CCCC ")
        vt.write("\u{1B}[1M") // delete 1 line at row 2 (cursor still there)
        XCTAssertEqual(vt.screenLines[0], "AAAA ")
        XCTAssertEqual(vt.screenLines[1], "BBBB ")
        XCTAssertEqual(vt.screenLines[2], "CCCC ")
    }
}
