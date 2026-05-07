import Testing
@testable import ForgeLoopTUI

#if canImport(Darwin)
import Darwin
#endif

@Suite("InputReader Lifecycle")
struct InputReaderLifecycleTests {

    /// 在 macOS 上打开一对伪终端 fd（master / slave）。
    /// slave 端可通过 `isatty` 检查，用于测试 `RawTTY`/`InputReader`。
    private func openPTY() -> (master: Int32, slave: Int32)? {
        let master = posix_openpt(O_RDWR)
        guard master >= 0 else { return nil }
        guard grantpt(master) == 0 else { return nil }
        guard unlockpt(master) == 0 else { return nil }
        let name = String(cString: ptsname(master)!)
        let slave = open(name, O_RDWR)
        guard slave >= 0 else { return nil }
        return (master, slave)
    }

    @Test("start is idempotent when already running")
    func testStartIsIdempotent() throws {
        guard let pty = openPTY() else {
            Issue.record("Failed to open PTY")
            return
        }
        defer {
            close(pty.master)
            close(pty.slave)
        }

        let reader = InputReader(tty: RawTTY(fd: pty.slave), onEvent: { _ in })
        #expect(!reader.running)

        try reader.start()
        #expect(reader.running)

        // 第二次 start 应直接返回，不创建新的 source
        try reader.start()
        #expect(reader.running)

        reader.stop()
        #expect(!reader.running)
    }

    @Test("restart after stop re-enters raw mode")
    func testRestartAfterStop() throws {
        guard let pty = openPTY() else {
            Issue.record("Failed to open PTY")
            return
        }
        defer {
            close(pty.master)
            close(pty.slave)
        }

        let reader = InputReader(tty: RawTTY(fd: pty.slave), onEvent: { _ in })

        try reader.start()
        #expect(reader.running)

        reader.stop()
        #expect(!reader.running)

        // 再次 start 应成功重新进入 raw mode
        try reader.start()
        #expect(reader.running)

        reader.stop()
        #expect(!reader.running)
    }

    @Test("stop is idempotent when never started")
    func testStopIsIdempotent() {
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        defer {
            close(fds[0])
            close(fds[1])
        }

        let reader = InputReader(tty: RawTTY(fd: fds[0]), onEvent: { _ in })
        #expect(!reader.running)

        reader.stop() // 不应崩溃
        #expect(!reader.running)
    }

    @Test("start throws on non-TTY and does not leak source")
    func testStartThrowsOnNonTTY() {
        var fds: [Int32] = [0, 0]
        pipe(&fds)
        defer {
            close(fds[0])
            close(fds[1])
        }

        let reader = InputReader(tty: RawTTY(fd: fds[0]), onEvent: { _ in })
        #expect(!reader.running)

        #expect(throws: RawTTYError.notATTY(fd: fds[0])) {
            try reader.start()
        }

        #expect(!reader.running)
    }
}
