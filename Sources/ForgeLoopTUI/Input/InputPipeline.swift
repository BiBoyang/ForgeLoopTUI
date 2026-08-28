import Foundation

/// Input pipeline: integrates byte buffering, key parsing, bracketed paste
/// aggregation, and ESC timeout handling.
///
/// Exposes a unified `feed(_:) -> [KeyEvent]` and `tick() -> [KeyEvent]`
/// interface, hiding the details of `ByteStreamBuffer` and `KeyParser`.
///
/// ## Bracketed paste
/// Detecting `ESC[200~` enters paste mode; all subsequent `InputUnit`s are
/// aggregated as plain text. Detecting `ESC[201~` exits paste mode and emits
/// `.paste(String)`.
///
/// ## ESC/Alt ambiguity
/// When ESC is pressed alone, the terminal only sends 0x1B, which
/// `ByteStreamBuffer` retains as an incomplete sequence. `InputPipeline`
/// starts a timeout when it detects an incomplete ESC; if no further bytes
/// arrive before the timeout, calling `tick()` triggers `flush()` to emit the
/// ESC as `.escape`. If subsequent bytes arrive within the window, the
/// sequence is parsed normally as Alt+character or CSI.
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
        clock: (any InputClock)? = nil,
        escapeTimeoutNanoseconds: UInt64 = 50_000_000
    ) {
        self.clock = clock ?? SystemInputClock()
        self.escapeTimeoutNanoseconds = escapeTimeoutNanoseconds
    }

    /// Feeds raw bytes and returns the parsed key events.
    public func feed(_ bytes: [UInt8]) -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        var events = checkTimeoutLocked()
        let units = buffer.feed(bytes)
        events.append(contentsOf: processLocked(units))
        updateTimeoutLocked()
        return events
    }

    /// Checks the timeout. If there is an incomplete ESC that has timed out,
    /// triggers a flush and returns the corresponding events.
    public func tick() -> [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        return checkTimeoutLocked()
    }

    /// Forces the pipeline to drain. An unclosed paste is emitted as
    /// `.paste(String)`; an incomplete ESC is flushed as `.escape`.
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
