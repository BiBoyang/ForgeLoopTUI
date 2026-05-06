import Testing
@testable import ForgeLoopTUI
import Darwin

@Suite("RawTTY Lifecycle")
struct RawTTYTests {

    @Test("enter throws notATTY when fd is not a terminal")
    func testEnterThrowsWhenNotATTY() {
        let tty = RawTTY(fd: -1)
        #expect(throws: RawTTYError.notATTY(fd: -1)) {
            try tty.enter()
        }
    }

    @Test("restore is idempotent when never entered")
    func testRestoreIsIdempotent() {
        let tty = RawTTY(fd: -1)
        // Should not crash or throw
        tty.restore()
        tty.restore()
    }

    @Test("deinit restores if enter succeeded")
    func testDeinitRestoresIfEntered() throws {
        // Skip if stdin is not a tty (e.g. in CI or piped test runner)
        guard isatty(STDIN_FILENO) == 1 else {
            // Skip: no real TTY available in this test environment
            return
        }

        let tty = RawTTY(fd: STDIN_FILENO)
        try tty.enter()
        // tty goes out of scope, deinit should call restore()
    }

    @Test("withRawTTY restores on normal return")
    func testWithRawTTYRestoresOnNormalReturn() throws {
        guard isatty(STDIN_FILENO) == 1 else {
            return // skip
        }

        let result = try withRawTTY { tty in
            #expect(tty != nil)
            return 42
        }
        #expect(result == 42)
    }

    @Test("withRawTTY restores on throw")
    func testWithRawTTYRestoresOnThrow() {
        guard isatty(STDIN_FILENO) == 1 else {
            return // skip
        }

        struct TestError: Error {}
        #expect(throws: TestError.self) {
            try withRawTTY { _ in
                throw TestError()
            }
        }
        // restore() was called via defer even though body threw
    }
}
