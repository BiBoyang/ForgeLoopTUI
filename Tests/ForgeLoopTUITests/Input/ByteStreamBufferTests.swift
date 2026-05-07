import Testing
@testable import ForgeLoopTUI

@Suite("ByteStreamBuffer")
struct ByteStreamBufferTests {

    // MARK: - Plain ASCII

    @Test("plain ASCII characters are emitted immediately")
    func testPlainASCII() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0x41, 0x42, 0x43]) // "ABC"
        #expect(units.count == 3)
        #expect(units[0] == .character("A"))
        #expect(units[1] == .character("B"))
        #expect(units[2] == .character("C"))
    }

    // MARK: - CSI sequences

    @Test("complete CSI sequence is parsed in one feed")
    func testCompleteCSI() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0x1B, 0x5B, 0x41]) // ESC [ A
        #expect(units.count == 1)
        #expect(units[0] == .csi(params: [], command: "A"))
    }

    @Test("CSI with parameters is parsed correctly")
    func testCSIWithParams() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0x1B, 0x5B, 0x31, 0x3B, 0x33, 0x6D]) // ESC[1;3m
        #expect(units.count == 1)
        #expect(units[0] == .csi(params: [1, 3], command: "m"))
    }

    @Test("ESC split across two feeds")
    func testSplitESC() {
        let buf = ByteStreamBuffer()
        let u1 = buf.feed([0x1B])
        #expect(u1.isEmpty)

        let u2 = buf.feed([0x5B, 0x41]) // [ A
        #expect(u2.count == 1)
        #expect(u2[0] == .csi(params: [], command: "A"))
    }

    @Test("CSI params split across feeds")
    func testSplitCSIParams() {
        let buf = ByteStreamBuffer()
        let u1 = buf.feed([0x1B, 0x5B, 0x31]) // ESC[1
        #expect(u1.isEmpty)

        let u2 = buf.feed([0x3B, 0x33, 0x6D]) // ;3m
        #expect(u2.count == 1)
        #expect(u2[0] == .csi(params: [1, 3], command: "m"))
    }

    @Test("final byte split across feeds")
    func testSplitFinalByte() {
        let buf = ByteStreamBuffer()
        let u1 = buf.feed([0x1B, 0x5B, 0x32]) // ESC[2
        #expect(u1.isEmpty)

        let u2 = buf.feed([0x4A]) // J
        #expect(u2.count == 1)
        #expect(u2[0] == .csi(params: [2], command: "J"))
    }

    // MARK: - UTF-8

    @Test("complete UTF-8 character is emitted immediately")
    func testCompleteUTF8() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0xE4, 0xB8, 0xAD]) // 中
        #expect(units.count == 1)
        #expect(units[0] == .character("中"))
    }

    @Test("UTF-8 split across two feeds")
    func testSplitUTF8() {
        let buf = ByteStreamBuffer()
        let u1 = buf.feed([0xE4, 0xB8]) // first 2 bytes of 中
        #expect(u1.isEmpty)

        let u2 = buf.feed([0xAD]) // final byte
        #expect(u2.count == 1)
        #expect(u2[0] == .character("中"))
    }

    @Test("mixed ASCII and UTF-8")
    func testMixedASCIIAndUTF8() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0x41, 0xE4, 0xB8, 0xAD, 0x42]) // A中B
        #expect(units.count == 3)
        #expect(units[0] == .character("A"))
        #expect(units[1] == .character("中"))
        #expect(units[2] == .character("B"))
    }

    // MARK: - Flush

    @Test("flush emits incomplete CSI as raw bytes")
    func testFlushIncompleteCSI() {
        let buf = ByteStreamBuffer()
        _ = buf.feed([0x1B, 0x5B, 0x32]) // ESC[2 (no final)
        let units = buf.flush()
        // flush: ESC falls back to character, '[' and '2' are parsed as ASCII
        #expect(units.count == 3)
        #expect(units[0] == .character("\u{1B}"))
        #expect(units[1] == .character("["))
        #expect(units[2] == .character("2"))
    }

    @Test("flush emits incomplete UTF-8 as replacement character")
    func testFlushIncompleteUTF8() {
        let buf = ByteStreamBuffer()
        _ = buf.feed([0xE4, 0xB8]) // incomplete 中
        let units = buf.flush()
        #expect(units.count == 1)
        #expect(units[0] == .character("\u{FFFD}"))
    }

    @Test("flush is idempotent when buffer is empty")
    func testFlushIdempotent() {
        let buf = ByteStreamBuffer()
        let u1 = buf.flush()
        let u2 = buf.flush()
        #expect(u1.isEmpty)
        #expect(u2.isEmpty)
    }

    @Test("flush after complete parse leaves empty buffer")
    func testFlushAfterCompleteParse() {
        let buf = ByteStreamBuffer()
        let u1 = buf.feed([0x41, 0x42]) // "AB"
        #expect(u1.count == 2)
        let u2 = buf.flush()
        #expect(u2.isEmpty)
    }

    // MARK: - Escape sequences

    @Test("non-CSI escape sequence is parsed")
    func testNonCSIEscape() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0x1B, 0x4F]) // ESC O
        #expect(units.count == 1)
        #expect(units[0] == .escape(command: "O"))
    }

    // MARK: - Complex splits

    @Test("ESC followed by non-CSI byte is parsed as escape sequence")
    func testEscapeNonCSI() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0x1B, 0x61]) // ESC a
        #expect(units.count == 1)
        #expect(units[0] == .escape(command: "a"))
    }

    @Test("ESC with illegal CSI content is consumed byte by byte in feed")
    func testESCIllegalCSIFallback() {
        let buf = ByteStreamBuffer()
        // ESC [ followed by illegal byte (0xE4) — not a valid CSI
        // ESC is emitted as raw byte, '[' as character; 0xE4 is incomplete UTF-8, buffered
        let u1 = buf.feed([0x1B, 0x5B, 0xE4])
        #expect(u1.count == 2)
        #expect(u1[0] == .byte(0x1B))
        #expect(u1[1] == .character("["))
        // On flush, the lone 0xE4 becomes a replacement character
        let flushed = buf.flush()
        #expect(flushed.count == 1)
        #expect(flushed[0] == .character("\u{FFFD}"))
    }

    @Test("illegal UTF-8 start byte does not block subsequent ASCII")
    func testIllegalByteDoesNotBlock() {
        let buf = ByteStreamBuffer()
        let units = buf.feed([0xFF, 0x41]) // 0xFF is illegal UTF-8 start, then 'A'
        #expect(units.count == 2)
        #expect(units[0] == .byte(0xFF))
        #expect(units[1] == .character("A"))
    }

    @Test("illegal CSI byte does not block subsequent ASCII")
    func testIllegalCSIDoesNotBlock() {
        let buf = ByteStreamBuffer()
        // ESC[E4A — 0xE4 is illegal in CSI, so ESC is consumed as raw byte.
        // '[' is a normal character. 0xE4 starts a UTF-8 sequence but 0x41 is
        // not a valid continuation byte, so 0xE4 is consumed as raw byte too.
        let units = buf.feed([0x1B, 0x5B, 0xE4, 0x41])
        #expect(units.count == 4)
        #expect(units[0] == .byte(0x1B))
        #expect(units[1] == .character("["))
        #expect(units[2] == .byte(0xE4))
        #expect(units[3] == .character("A"))
    }
}
