import Testing
@testable import ForgeLoopTUI

@Suite("KeyParser")
struct KeyParserTests {
    let parser = KeyParser()

    // MARK: - Printable characters

    @Test("plain ASCII characters")
    func testPlainASCII() {
        let units: [InputUnit] = [.character("a"), .character("Z"), .character("1")]
        let events = parser.parse(units)
        #expect(events == [
            KeyEvent(key: .character("a")),
            KeyEvent(key: .character("Z")),
            KeyEvent(key: .character("1")),
        ])
    }

    @Test("UTF-8 multibyte characters")
    func testUTF8Characters() {
        let units: [InputUnit] = [.character("中"), .character("🚀")]
        let events = parser.parse(units)
        #expect(events == [
            KeyEvent(key: .character("中")),
            KeyEvent(key: .character("🚀")),
        ])
    }

    // MARK: - Arrow keys (CSI)

    @Test("arrow keys via CSI")
    func testArrowKeysCSI() {
        let units: [InputUnit] = [
            .csi(params: [], command: "A"),
            .csi(params: [], command: "B"),
            .csi(params: [], command: "C"),
            .csi(params: [], command: "D"),
        ]
        let events = parser.parse(units)
        #expect(events == [
            KeyEvent(key: .up),
            KeyEvent(key: .down),
            KeyEvent(key: .right),
            KeyEvent(key: .left),
        ])
    }

    @Test("arrow keys with modifiers")
    func testArrowKeysWithModifiers() {
        // CSI 1 ; 2 A = Shift+Up
        let units: [InputUnit] = [
            .csi(params: [1, 2], command: "A"),
            .csi(params: [1, 5], command: "B"),
            .csi(params: [1, 6], command: "C"),
            .csi(params: [1, 8], command: "D"),
        ]
        let events = parser.parse(units)
        #expect(events == [
            KeyEvent(key: .up, modifiers: .shift),
            KeyEvent(key: .down, modifiers: .ctrl),
            KeyEvent(key: .right, modifiers: [.shift, .ctrl]),
            KeyEvent(key: .left, modifiers: [.shift, .alt, .ctrl]),
        ])
    }

    // MARK: - Home / End / PageUp / PageDown / Insert / Delete

    @Test("home and end via CSI")
    func testHomeEndCSI() {
        let events = parser.parse([
            .csi(params: [], command: "H"),
            .csi(params: [], command: "F"),
        ])
        #expect(events == [
            KeyEvent(key: .home),
            KeyEvent(key: .end),
        ])
    }

    @Test("home end insert delete page via tilde CSI")
    func testTildeCSI() {
        let events = parser.parse([
            .csi(params: [1], command: "~"),   // Home
            .csi(params: [2], command: "~"),   // Insert
            .csi(params: [3], command: "~"),   // Delete
            .csi(params: [4], command: "~"),   // End
            .csi(params: [5], command: "~"),   // PageUp
            .csi(params: [6], command: "~"),   // PageDown
        ])
        #expect(events == [
            KeyEvent(key: .home),
            KeyEvent(key: .insert),
            KeyEvent(key: .delete),
            KeyEvent(key: .end),
            KeyEvent(key: .pageUp),
            KeyEvent(key: .pageDown),
        ])
    }

    @Test("delete with ctrl modifier")
    func testDeleteWithCtrl() {
        let events = parser.parse([
            .csi(params: [3, 5], command: "~"),
        ])
        #expect(events == [KeyEvent(key: .delete, modifiers: .ctrl)])
    }

    // MARK: - Function keys

    @Test("function keys via CSI tilde")
    func testFunctionKeysTilde() {
        let events = parser.parse([
            .csi(params: [11], command: "~"),
            .csi(params: [12], command: "~"),
            .csi(params: [13], command: "~"),
            .csi(params: [14], command: "~"),
            .csi(params: [15], command: "~"),
            .csi(params: [17], command: "~"),
            .csi(params: [18], command: "~"),
            .csi(params: [19], command: "~"),
            .csi(params: [20], command: "~"),
            .csi(params: [21], command: "~"),
            .csi(params: [23], command: "~"),
            .csi(params: [24], command: "~"),
        ])
        #expect(events == [
            KeyEvent(key: .f1), KeyEvent(key: .f2), KeyEvent(key: .f3),
            KeyEvent(key: .f4), KeyEvent(key: .f5), KeyEvent(key: .f6),
            KeyEvent(key: .f7), KeyEvent(key: .f8), KeyEvent(key: .f9),
            KeyEvent(key: .f10), KeyEvent(key: .f11), KeyEvent(key: .f12),
        ])
    }

    @Test("function keys via SS3")
    func testFunctionKeysSS3() {
        let events = parser.parse([
            .escape(command: "O"), .character("P"),
            .escape(command: "O"), .character("Q"),
            .escape(command: "O"), .character("R"),
            .escape(command: "O"), .character("S"),
        ])
        #expect(events == [
            KeyEvent(key: .f1), KeyEvent(key: .f2),
            KeyEvent(key: .f3), KeyEvent(key: .f4),
        ])
    }

    // MARK: - SS3 arrow and navigation keys

    @Test("arrow keys via SS3")
    func testArrowKeysSS3() {
        let events = parser.parse([
            .escape(command: "O"), .character("A"),
            .escape(command: "O"), .character("B"),
            .escape(command: "O"), .character("C"),
            .escape(command: "O"), .character("D"),
            .escape(command: "O"), .character("H"),
            .escape(command: "O"), .character("F"),
        ])
        #expect(events == [
            KeyEvent(key: .up), KeyEvent(key: .down),
            KeyEvent(key: .right), KeyEvent(key: .left),
            KeyEvent(key: .home), KeyEvent(key: .end),
        ])
    }

    // MARK: - Control characters

    @Test("Ctrl+A through Ctrl+Z")
    func testCtrlAZ() {
        // 0x09 (Tab), 0x0A (LF/Enter), 0x0D (CR/Enter) 是特殊控制字符，
        // 被优先映射为 Tab/Enter 而不是 Ctrl+I/J/M。
        var events: [KeyEvent] = []
        var expected: [KeyEvent] = []
        for v in 0x01...0x1A {
            events.append(contentsOf: parser.parse([.character(Character(Unicode.Scalar(v)!))]))
            switch v {
            case 0x09: expected.append(KeyEvent(key: .tab))
            case 0x0A: expected.append(KeyEvent(key: .enter))
            case 0x0D: expected.append(KeyEvent(key: .enter))
            default:
                expected.append(KeyEvent(
                    key: .character(Character(Unicode.Scalar(v + 0x40)!)),
                    modifiers: .ctrl
                ))
            }
        }
        #expect(events == expected)
    }

    @Test("Ctrl+Space / Ctrl+@")
    func testCtrlSpace() {
        let events = parser.parse([.character("\u{00}")])
        #expect(events == [KeyEvent(key: .character("@"), modifiers: .ctrl)])
    }

    @Test("Enter, Tab, Backspace, Escape from characters")
    func testSpecialCharacters() {
        let events = parser.parse([
            .character("\r"),
            .character("\n"),
            .character("\t"),
            .character("\u{7F}"),
            .character("\u{1B}"),
        ])
        #expect(events == [
            KeyEvent(key: .enter),
            KeyEvent(key: .enter),
            KeyEvent(key: .tab),
            KeyEvent(key: .backspace),
            KeyEvent(key: .escape),
        ])
    }

    @Test("Shift+Tab via CSI Z")
    func testShiftTab() {
        let events = parser.parse([.csi(params: [], command: "Z")])
        #expect(events == [KeyEvent(key: .tab, modifiers: .shift)])
    }

    // MARK: - Alt combinations

    @Test("Alt+character via escape sequence")
    func testAltCharacter() {
        let events = parser.parse([
            .escape(command: "x"),
            .escape(command: "X"),
            .escape(command: "1"),
        ])
        #expect(events == [
            KeyEvent(key: .character("x"), modifiers: .alt),
            KeyEvent(key: .character("X"), modifiers: .alt),
            KeyEvent(key: .character("1"), modifiers: .alt),
        ])
    }

    // MARK: - Byte fallback

    @Test("raw bytes mapped to control characters")
    func testByteFallback() {
        let events = parser.parse([
            .byte(0x0D),
            .byte(0x09),
            .byte(0x7F),
            .byte(0x01),
        ])
        #expect(events == [
            KeyEvent(key: .enter),
            KeyEvent(key: .tab),
            KeyEvent(key: .backspace),
            KeyEvent(key: .character("A"), modifiers: .ctrl),
        ])
    }

    // MARK: - Unknown / ignored sequences

    @Test("unknown CSI sequences are dropped")
    func testUnknownCSI() {
        let events = parser.parse([
            .csi(params: [1, 2, 3], command: "X"),
        ])
        #expect(events.isEmpty)
    }

    @Test("unknown SS3 final falls back to separate units")
    func testUnknownSS3() {
        let events = parser.parse([
            .escape(command: "O"), .character("Z"),
        ])
        // SS3 Z 未被映射，因此 ESC O 作为 Alt+O，Z 作为普通字符
        #expect(events == [
            KeyEvent(key: .character("O"), modifiers: .alt),
            KeyEvent(key: .character("Z")),
        ])
    }

    // MARK: - End-to-end with ByteStreamBuffer

    @Test("end-to-end: mixed stream through buffer and parser")
    func testEndToEndMixedStream() {
        let buf = ByteStreamBuffer()
        var allUnits: [InputUnit] = []
        allUnits.append(contentsOf: buf.feed([0x61, 0x1B, 0x5B, 0x41])) // 'a' + Up
        allUnits.append(contentsOf: buf.feed([0x0D]))                    // Enter
        allUnits.append(contentsOf: buf.feed([0x1B, 0x4F, 0x42]))       // SS3 Down
        allUnits.append(contentsOf: buf.feed([0x1B, 0x78]))              // Alt+x

        let events = parser.parse(allUnits)
        #expect(events == [
            KeyEvent(key: .character("a")),
            KeyEvent(key: .up),
            KeyEvent(key: .enter),
            KeyEvent(key: .down),
            KeyEvent(key: .character("x"), modifiers: .alt),
        ])
    }
}
