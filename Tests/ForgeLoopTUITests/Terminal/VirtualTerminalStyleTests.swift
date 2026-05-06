import Testing
@testable import ForgeLoopTUI

@Suite("VirtualTerminal Style Tracking")
struct VirtualTerminalStyleTests {

    @Test("bold style is applied to subsequent characters")
    func testBoldStyleAppliedToCharacters() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1mA")
        let cells = vt.screenCells
        #expect(cells[0][0].character == "A")
        #expect(cells[0][0].style.bold == true)
        #expect(cells[0][0].style.dim == false)
    }

    @Test("reset clears active style")
    func testResetClearsStyle() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1mA\u{1B}[0mB")
        let cells = vt.screenCells
        #expect(cells[0][0].style.bold == true)
        #expect(cells[0][1].style.bold == false)
        #expect(cells[0][1].character == "B")
    }

    @Test("nested style switching preserves overlapping attributes")
    func testNestedStyleSwitching() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1;31mA\u{1B}[32mB")
        let cells = vt.screenCells
        #expect(cells[0][0].style.bold == true)
        #expect(cells[0][0].style.foreground == .standard(1))
        #expect(cells[0][1].style.bold == true)
        #expect(cells[0][1].style.foreground == .standard(2))
    }

    @Test("partial SGR split across writes still applies style")
    func testPartialSGRStyle() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[")
        vt.write("1")
        vt.write("m")
        vt.write("X")
        let cells = vt.screenCells
        #expect(cells[0][0].character == "X")
        #expect(cells[0][0].style.bold == true)
    }

    @Test("dim style is tracked")
    func testDimStyle() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[2mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.dim == true)
    }

    @Test("background color is tracked")
    func testBackgroundColor() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[42mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.background == .standard(2))
    }

    @Test("bright foreground color is tracked")
    func testBrightForeground() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[95mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.foreground == .bright(5))
    }

    @Test("clear screen resets current style")
    func testClearScreenResetsStyle() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1mA\u{1B}[2JB")
        let cells = vt.screenCells
        #expect(cells[0][0].character == "B")
        #expect(cells[0][0].style.bold == false)
    }

    @Test("colon-style SGR does not reset existing style")
    func testColonStyleSGRPreservesExistingStyle() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1mA\u{1B}[38:2:255:0:0mB")
        let cells = vt.screenCells
        #expect(cells[0][0].style.bold == true)
        #expect(cells[0][1].style.bold == true)
        #expect(cells[0][1].character == "B")
    }

    @Test("screenLines remains text-only and backward compatible")
    func testScreenLinesIgnoresStyle() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1;31mhello")
        #expect(vt.screenLines[0] == "hello     ")
        #expect(vt.buffer == "hello")
    }

    // MARK: - Extended colors

    @Test("38;5;n sets indexed foreground")
    func testIndexedForeground() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[38;5;196mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.foreground == .indexed(196))
    }

    @Test("48;5;n sets indexed background")
    func testIndexedBackground() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[48;5;21mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.background == .indexed(21))
    }

    @Test("38;2;r;g;b sets rgb foreground")
    func testRGBForeground() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[38;2;255;128;0mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.foreground == .rgb(255, 128, 0))
    }

    @Test("48;2;r;g;b sets rgb background")
    func testRGBBackground() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[48;2;0;128;255mA")
        let cells = vt.screenCells
        #expect(cells[0][0].style.background == .rgb(0, 128, 255))
    }

    @Test("incomplete extended color params do not pollute state")
    func testIncompleteExtendedColorDoesNotPollute() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1mA\u{1B}[38;2;255;0mB")
        let cells = vt.screenCells
        #expect(cells[0][0].style.bold == true)
        #expect(cells[0][1].style.bold == true)
        #expect(cells[0][1].style.foreground == nil)
    }

    @Test("39/49/0 reset semantics")
    func testResetSemantics() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}[1;31;42mA\u{1B}[39mB\u{1B}[49mC\u{1B}[0mD")
        let cells = vt.screenCells
        // A: bold + red fg + green bg
        #expect(cells[0][0].style.bold == true)
        #expect(cells[0][0].style.foreground == .standard(1))
        #expect(cells[0][0].style.background == .standard(2))
        // B: bold + default fg + green bg
        #expect(cells[0][1].style.bold == true)
        #expect(cells[0][1].style.foreground == nil)
        #expect(cells[0][1].style.background == .standard(2))
        // C: bold + default fg + default bg
        #expect(cells[0][2].style.bold == true)
        #expect(cells[0][2].style.foreground == nil)
        #expect(cells[0][2].style.background == nil)
        // D: all reset
        #expect(cells[0][3].style.bold == false)
        #expect(cells[0][3].style.foreground == nil)
        #expect(cells[0][3].style.background == nil)
    }
}
