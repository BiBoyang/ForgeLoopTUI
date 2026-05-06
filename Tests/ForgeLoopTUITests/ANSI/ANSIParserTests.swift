import Testing
@testable import ForgeLoopTUI

@Suite("ANSIParser")
struct ANSIParserTests {

    // MARK: - Basic text passthrough

    @Test("plain text emits text events")
    func testPlainText() {
        var parser = ANSIParser()
        var chars: [Character] = []
        for scalar in "Hello".unicodeScalars {
            parser.feed(scalar) { event in
                if case .text(let c) = event { chars.append(c) }
            }
        }
        #expect(chars == ["H", "e", "l", "l", "o"])
    }

    // MARK: - Complete CSI sequences

    @Test("ESC[2J emits CSI event with params [2] and command J")
    func testClearScreenSequence() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[2J".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 1)
        if case .csi(let params, let intermediates, let command) = events.first {
            #expect(params == [2])
            #expect(intermediates.isEmpty)
            #expect(command == "J")
        } else {
            Issue.record("Expected CSI event")
        }
    }

    @Test("ESC[H emits CSI event with empty params")
    func testHomeSequence() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[H".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 1)
        if case .csi(let params, let intermediates, let command) = events.first {
            #expect(params.isEmpty)
            #expect(intermediates.isEmpty)
            #expect(command == "H")
        } else {
            Issue.record("Expected CSI event")
        }
    }

    @Test("SGR sequence is consumed and emits no text")
    func testSGRSequenceIgnored() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[7;1mX".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 2)
        if case .csi(let params, let intermediates, let command) = events[0] {
            #expect(params == [7, 1])
            #expect(intermediates.isEmpty)
            #expect(command == "m")
        } else {
            Issue.record("Expected CSI event for SGR")
        }
        if case .text(let c) = events[1] {
            #expect(c == "X")
        } else {
            Issue.record("Expected text event for X")
        }
    }

    // MARK: - Partial / chunked CSI sequences

    @Test("ESC split across two writes")
    func testPartialEscapeSequence() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []

