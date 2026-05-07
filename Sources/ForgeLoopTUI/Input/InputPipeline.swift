import Foundation

/// 输入管道：整合字节缓冲、键值解析、bracketed paste 聚合和 ESC 超时处理。
///
/// 对外暴露统一的 `feed(_:) -> [KeyEvent]` 和 `tick() -> [KeyEvent]` 接口，
/// 屏蔽 `ByteStreamBuffer` 和 `KeyParser` 的细节。
///
/// ## Bracketed paste
/// 检测到 `ESC[200~` 进入 paste 模式，后续所有 `InputUnit` 被聚合为纯文本。
/// 检测到 `ESC[201~` 退出并输出 `.paste(String)`。
///
/// ## ESC/Alt 歧义
/// 单独按 ESC 时终端只发送 0x1B，`ByteStreamBuffer` 会将其保留为不完整序列。
/// `InputPipeline` 在检测到不完整 ESC 时启动超时；若超时前无后续字节到达，
/// 调用 `tick()` 会触发 `flush()` 将 ESC 作为 `.escape` 输出。
/// 若后续字节在窗口内到达，则正常解析为 Alt+字符 或 CSI。
public final class InputPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer = ByteStreamBuffer()
    private let parser = KeyParser()
    private let clock: any InputClock
    private let escapeTimeoutNanoseconds: UInt64
    private var pendingEscapeDeadline: UInt64?
    private var isPasting = false
    private var pasteAccumulator = ""

    public init(
        clock: any InputClock = SystemInputClock(),
        escapeTimeoutNanoseconds: UInt64 = 50_000_000
    ) {
        self.clock = clock
        self.escapeTimeoutNanoseconds = escapeTimeoutNanoseconds
    }

    /// 喂入原始字节，返回已解析的按键事件。
    public func feed(_ bytes: [UInt8]) -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        var events = checkTimeoutLocked()
        let units = buffer.feed(bytes)
        events.append(contentsOf: processLocked(units))
        updateTimeoutLocked()
        return events
    }

    /// 检查超时。若有不完整 ESC 且已超时，触发 flush 并返回对应事件。
    public func tick() -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        return checkTimeoutLocked()
    }

    /// 强制清空管道。未闭合的 paste 会被输出为 `.paste(String)`；
    /// 不完整的 ESC 会被 flush 为 `.escape`。
    public func flush() -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        // 若处于 paste 模式，先把 ByteStreamBuffer 中残留的尾部字节
        // 在当前 paste 语境下聚合，避免它们被当作普通按键解析。
        let units = buffer.flush()
        var events = processLocked(units)

        if isPasting {
            isPasting = false
            events.append(KeyEvent(key: .paste(pasteAccumulator)))
            pasteAccumulator = ""
        }
        pendingEscapeDeadline = nil
        return events
    }

    // MARK: - Private

    private func checkTimeoutLocked() -> [KeyEvent] {
        if let deadline = pendingEscapeDeadline, clock.now() >= deadline {
            pendingEscapeDeadline = nil
            let units = buffer.flush()
            return processLocked(units)
        }
        return []
    }

    private func updateTimeoutLocked() {
        if buffer.isPendingEscape {
            pendingEscapeDeadline = clock.now() + escapeTimeoutNanoseconds
        } else {
            pendingEscapeDeadline = nil
        }
    }

    private func processLocked(_ units: [InputUnit]) -> [KeyEvent] {
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
