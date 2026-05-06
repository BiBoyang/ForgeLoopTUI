import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public typealias FrameWriter = @Sendable (String) -> Void

func writeToStandardOutput(_ text: String) {
    let data = Data(text.utf8)
    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var written = 0

        while written < rawBuffer.count {
            let pointer = baseAddress.advanced(by: written)
            let remaining = rawBuffer.count - written
            let result = Darwin.write(STDOUT_FILENO, pointer, remaining)

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

            break
        }
    }
}

/// 默认终端实现：直接写入标准输出（stdout）。
public struct StdoutTerminal: Terminal {
    public var isTTY: Bool { true }

    public init() {}

    public func write(_ text: String) {
        writeToStandardOutput(text)
    }
}
