import Foundation

import Darwin

/// Raw TTY lifecycle management: enters raw mode and restores the terminal
/// attributes on exit or failure.
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
        }
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
