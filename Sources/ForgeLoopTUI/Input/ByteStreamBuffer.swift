import Foundation

/// 字节流缓冲器：将分片到达的字节流解析为结构化的输入单元。
///
/// 支持跨 `feed()` 调用的不完整序列拼接：
/// - CSI 控制序列（`ESC[` ... final）
/// - UTF-8 多字节字符
///
/// 错误恢复策略：非法字节不会阻塞后续输入，立即消费 1 字节输出 `.byte`，
/// 循环继续解析剩余数据。
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
    /// 非法字节立即被消费并输出为 `.byte`，不会阻塞后续合法输入。
    public func feed(_ bytes: [UInt8]) -> [InputUnit] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: bytes)
        return parseComplete()
    }

    /// 强制清空当前缓冲，将所有剩余字节尽可能解析后返回。
    ///
    /// 不完整的 UTF-8 序列会被替换为 `\u{FFFD}`（�），
    /// 不完整的 ESC 前缀会被当作普通字节输出。
    public func flush() -> [InputUnit] {
        lock.lock()
        defer { lock.unlock() }
        let units = parseAll()
        buffer.removeAll()
        return units
    }

    // MARK: - Private

    private enum ParseResult {
        case ok(unit: InputUnit, length: Int)
        case incomplete
        case invalid
    }

    /// 只解析当前缓冲中已完整的单元，保留尾部不完整数据。
    /// 非法字节立即消费 1 字节并继续，不会阻塞。
    private func parseComplete() -> [InputUnit] {
        var units: [InputUnit] = []
        var i = 0

        parseLoop: while i < buffer.count {
            switch parseUnit(at: i, allowIncomplete: false) {
            case .ok(let unit, let length):
                units.append(unit)
                i += length
            case .incomplete:
                break parseLoop
            case .invalid:
                units.append(.byte(buffer[i]))
                i += 1
            }
        }

        buffer.removeFirst(i)
        return units
    }

    /// 解析缓冲中的所有字节。不完整序列用替换字符或字节兜底。
    private func parseAll() -> [InputUnit] {
        var units: [InputUnit] = []
        var i = 0

        while i < buffer.count {
            switch parseUnit(at: i, allowIncomplete: false) {
            case .ok(let unit, let length):
                units.append(unit)
                i += length
            case .incomplete:
                // 尝试用 allowIncomplete=true 兜底
                switch parseUnit(at: i, allowIncomplete: true) {
                case .ok(let unit, let length):
                    units.append(unit)
                    i += length
                case .incomplete, .invalid:
                    units.append(.byte(buffer[i]))
                    i += 1
                }
            case .invalid:
                units.append(.byte(buffer[i]))
                i += 1
            }
        }

        return units
    }

    private func parseUnit(at i: Int, allowIncomplete: Bool) -> ParseResult {
        guard i < buffer.count else { return .incomplete }

        if buffer[i] == 0x1B {
            return parseEscape(at: i, allowIncomplete: allowIncomplete)
        }

        switch parseUTF8(at: i, allowIncomplete: allowIncomplete) {
        case .ok(let char, let length):
            return .ok(unit: .character(char), length: length)
        case .incomplete:
            return .incomplete
        case .invalid:
            return .invalid
        }
    }

    private func parseEscape(at i: Int, allowIncomplete: Bool) -> ParseResult {
        guard buffer[i] == 0x1B else { return .invalid }

        if i + 1 >= buffer.count {
            return allowIncomplete
                ? .ok(unit: .character(Character(Unicode.Scalar(0x1B))), length: 1)
                : .incomplete
        }

        let next = buffer[i + 1]
        if next == 0x5B { // '['
            return parseCSI(at: i, allowIncomplete: allowIncomplete)
        }

        return .ok(unit: .escape(command: Character(Unicode.Scalar(next))), length: 2)
    }

    private func parseCSI(at i: Int, allowIncomplete: Bool) -> ParseResult {
        var j = i + 2 // 跳过 ESC [
        while j < buffer.count {
            let byte = buffer[j]
            if (0x40...0x7E).contains(byte) {
                let params = parseCSIParams(Array(buffer[(i + 2)..<j]))
                return .ok(
                    unit: .csi(params: params, command: Character(Unicode.Scalar(byte))),
                    length: j - i + 1
                )
            } else if (0x30...0x3F).contains(byte) {
                j += 1
            } else {
                // CSI 中遇到非法字节
                return .invalid
            }
        }
        // 到 buffer 末尾仍无 final byte
        return allowIncomplete
            ? .ok(unit: .character(Character(Unicode.Scalar(0x1B))), length: 1)
            : .incomplete
    }

    private func parseCSIParams(_ bytes: [UInt8]) -> [Int] {
        guard let string = String(bytes: bytes, encoding: .ascii) else { return [] }
        return string.split(separator: ";").compactMap { Int($0) }
    }

    private enum UTF8ParseResult {
        case ok(Character, Int)
        case incomplete
        case invalid
    }

    private func parseUTF8(at i: Int, allowIncomplete: Bool) -> UTF8ParseResult {
        guard i < buffer.count else { return .incomplete }
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
            return .invalid
        }

        if i + expectedLength <= buffer.count {
            let bytes = Array(buffer[i..<i + expectedLength])
            if let string = String(bytes: bytes, encoding: .utf8), let char = string.first {
                return .ok(char, expectedLength)
            }
            return .invalid
        }

        // 长度不够：检查已有的 continuation bytes 是否有效
        // 如果任何 continuation byte 不在 0x80-0xBF 范围，说明不可能构成有效 UTF-8
        for k in (i + 1)..<buffer.count {
            if buffer[k] & 0xC0 != 0x80 {
                return .invalid
            }
        }

        if allowIncomplete {
            let available = Array(buffer[i..<buffer.count])
            let decoded = String(decoding: Data(available), as: UTF8.self)
            if let char = decoded.first {
                return .ok(char, available.count)
            }
            return .ok("\u{FFFD}", 1)
        }

        return .incomplete
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
    /// 无法解析的原始字节（非法输入或 `flush()` 兜底）。
    case byte(UInt8)
}
