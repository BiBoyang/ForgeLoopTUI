import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Raw TTY 生命周期管理：进入 raw mode 并在退出/异常时恢复终端属性。
///
/// 用法（RAII 模式）：
/// ```swift
/// let tty = RawTTY()
/// try tty.enter()
/// defer { tty.restore() }
/// // ... 读取原始输入 ...
/// ```
///
/// 用法（闭包模式）：
/// ```swift
/// try withRawTTY { tty in
///     // ... 读取原始输入 ...
/// }
/// ```
public final class RawTTY: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var originalTermios: termios?

    /// 创建 RawTTY 管理器。
    /// - Parameter fd: 目标文件描述符，默认 `STDIN_FILENO`。
    public init(fd: Int32 = STDIN_FILENO) {
        self.fd = fd
    }

    /// 保存当前终端属性并切换到 raw mode。
    ///
    /// 若 fd 不是 TTY，抛出 `.notATTY`。
    /// 若获取/设置属性失败，抛出对应的系统错误。
    public func enter() throws {
        lock.lock()
        defer { lock.unlock() }

        guard originalTermios == nil else {
            throw RawTTYError.alreadyEntered
        }

        guard isatty(fd) == 1 else {
            throw RawTTYError.notATTY(fd: fd)
        }

        var raw = termios()
        guard tcgetattr(fd, &raw) == 0 else {
            throw RawTTYError.unableToGetAttributes(errno: errno)
        }
        originalTermios = raw

        // 最小 raw mode：关闭回显和规范模式
        raw.c_lflag &= ~UInt(ECHO | ICANON | IEXTEN | ISIG)
        raw.c_iflag &= ~UInt(IXON | ICRNL | INPCK | ISTRIP)
        raw.c_oflag &= ~UInt(OPOST)
        raw.c_cflag |= UInt(CS8)
        withUnsafeMutableBytes(of: &raw.c_cc) { buf in
            buf.bindMemory(to: cc_t.self)[Int(VMIN)] = 0
            buf.bindMemory(to: cc_t.self)[Int(VTIME)] = 1
        }

        guard tcsetattr(fd, TCSAFLUSH, &raw) == 0 else {
            throw RawTTYError.unableToSetAttributes(errno: errno)
        }
    }

    /// 恢复之前保存的终端属性。
    ///
    /// 若从未调用过 `enter()`，或已经恢复过，此方法无操作（幂等）。
    public func restore() {
        lock.withLock {
            guard var original = originalTermios else { return }
            _ = tcsetattr(fd, TCSAFLUSH, &original)
            originalTermios = nil
        }
    }

    deinit {
        restore()
    }
}

/// RawTTY 错误类型。
public enum RawTTYError: Error, Equatable {
    case notATTY(fd: Int32)
    case alreadyEntered
    case unableToGetAttributes(errno: Int32)
    case unableToSetAttributes(errno: Int32)
}

/// 闭包形式的 RawTTY 生命周期管理。
///
/// `enter()` 在进入闭包前调用，闭包返回后自动调用 `restore()`（包括抛异常时）。
public func withRawTTY<T>(fd: Int32 = STDIN_FILENO, body: (RawTTY) throws -> T) throws -> T {
    let tty = RawTTY(fd: fd)
    try tty.enter()
    defer { tty.restore() }
    return try body(tty)
}
