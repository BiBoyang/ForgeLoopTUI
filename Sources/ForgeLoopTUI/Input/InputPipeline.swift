import Foundation

/// 输入管道：整合字节缓冲、键值解析和 bracketed paste 聚合。
///
/// 对外暴露统一的 `feed(_:) -> [KeyEvent]` 接口，屏蔽 `ByteStreamBuffer`
/// 和 `KeyParser` 的细节。
///
/// Bracketed paste 支持：
/// - 检测到 `ESC[200~` 进入 paste 模式，后续所有 `InputUnit` 被聚合为纯文本。
/// - 检测到 `ESC[201~` 退出 paste 模式，输出单个 `.paste(String)` 事件。
/// - paste 区间内的 CSI/escape 序列会被还原为字面量字符串，不会被解析为方向键。
public final class InputPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer = ByteStreamBuffer()
    private let parser = KeyParser()
    private var isPasting = false
    private var pasteAccumulator = ""

    public init() {}

    /// 喂入原始字节，返回已解析的按键事件。
    public func feed(_ bytes: [UInt8]) -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        let units = buffer.feed(bytes)
        return process(units)
    }

    /// 强制清空管道。未闭合的 paste 会被输出为 `.paste(String)`。
    public func flush() -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        let units = buffer.flush()
        var events = process(units)
        if isPasting {
            isPasting = false
            events.append(KeyEvent(key: .paste(pasteAccumulator)))
            pasteAccumulator = ""
        }
        return events
    }

    // MARK: - Private

    private func process(_ units: [InputUnit]) -> [KeyEvent] {
        var events: [KeyEvent] = []
        var normalBuffer: [InputUnit] = []

        func flushNormal() {
            if !normalBuffer.isEmpty {
                events.append(contentsOf: parser.parse(normalBuffer))
                normalBuffer.removeAll()
            }
        }

        for unit in units {
            if isPasting {
                if isPasteEnd(unit) {
                    isPasting = false
                    events.append(KeyEvent(key: .paste(pasteAccumulator)))
                    pasteAccumulator = ""
                } else {
                    pasteAccumulator.append(contentsOf: unitToString(unit))
                }
            } else {
                if isPasteStart(unit) {
                    flushNormal()
                    isPasting = true
                    pasteAccumulator = ""
                } else {
                    normalBuffer.append(unit)
                }
            }
        }

        flushNormal()
        return events
    }

    private func isPasteStart(_ unit: InputUnit) -> Bool {
        if case .csi(params: [200], command: "~") = unit { return true }
        return false
    }

    private func isPasteEnd(_ unit: InputUnit) -> Bool {
        if case .csi(params: [201], command: "~") = unit { return true }
        return false
    }

    /// 将 `InputUnit` 还原为最接近原始字节的字符串表示。
    /// 用于 paste 区间内保留字面量内容。
    private func unitToString(_ unit: InputUnit) -> String {
        switch unit {
        case .character(let c):
            return String(c)
        case .byte(let b):
            return String(Character(Unicode.Scalar(b)))
        case .csi(let params, let command):
            let paramStr = params.map(String.init).joined(separator: ";")
            return "\u{1B}[\(paramStr)\(command)"
        case .escape(let command):
            return "\u{1B}\(command)"
        }
    }
}
