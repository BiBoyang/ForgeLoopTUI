import Darwin
import Testing
@testable import ForgeLoopTUI

@Suite("StdoutTerminal")
struct StdoutTerminalTests {

    // MARK: - Honest environment detection

    @Test("isTTY matches the real stdout state instead of a hardcoded true")
    func testIsTTYHonest() {
        #expect(StdoutTerminal().isTTY == (isatty(STDOUT_FILENO) != 0))
    }

    @Test("capability detection: non-TTY is plain")
    func testDetectNonTTY() {
        #expect(TerminalCapability.detect(isTTY: false, environment: [:]) == .plain)
        #expect(TerminalCapability.detect(
            isTTY: false,
            environment: ["COLORTERM": "truecolor"]
        ) == .plain)
    }

    @Test("capability detection: COLORTERM truecolor/24bit wins")
    func testDetectColorTerm() {
        #expect(TerminalCapability.detect(
            isTTY: true,
            environment: ["COLORTERM": "truecolor", "TERM": "xterm"]
        ) == .truecolor)
        #expect(TerminalCapability.detect(
            isTTY: true,
            environment: ["COLORTERM": "24bit"]
        ) == .truecolor)
    }

    @Test("capability detection: TERM fallback ladder")
    func testDetectTerm() {
        #expect(TerminalCapability.detect(
            isTTY: true,
            environment: ["TERM": "xterm-256color"]
        ) == .ansi256)
        #expect(TerminalCapability.detect(
            isTTY: true,
            environment: ["TERM": "xterm"]
        ) == .ansi16)
        #expect(TerminalCapability.detect(
            isTTY: true,
            environment: ["TERM": "dumb"]
        ) == .plain)
        // TTY without any environment info: conservative ansi16.
        #expect(TerminalCapability.detect(isTTY: true, environment: [:]) == .ansi16)
    }

    // MARK: - Write failure reporting

    @Test("write to a closed fd reports EBADF instead of failing silently")
    func testWriteFailureReturnsErrno() {
        let fd = open("/dev/null", O_WRONLY)
        #expect(fd >= 0)
        #expect(close(fd) == 0)

        let failure = writeToFileDescriptor(fd, "hello")

        #expect(failure == EBADF)
    }

    @Test("successful write returns nil")
    func testWriteSuccessReturnsNil() {
        let fd = open("/dev/null", O_WRONLY)
        #expect(fd >= 0)
        defer { close(fd) }

        #expect(writeToFileDescriptor(fd, "hello") == nil)
    }
}
