import Foundation
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

    @Test("enter pushes kitty keyboard flags, restore pops them")
    func testKittyKeyboardPushPop() throws {
        // Open a PTY pair; bytes the library writes to the slave are
        // readable on the master side.
        let master = posix_openpt(O_RDWR)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let slaveName = ptsname(master) else {
            if master >= 0 { close(master) }
            return // skip: no PTY available in this environment
        }
        defer { close(master) }
        guard fcntl(master, F_SETFL, O_NONBLOCK) == 0 else { return }
        let slave = open(String(cString: slaveName), O_RDWR)
        guard slave >= 0 else { return }
        defer { close(slave) }

        let tty = RawTTY(fd: slave, kittyControlFD: slave)
        try tty.enter()
        #expect(readPTYMaster(master, timeout: 1.0) == "\u{1B}[>1u\u{1B}[?2004h")

        tty.restore()
        #expect(readPTYMaster(master, timeout: 1.0) == "\u{1B}[<u\u{1B}[?2004l")

        // restore 幂等：第二次 restore 不再写 pop
        tty.restore()
        #expect(readPTYMaster(master, timeout: 0.1).isEmpty)
    }

    @Test("enter enables bracketed paste mode, restore disables it")
    func testBracketedPasteEnableDisable() throws {
        // 与 kitty 测试同构：库写到 slave 的控制序列可从 master 侧读回。
        let master = posix_openpt(O_RDWR)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let slaveName = ptsname(master) else {
            if master >= 0 { close(master) }
            return // skip: no PTY available in this environment
        }
        defer { close(master) }
        guard fcntl(master, F_SETFL, O_NONBLOCK) == 0 else { return }
        let slave = open(String(cString: slaveName), O_RDWR)
        guard slave >= 0 else { return }
        defer { close(slave) }

        let tty = RawTTY(fd: slave, kittyControlFD: slave)
        try tty.enter()
        // enter 还会写 kitty push（ESC[>1u），这里只断言 bracketed paste 开关。
        #expect(readPTYMaster(master, timeout: 1.0).contains("\u{1B}[?2004h"))

        tty.restore()
        #expect(readPTYMaster(master, timeout: 1.0).contains("\u{1B}[?2004l"))
    }

    /// 非阻塞读取 PTY master：读到数据后 drain 完即返回，无数据则轮询至 timeout。
    private func readPTYMaster(_ master: Int32, timeout: TimeInterval) -> String {
        var bytes: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 64)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let n = read(master, &buf, buf.count)
            if n > 0 {
                bytes.append(contentsOf: buf[..<n])
            } else if n == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                if !bytes.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.005)
            } else {
                break
            }
        } while Date() < deadline
        return String(decoding: bytes, as: UTF8.self)
    }
}
