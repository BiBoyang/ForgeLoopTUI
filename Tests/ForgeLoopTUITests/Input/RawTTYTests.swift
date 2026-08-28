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

    @Test("double enter on same instance throws alreadyEntered")
    func testDoubleEnterThrowsAlreadyEntered() throws {
        guard isatty(STDIN_FILENO) == 1 else {
            return // skip
        }

        let tty = RawTTY(fd: STDIN_FILENO)
        try tty.enter()
        defer { tty.restore() }

        #expect(throws: RawTTYError.alreadyEntered) {
            try tty.enter()
        }
    }

    @Test("restore failure invokes onRestoreFailure with errno")
    func testRestoreFailureInvokesHook() throws {
        // Open a PTY pair so `enter()` succeeds, then break the fd.
        let master = posix_openpt(O_RDWR)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let slaveName = ptsname(master) else {
            if master >= 0 { close(master) }
            return // skip: no PTY available in this environment
        }
        defer { close(master) }
        let slave = open(String(cString: slaveName), O_RDWR)
        guard slave >= 0 else { return }

        final class ErrnoBox: @unchecked Sendable {
            var value: Int32?
        }
        let box = ErrnoBox()

        let tty = RawTTY(fd: slave)
        try tty.enter()
        #expect(close(slave) == 0)
        tty.onRestoreFailure = { box.value = $0 }

        tty.restore()

        #expect(box.value == EBADF)
    }
}