        parser.feed("\u{1B}") { _ in }
        for scalar in "[2J".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }

        #expect(events.count == 1)
        if case .csi(let params, let intermediates, let command) = events.first {
            #expect(params == [2])
            #expect(intermediates.isEmpty)
            #expect(command == "J")
        } else {
            Issue.record("Expected CSI event")
        }
    }

    @Test("CSI parameters split across writes")
    func testPartialCSIParams() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []

        for scalar in "\u{1B}[1".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.isEmpty, "Incomplete CSI should emit nothing")

        for scalar in ";36m".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }

        #expect(events.count == 1)
        if case .csi(let params, let intermediates, let command) = events.first {
            #expect(params == [1, 36])
            #expect(intermediates.isEmpty)
            #expect(command == "m")
        } else {
            Issue.record("Expected CSI event")
        }
    }

    @Test("final byte split across writes")
    func testPartialFinalByte() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []

        for scalar in "\u{1B}[2".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.isEmpty)

        parser.feed("J") { events.append($0) }

        #expect(events.count == 1)
        if case .csi(let params, let intermediates, let command) = events.first {
            #expect(params == [2])
            #expect(intermediates.isEmpty)
            #expect(command == "J")
        } else {
            Issue.record("Expected CSI event")
        }
    }

    @Test("every byte of a sequence split individually")
    func testByteByByteReplay() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        let sequence = "\u{1B}[7;1mX"
        for scalar in sequence.unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 2)
    }

    // MARK: - VirtualTerminal integration with partial sequences

    @Test("VirtualTerminal handles SGR split across writes")
    func testVirtualTerminalPartialSGR() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("\u{1B}")
        vt.write("[")
        vt.write("1")
        vt.write(";")
        vt.write("3")
        vt.write("6")
        vt.write("m")
        vt.write("X")
        #expect(vt.buffer == "X")
    }

    @Test("VirtualTerminal handles clear screen split across writes")
    func testVirtualTerminalPartialClearScreen() {
        let vt = VirtualTerminal(width: 10, height: 5)
        vt.write("hello")
        vt.write("\u{1B}[2")
        vt.write("J")
        vt.write("X")
        #expect(vt.buffer == "X")
        #expect(vt.cursorRow == 0)
        #expect(vt.cursorCol == 1)
    }

    // MARK: - Intermediate bytes

    @Test("intermediate bytes are consumed without leaking text")
    func testIntermediateBytesAreConsumed() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[1 $H".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 1)
        if case .csi(let params, let intermediates, let command) = events.first {
            #expect(params == [1])
            #expect(intermediates == " $")
            #expect(command == "H")
        } else {
            Issue.record("Expected CSI event")
        }
    }

    @Test("intermediate buffer is cleared between back-to-back CSI sequences")
    func testIntermediateBufferClearedBetweenSequences() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[1 $H\u{1B}[2J".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 2)
        if case .csi(_, let intermediates1, _) = events[0] {
            #expect(intermediates1 == " $")
        } else {
            Issue.record("Expected first CSI event")
        }
        if case .csi(_, let intermediates2, _) = events[1] {
            #expect(intermediates2.isEmpty, "Second CSI should have no residual intermediates")
        } else {
            Issue.record("Expected second CSI event")
        }
    }

    @Test("illegal param after intermediate aborts sequence")
    func testParamAfterIntermediateAbortsSequence() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[1 $2 H".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        // intermediate 后遇到参数字节 '2'，序列被丢弃；
        // 接着 ' ' 和 'H' 在 ground 状态作为文本输出
        #expect(events.count == 2)
        if case .text(let c1) = events[0] {
            #expect(c1 == " ")
        } else {
            Issue.record("Expected text event for ' '")
        }
        if case .text(let c2) = events[1] {
            #expect(c2 == "H")
        } else {
            Issue.record("Expected text event for 'H'")
        }
    }

    // MARK: - Colon-style SGR

    @Test("colon-style SGR does not leak visible characters")
    func testColonStyleSGRDoesNotLeak() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[38:2:255:0:0mX".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 2)
        if case .csi(let params, _, let command) = events[0] {
            #expect(command == "m")
            // colon 被当作分隔符，参数被拆分后保留可解析部分
            #expect(params == [38, 2, 255, 0, 0])
        } else {
            Issue.record("Expected CSI event for SGR")
        }
        if case .text(let c) = events[1] {
            #expect(c == "X")
        } else {
            Issue.record("Expected text event for X")
        }
    }

    @Test("semicolon-and-colon mixed SGR preserves semicolon params")
    func testMixedSeparatorSGR() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[1;38:5:196;48:5:21mX".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 2)
        if case .csi(let params, _, let command) = events[0] {
            #expect(command == "m")
            // 分号与 colon 均作为分隔符，所有数字参数均被保留
            #expect(params == [1, 38, 5, 196, 48, 5, 21])
        } else {
            Issue.record("Expected CSI event")
        }
    }

    // MARK: - Edge cases

    @Test("consecutive ESC bytes are discarded")
    func testConsecutiveEscapeBytes() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}\u{1B}X".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 1)
        if case .text(let c) = events.first {
            #expect(c == "X")
        } else {
            Issue.record("Expected text event for X")
        }
    }

    @Test("ESC followed by non-CSI byte discards ESC and emits text")
    func testUnsupportedEscapeSequence() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}X".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        #expect(events.count == 1)
        if case .text(let c) = events.first {
            #expect(c == "X")
        } else {
            Issue.record("Expected text event for X")
        }
    }

    @Test("illegal byte inside CSI aborts sequence")
    func testIllegalByteInCSI() {
        var parser = ANSIParser()
        var events: [ANSIParser.Event] = []
        for scalar in "\u{1B}[1\u{00}X".unicodeScalars {
            parser.feed(scalar) { events.append($0) }
        }
        // NUL (0x00) is not a param, intermediate, nor final byte, so CSI is aborted.
        // 'X' is emitted as text.
        #expect(events.count == 1)
        if case .text(let c) = events.first {
            #expect(c == "X")
        } else {
            Issue.record("Expected text event for X")
        }
    }
}
