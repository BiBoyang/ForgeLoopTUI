import Foundation

import Darwin

/// Raw TTY lifecycle management: enters raw mode and restores the terminal
/// attributes on exit or failure.
///
/// `enter()` also pushes the kitty keyboard progressive-enhancement flag
/// `disambiguate escape codes` (`ESC[>1u`) so modified Enter (e.g.
/// Shift+Enter) arrives as a CSI-u sequence; `restore()` pops it (`ESC[<u`)
/// on every exit path (`stop()`, `withRawTTY` defer, `deinit`). The
/// sequences go to stdout — the channel `StdoutTerminal` already uses — not
/// to the input fd: writing them to the input fd would make a later
/// `tcsetattr(TCSAFLUSH)` block until the output queue drains. Terminals
/// without kitty support absorb both sequences silently.
///
/// Usage (RAII style):
/// ```swift
/// let tty = RawTTY()
/// try tty.enter()
/// defer { tty.restore() }
/// // ... read raw input ...
/// ```
///
/// Usage (closure style):
/// ```swift
/// try withRawTTY { tty in
///     // ... read raw input ...
/// }
/// ```
public final class RawTTY: @unchecked Sendable {
    public let fd: Int32
    private let lock = NSLock()
    private var originalTermios: termios?
    private var onRestoreFailureStorage: (@Sendable (Int32) -> Void)?

    /// kitty 键盘增强协议（progressive enhancement）控制序列：
    /// `enter()` 时 push `disambiguate escape codes`（flag 1），`restore()` 时 pop。
    /// 不支持该协议的终端会静默吸收这两条未知 CSI，因此无条件启用是安全的。
    /// 写入失败不影响 raw mode 生命周期（尽力而为，协议只是增强）。
    private static let kittyKeyboardPush = "\u{1B}[>1u"
    private static let kittyKeyboardPop = "\u{1B}[<u"

    /// kitty 控制序列的输出 fd，默认 stdout（与 `StdoutTerminal` 同一通道）。
    /// 仅在该 fd 是 TTY 时写入。internal 以便测试注入（如 PTY slave）。
    let kittyControlFD: Int32

    /// Called with the failing `errno` when restoring termios via `tcsetattr`
    /// fails. `restore()` cannot throw (it also runs from `deinit`), so this
    /// hook is the failure-reporting channel. The callback fires while the
    /// lock is held; it must not call back into this instance.
    public var onRestoreFailure: (@Sendable (Int32) -> Void)? {
        get { lock.withLock { onRestoreFailureStorage } }
        set { lock.withLock { onRestoreFailureStorage = newValue } }
    }

    /// Creates a RawTTY manager.
    /// - Parameter fd: The target file descriptor, defaulting to `STDIN_FILENO`.
    public init(fd: Int32 = STDIN_FILENO) {
        self.fd = fd
        self.kittyControlFD = STDOUT_FILENO
    }

    /// 测试专用：指定 kitty 控制序列的输出 fd。
    init(fd: Int32, kittyControlFD: Int32) {
        self.fd = fd
        self.kittyControlFD = kittyControlFD
    }

    /// Saves the current terminal attributes and switches to raw mode.
    ///
    /// Throws `.notATTY` if fd is not a TTY.
    /// Throws the corresponding system error if getting/setting attributes fails.
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
        raw.c_iflag = withUTF8EraseFlag(raw.c_iflag)
        raw.c_oflag &= ~UInt(OPOST)
        raw.c_cflag |= UInt(CS8)
        withUnsafeMutableBytes(of: &raw.c_cc) { buf in
            buf.bindMemory(to: cc_t.self)[Int(VMIN)] = 0
            buf.bindMemory(to: cc_t.self)[Int(VTIME)] = 1
        }

        guard tcsetattr(fd, TCSAFLUSH, &raw) == 0 else {
            throw RawTTYError.unableToSetAttributes(errno: errno)
        }

        // 进入 raw mode 后开启 kitty 键盘协议，让 Shift+Enter 等组合键以
        // CSI-u 序列到达（KeyParser 负责解析）。尽力而为，失败不视为 enter 失败。
        Self.writeKittyControlSequence(Self.kittyKeyboardPush, to: kittyControlFD)
    }

    /// Restores the previously saved terminal attributes.
    ///
    /// If `enter()` was never called, or the attributes have already been
    /// restored, this method does nothing (idempotent).
    public func restore() {
        lock.withLock {
            guard var original = originalTermios else { return }
            if tcsetattr(fd, TCSAFLUSH, &original) != 0 {
                onRestoreFailureStorage?(errno)
            }
            originalTermios = nil
            Self.writeKittyControlSequence(Self.kittyKeyboardPop, to: kittyControlFD)
        }
    }

    /// 向控制 fd 写入 kitty 控制序列；目标不是 TTY 时跳过。
    private static func writeKittyControlSequence(_ sequence: String, to fd: Int32) {
        guard isatty(fd) == 1 else { return }
        _ = writeToFileDescriptor(fd, sequence)
    }

    deinit {
        restore()
    }
}

/// RawTTY error type.
public enum RawTTYError: Error, Equatable {
    case notATTY(fd: Int32)
    case alreadyEntered
    case unableToGetAttributes(errno: Int32)
    case unableToSetAttributes(errno: Int32)
}

/// Closure-based RawTTY lifecycle management.
///
/// `enter()` is called before entering the closure, and `restore()` is called
/// automatically after the closure returns (including when it throws).
public func withRawTTY<T>(fd: Int32 = STDIN_FILENO, body: (RawTTY) throws -> T) throws -> T {
    let tty = RawTTY(fd: fd)
    try tty.enter()
    defer { tty.restore() }
    return try body(tty)
}
