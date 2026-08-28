import Foundation

/// A byte-stream buffer that parses incrementally arriving bytes into structured input units.
///
/// Supports reassembling sequences split across `feed()` calls:
/// - CSI control sequences (`ESC[` ... final)
/// - UTF-8 multi-byte characters
///
/// Error recovery: invalid bytes never block subsequent input; 1 byte is consumed immediately
/// and emitted as `.byte`, then parsing continues with the remaining data.
///
/// Usage:
/// ```swift
/// let buf = ByteStreamBuffer()
/// let units1 = buf.feed([0x1B])        // empty; ESC is incomplete
/// let units2 = buf.feed([0x5B, 0x41])  // [CSI(params: [], command: "A")]
/// let units3 = buf.flush()             // drains the remaining buffer
/// ```
public final class ByteStreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8] = []

    public init() {}

    /// Feeds a chunk of bytes and returns the fully parsed input units.
    ///
    /// Incomplete ESC sequences or UTF-8 characters are kept in the internal buffer,
    /// awaiting the next `feed` or `flush`.
    /// Invalid bytes are consumed immediately and emitted as `.byte`; they never block later valid input.
    public func feed(_ bytes: [UInt8]) -> [InputUnit] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: bytes)
        return parseComplete()
    }

    /// Forces the current buffer to drain, parsing all remaining bytes as far as possible.
    ///
    /// Incomplete UTF-8 sequences are replaced with `\u{FFFD}` (),
    /// incomplete ESC prefixes are emitted as plain bytes.
    public func flush() -> [InputUnit] {
        lock.lock()
        defer { lock.unlock() }
        let units = parseAll()
        buffer.removeAll()
        return units
    }

    /// Whether the buffer currently starts with an incomplete ESC (used by the ESC/Alt disambiguation timer).
    public var isPendingEscape: Bool {
        lock.lock(); defer { lock.unlock() }
        return buffer.first == 0x1B
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
        // 与 `ANSIParser` 共用同一参数解析，分隔符规则天然一致。
        return parseCSIParameters(string)
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

/// An input unit: a structured event produced by byte-stream parsing.
public enum InputUnit: Sendable, Equatable {
    /// A printable character (including the result of UTF-8 multi-byte parsing).
    case character(Character)
    /// A CSI control sequence. Empty parameters in `params` are recorded as 0 (default-value semantics)
    /// and `:` sub-parameters are flattened, matching the rules of `ANSIParser.Event.csi`.
    case csi(params: [Int], command: Character)
    /// A non-CSI escape sequence (e.g. ESC O).
    case escape(command: Character)
    /// An unparseable raw byte (invalid input or a `flush()` fallback).
    case byte(UInt8)
}
