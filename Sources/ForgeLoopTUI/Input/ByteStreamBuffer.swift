import Foundation

/// 字节流缓冲器：将分片到达的字节流解析为结构化的输入单元。
///
/// 支持跨 `feed()` 调用的不完整序列拼接：
/// - CSI 控制序列（`ESC[` ... final）
/// - UTF-8 多字节字符
///
/// 用法：
/// ```swift
/// let buf = ByteStreamBuffer()
/// let units1 = buf.feed([0x1B])        // 空，ESC 不完整
/// let units2 = buf.feed([0x5B, 0x41])  // [CSI(params: [], command: "A")]
/// let units3 = buf.flush()             // 清空剩余缓冲
/// ```
public final class ByteStreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8] = []

    public init() {}

    /// 喂入一个字节块，返回已完整解析的输入单元。
    ///
    /// 不完整的 ESC 序列或 UTF-8 字符会被保留在内部缓冲中，
    /// 等待下一次 `feed` 或 `flush` 处理。
    public func feed(_ bytes: [UInt8]) -> [InputUnit] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: bytes)
        return parseComplete()
    }

    /// 强制清空当前缓冲，将所有剩余字节尽可能解析后返回。
    ///
    /// 不完整的 UTF-8 序列会被替换为 `\u{FFFD}`（�），
    /// 无法解析的 ESC 前缀会被当作原始字节输出。
    public func flush() -> [InputUnit] {
        lock.lock()
        defer { lock.unlock() }
        let units = parseAll()
        buffer.removeAll()
        return units
    }

    // MARK: - Private

    /// 只解析当前缓冲中已完整的单元，保留尾部不完整数据。
    private func parseComplete() -> [InputUnit] {
        var units: [InputUnit] = []
        var i = 0

        while i < buffer.count {
            if let (unit, length) = parseUnit(at: i, allowIncomplete: false) {
                units.append(unit)
                i += length
            } else {
                break
            }
        }

        buffer.removeFirst(i)
        return units
    }

    /// 解析缓冲中的所有字节，包括不完整序列（用替换字符或原始字节兜底）。
    private func parseAll() -> [InputUnit] {
        var units: [InputUnit] = []
        var i = 0

        while i < buffer.count {
            if let (unit, length) = parseUnit(at: i, allowIncomplete: false) {
                units.append(unit)
                i += length
            } else if let (char, length) = parseUTF8(at: i, allowIncomplete: true) {
                units.append(.character(char))
                i += length
            } else {
                // 无法解析，输出原始字节
                units.append(.byte(buffer[i]))
                i += 1
            }
        }

        return units
    }

    private func parseUnit(at i: Int, allowIncomplete: Bool) -> (InputUnit, Int)? {
        guard i < buffer.count else { return nil }

        if buffer[i] == 0x1B {
            return parseEscape(at: i, allowIncomplete: allowIncomplete)
        }

        if let (char, length) = parseUTF8(at: i, allowIncomplete: allowIncomplete) {
            return (.character(char), length)
        }
        return nil
    }

    private func parseEscape(at i: Int, allowIncomplete: Bool) -> (InputUnit, Int)? {
        guard buffer[i] == 0x1B else { return nil }

        if i + 1 >= buffer.count {
            return allowIncomplete ? (.character(Character(Unicode.Scalar(0x1B))), 1) : nil
        }

        let next = buffer[i + 1]
        if next == 0x5B { // '['
            if let result = parseCSI(at: i, allowIncomplete: allowIncomplete) {
                return result
            }
            // parseCSI 失败（非法字节或不完整），flush 时回退为 ESC 字节
            return allowIncomplete ? (.character(Character(Unicode.Scalar(0x1B))), 1) : nil
        }

        return (.escape(command: Character(Unicode.Scalar(next))), 2)
    }

    private func parseCSI(at i: Int, allowIncomplete: Bool) -> (InputUnit, Int)? {
        // ESC [ ... final
        var j = i + 2 // 跳过 ESC [
        while j < buffer.count {
            let byte = buffer[j]
            if (0x40...0x7E).contains(byte) {
                let params = parseCSIParams(Array(buffer[(i + 2)..<j]))
                let command = Character(Unicode.Scalar(byte))
                return (.csi(params: params, command: command), j - i + 1)
            } else if (0x30...0x3F).contains(byte) {
                j += 1
            } else {
                // CSI 中遇到非法字节：如果允许不完整，输出 ESC 和 [ 作为字节
                return allowIncomplete ? nil : nil
            }
        }
        return allowIncomplete ? (.byte(0x1B), 1) : nil
    }

    private func parseCSIParams(_ bytes: [UInt8]) -> [Int] {
        guard let string = String(bytes: bytes, encoding: .ascii) else { return [] }
        return string.split(separator: ";").compactMap { Int($0) }
    }

    private func parseUTF8(at i: Int, allowIncomplete: Bool) -> (Character, Int)? {
        guard i < buffer.count else { return nil }
        let first = buffer[i]

        let expectedLength: Int
        if first & 0x80 == 0 {
            expectedLength = 1
        } else if first & 0xE0 == 0xC0 {
            expectedLength = 2
        } else if first & 0xF0 == 0xE0 {
            expectedLength = 3
        } else if first & 0xF8 == 0xF0 {
            expectedLength = 4
        } else {
            // 非法 UTF-8 起始字节
            return allowIncomplete ? (Character(Unicode.Scalar(first)), 1) : nil
        }

        if i + expectedLength <= buffer.count {
            let bytes = Array(buffer[i..<i + expectedLength])
            if let string = String(bytes: bytes, encoding: .utf8), let char = string.first {
                return (char, expectedLength)
            }
            // 字节组合无效但长度足够
            return allowIncomplete ? ("\u{FFFD}", expectedLength) : nil
        }

        if allowIncomplete {
            // 尝试用可用字节解析，如果失败则用替换字符
            let available = Array(buffer[i..<buffer.count])
            let decoded = String(decoding: Data(available), as: UTF8.self)
            if let char = decoded.first {
                return (char, available.count)
            }
            return ("\u{FFFD}", 1)
        }

        return nil
    }
}

/// 输入单元：字节流解析后的结构化事件。
public enum InputUnit: Sendable, Equatable {
    /// 可打印字符（含 UTF-8 多字节解析结果）。
    case character(Character)
    /// CSI 控制序列。
    case csi(params: [Int], command: Character)
    /// 非 CSI 的 Escape 序列（如 ESC O）。
    case escape(command: Character)
    /// 无法解析的原始字节（仅在 `flush()` 兜底时出现）。
    case byte(UInt8)
}
