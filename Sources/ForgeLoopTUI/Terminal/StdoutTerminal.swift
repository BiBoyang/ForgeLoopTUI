import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public typealias FrameWriter = @Sendable (String) -> Void

/// 尽力把文本写入 fd，返回 nil 表示全部写完，否则返回中止写入的 errno。
/// 拆出 fd 参数是为了可对失败路径做单元测试（如对已关闭的 fd 写入）。
func writeToFileDescriptor(_ fd: Int32, _ text: String) -> Int32? {
    let data = Data(text.utf8)
    return data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return nil }
        var written = 0

        while written < rawBuffer.count {
            let pointer = baseAddress.advanced(by: written)
            let remaining = rawBuffer.count - written
            let result = Darwin.write(fd, pointer, remaining)

            if result > 0 {
                written += result
                continue
            }

            if result == -1 && errno == EINTR {
                continue
            }

            if result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                usleep(1_000)
                continue
            }

            return errno
        }
        return nil
    }
}

extension TerminalCapability {
    /// 基于 TTY 状态与环境变量（COLORTERM/TERM）的尽力能力探测。
    /// 纯函数，便于测试；真实环境传 `ProcessInfo.processInfo.environment`。
    static func detect(isTTY: Bool, environment: [String: String]) -> TerminalCapability {
        guard isTTY else { return .plain }
        if let colorTerm = environment["COLORTERM"]?.lowercased(),
           colorTerm == "truecolor" || colorTerm == "24bit" {
            return .truecolor
        }
        guard let term = environment["TERM"]?.lowercased() else {
            // TTY 但无 TERM 信息：保守给标准 16 色。
            return .ansi16
        }
        if term == "dumb" { return .plain }
        if term.contains("256color") { return .ansi256 }
        return .ansi16
    }
}

/// 默认终端实现：直接写入标准输出（stdout）。
public struct StdoutTerminal: Terminal {
    public var isTTY: Bool { isatty(STDOUT_FILENO) != 0 }
    public var capability: TerminalCapability {
        TerminalCapability.detect(isTTY: isTTY, environment: ProcessInfo.processInfo.environment)
    }

    /// Called with the failing `errno` when a stdout write cannot complete.
    /// `Terminal.write` cannot throw; this hook is the reporting channel
    /// (see `docs/known-limitations.md`).
    public var onWriteFailure: (@Sendable (Int32) -> Void)?

    public init() {}

    public func write(_ text: String) {
        if let failure = writeToFileDescriptor(STDOUT_FILENO, text) {
            onWriteFailure?(failure)
        }
    }
}
