import Foundation
/// 将旧版 `FrameWriter` 桥接到 `Terminal` 协议的内部适配器。
private struct WriterTerminal: Terminal {
    let isTTY: Bool
    let capability: TerminalCapability
    let writer: FrameWriter

    func write(_ text: String) {
        writer(text)
    }
}

public final class TUI: @unchecked Sendable {
    public let strategy: RenderStrategy
    public let isTTY: Bool
    public let liveBudget: Int
    public private(set) var terminalWidth: Int
    public private(set) var terminalHeight: Int
    private let terminal: Terminal

    private let lock = NSLock()
    private var previousLines: [String] = []
    private var lastFramePhysicalRows: Int = 0
    private var lastCursorAnchored: Bool = false
    private var lastCursorOffset: Int = 0
    private let ttyNewline = "\r\n"

    // MARK: - Commit / Live state
    private var committedLines: [String] = []
    private var lastCommittedPhysicalRows: Int = 0
    private var previousLiveLines: [String] = []
    private var lastLivePhysicalRows: Int = 0

    public init(
        strategy: RenderStrategy? = nil,
        isTTY: Bool? = nil,
        terminalWidth: Int = 80,
        terminalHeight: Int = 24,
        liveBudget: Int = 0,
        terminal: Terminal? = nil,
        writer: FrameWriter? = nil
    ) {
        self.liveBudget = liveBudget
        let resolvedStrategy: RenderStrategy
        if let strategy {
            resolvedStrategy = strategy
        } else if
            let env = ProcessInfo.processInfo.environment["FORGELOOP_TUI_STRATEGY"],
            env.lowercased() == "legacy"
        {
            resolvedStrategy = .legacyAbsolute
        } else {
            resolvedStrategy = .inlineAnchor
        }

        self.strategy = resolvedStrategy
        self.terminalWidth = terminalWidth
        self.terminalHeight = terminalHeight

        if let terminal {
            self.terminal = terminal
            self.isTTY = isTTY ?? terminal.isTTY
        } else if let writer {
            let resolvedTTY = isTTY ?? true
            self.terminal = WriterTerminal(isTTY: resolvedTTY, capability: .truecolor, writer: writer)
            self.isTTY = resolvedTTY
        } else {
            let resolvedTTY = isTTY ?? true
            self.terminal = StdoutTerminal()
            self.isTTY = resolvedTTY
        }
    }

    public func updateTerminalSize(width: Int, height: Int? = nil) {
        lock.withLock {
            terminalWidth = width
            if let height {
                terminalHeight = height
            }
            // M4-S5: Recompute cached physical rows with new width
            // so that next-frame diff uses correct cursor math.
            lastFramePhysicalRows = totalPhysicalRows(for: previousLines)
            lastCommittedPhysicalRows = totalPhysicalRows(for: committedLines)
            lastLivePhysicalRows = totalPhysicalRows(for: previousLiveLines)
        }
    }

    public func invalidate() {}

    public func requestRender(lines: [String], cursorOffset: Int? = nil) {
        let normalizedLines = splitLogicalLines(lines)

        if !isTTY {
            var output = normalizedLines.joined(separator: "\n")
            if !normalizedLines.isEmpty && cursorOffset == nil {
                output += "\n"
            }
            terminal.write(output)
            return
        }

        switch strategy {
        case .legacyAbsolute:
            syncRetainedState(lines: normalizedLines, committed: normalizedLines, live: [], cursorOffset: cursorOffset)
            renderLegacy(lines: normalizedLines, cursorOffset: cursorOffset)
        case .inlineAnchor:
            if shouldFallbackToFullRedraw(for: normalizedLines) {
                syncRetainedState(lines: normalizedLines, committed: normalizedLines, live: [], cursorOffset: cursorOffset)
                renderLegacy(lines: normalizedLines, cursorOffset: cursorOffset)
            } else {
                renderInline(lines: normalizedLines, cursorOffset: cursorOffset)
            }
        }
    }

    public func appendFrame(lines: [String]) {
        let normalizedLines = splitLogicalLines(lines)
        let separator = isTTY ? ttyNewline : "\n"
        var output = normalizedLines.joined(separator: separator)
        if !normalizedLines.isEmpty {
            output += separator
        }
        terminal.write(output)
    }

    public func resetRetainedFrame() {
        lock.withLock {
            previousLines = []
            lastFramePhysicalRows = 0
            lastCursorAnchored = false
            lastCursorOffset = 0
            committedLines = []
            lastCommittedPhysicalRows = 0
            previousLiveLines = []
            lastLivePhysicalRows = 0
        }
    }

    // MARK: - Commit / Live Rendering

    /// 两区域渲染：稳定区（committed）只追加，可变区（live）支持 diff。
    ///
    /// 与 `requestRender(lines:)` 相比，此 API 将帧显式分割为 committed 和 live
    /// 两部分，使运行时只需要对 live 区做 diff，避免对稳定历史行进行不必要的
    /// 比较和重绘。
    public func render(committed: [String], live: [String], cursorOffset: Int? = nil) {
        var normalizedCommitted = splitLogicalLines(committed)
        var normalizedLive = splitLogicalLines(live)

        // M4-S3: Live budget / overflow settlement
        if liveBudget > 0, normalizedLive.count > liveBudget {
            let overflow = normalizedLive.count - liveBudget
            let settled = Array(normalizedLive.prefix(overflow))
            normalizedCommitted += settled
            normalizedLive = Array(normalizedLive.suffix(liveBudget))
        }

        if !isTTY {
            let allLines = normalizedCommitted + normalizedLive
            var output = allLines.joined(separator: "\n")
            if !allLines.isEmpty && cursorOffset == nil {
                output += "\n"
            }
            terminal.write(output)
            return
        }

        switch strategy {
        case .legacyAbsolute:
            let allLines = normalizedCommitted + normalizedLive
            syncRetainedState(lines: allLines, committed: normalizedCommitted, live: normalizedLive, cursorOffset: cursorOffset)
            renderLegacy(lines: allLines, cursorOffset: cursorOffset)
        case .inlineAnchor:
            if shouldFallbackToFullRedraw(committed: normalizedCommitted, live: normalizedLive) {
                let allLines = normalizedCommitted + normalizedLive
                syncRetainedState(lines: allLines, committed: normalizedCommitted, live: normalizedLive, cursorOffset: cursorOffset)
                renderLegacy(lines: allLines, cursorOffset: cursorOffset)
            } else {
                renderInlineCommittedLive(committed: normalizedCommitted, live: normalizedLive, cursorOffset: cursorOffset)
            }
        }
    }

    private func renderLegacy(lines: [String], cursorOffset: Int?) {
        let anchored = cursorOffset != nil
        var output = "\u{1B}[2J\u{1B}[H"
        output += lines.joined(separator: ttyNewline)
        if !lines.isEmpty && !anchored {
            output += ttyNewline
        }
        if let offset = cursorOffset, offset > 0 {
            output += "\u{1B}[\(offset)D"
        }
        terminal.write(output)
    }

    private func syncRetainedState(lines: [String], committed: [String], live: [String], cursorOffset: Int?) {
        lock.withLock {
            previousLines = lines
            lastFramePhysicalRows = totalPhysicalRows(for: lines)
            lastCursorAnchored = cursorOffset != nil
            lastCursorOffset = cursorOffset ?? 0
            committedLines = committed
            lastCommittedPhysicalRows = totalPhysicalRows(for: committed)
            previousLiveLines = live
            lastLivePhysicalRows = totalPhysicalRows(for: live)
        }
    }

    private func renderInline(lines: [String], cursorOffset: Int?) {
        let (prev, prevRows, wasAnchored, previousCursorOffset) = lock.withLock {
            let oldPrev = previousLines
            let oldRows = lastFramePhysicalRows
            let anchored = lastCursorAnchored
            let oldCursorOffset = lastCursorOffset
            previousLines = lines
            lastFramePhysicalRows = totalPhysicalRows(for: lines)
            lastCursorAnchored = cursorOffset != nil
            lastCursorOffset = cursorOffset ?? 0
            // 同步 commit/live 状态：requestRender 视为全部 committed，无 live
            committedLines = lines
            lastCommittedPhysicalRows = totalPhysicalRows(for: lines)
            previousLiveLines = []
            lastLivePhysicalRows = 0
            return (oldPrev, oldRows, anchored, oldCursorOffset)
        }

        var output = ""
        let anchored = cursorOffset != nil
        let trailingNewline = !lines.isEmpty && !anchored

        if prev.isEmpty {
            output += lines.joined(separator: ttyNewline)
            if trailingNewline {
                output += ttyNewline
            }
        } else {
            let firstDiff = firstDifferenceIndex(lhs: prev, rhs: lines)
            let anchorChanged = wasAnchored != anchored

            if firstDiff == nil, !anchorChanged {
                if let offset = cursorOffset {
                    let delta = offset - previousCursorOffset
                    if delta > 0 {
                        output += "\u{1B}[\(delta)D"
                    } else if delta < 0 {
                        output += "\u{1B}[\(-delta)C"
                    }
                }

                if !output.isEmpty {
                    terminal.write(output)
                }
                return
            }

            let startLineIndex: Int
            if let diff = firstDiff {
                startLineIndex = diff > 0 ? diff - 1 : 0
            } else {
                startLineIndex = 0
            }

            let prefixRows = totalPhysicalRows(for: prev.prefix(startLineIndex))
            let prevTailRows = totalPhysicalRows(for: prev.dropFirst(startLineIndex))
            let newTail = Array(lines.dropFirst(startLineIndex))
            let rewindRows = wasAnchored
                ? max(0, (prevRows - 1) - prefixRows)
                : max(0, prevRows - prefixRows)

            output += "\r"
            if rewindRows > 0 {
                output += "\u{1B}[\(rewindRows)A"
            }

            for _ in 0..<prevTailRows {
                output += "\u{1B}[2K\r\n"
            }

            if prevTailRows > 0 {
                output += "\u{1B}[\(prevTailRows)A"
            }
            output += newTail.joined(separator: ttyNewline)
            if trailingNewline {
                output += ttyNewline
            }
        }

        if let offset = cursorOffset, offset > 0 {
            output += "\u{1B}[\(offset)D"
        }

        terminal.write(output)
    }

    private func totalPhysicalRows(for lines: [String]) -> Int {
        lines.map { physicalRows(for: $0, width: terminalWidth) }.reduce(0, +)
    }

    private func totalPhysicalRows(for lines: ArraySlice<String>) -> Int {
        lines.reduce(into: 0) { partialResult, line in
            partialResult += physicalRows(for: line, width: terminalWidth)
        }
    }

    private func firstDifferenceIndex(lhs: [String], rhs: [String]) -> Int? {
        let minCount = min(lhs.count, rhs.count)
        for index in 0..<minCount where lhs[index] != rhs[index] {
            return index
        }
        return lhs.count == rhs.count ? nil : minCount
    }

    private func shouldFallbackToFullRedraw(for lines: [String]) -> Bool {
        lock.withLock {
            guard terminalHeight > 0 else { return false }
            let currentRows = totalPhysicalRows(for: lines)
            return max(lastFramePhysicalRows, currentRows) > terminalHeight
        }
    }

    private func shouldFallbackToFullRedraw(committed: [String], live: [String]) -> Bool {
        lock.withLock {
            guard terminalHeight > 0 else { return false }
            let currentRows = totalPhysicalRows(for: committed) + totalPhysicalRows(for: live)
            let prevTotalRows = lastCommittedPhysicalRows + lastLivePhysicalRows
            return max(prevTotalRows, currentRows) > terminalHeight
        }
    }

    private func renderInlineCommittedLive(committed: [String], live: [String], cursorOffset: Int?) {
        let (prevCommitted, prevCommittedRows, prevLive, prevLiveRows, wasAnchored, previousCursorOffset) = lock.withLock {
            let oldCommitted = committedLines
            let oldCommittedRows = lastCommittedPhysicalRows
            let oldLive = previousLiveLines
            let oldLiveRows = lastLivePhysicalRows
            let anchored = lastCursorAnchored
            let oldCursorOffset = lastCursorOffset

            committedLines = committed
            lastCommittedPhysicalRows = totalPhysicalRows(for: committed)
            previousLiveLines = live
            lastLivePhysicalRows = totalPhysicalRows(for: live)
            lastCursorAnchored = cursorOffset != nil
            lastCursorOffset = cursorOffset ?? 0
            // 同步 previousLines 状态
            let allLines = committed + live
            previousLines = allLines
            lastFramePhysicalRows = totalPhysicalRows(for: allLines)

            return (oldCommitted, oldCommittedRows, oldLive, oldLiveRows, anchored, oldCursorOffset)
        }

        let anchored = cursorOffset != nil
        let trailingNewline = !live.isEmpty && !anchored

        // 1. 快速路径：没有任何变化
        let committedDiff = firstDifferenceIndex(lhs: prevCommitted, rhs: committed)
        let liveDiff = firstDifferenceIndex(lhs: prevLive, rhs: live)
        let anchorChanged = wasAnchored != anchored

        if committedDiff == nil, liveDiff == nil, !anchorChanged {
            var output = ""
            if let offset = cursorOffset {
                let delta = offset - previousCursorOffset
                if delta > 0 {
                    output += "\u{1B}[\(delta)D"
                } else if delta < 0 {
                    output += "\u{1B}[\(-delta)C"
                }
            }
            if !output.isEmpty {
                terminal.write(output)
            }
            return
        }

        // 2. M4-S2 fast path: committed pure append with unchanged live
        let isPureAppend = committedDiff == prevCommitted.count
        if isPureAppend, liveDiff == nil, !wasAnchored, cursorOffset == nil, prevLiveRows > 0 {
            let appendedCount = committed.count - prevCommitted.count
            let appendedLines = Array(committed.suffix(appendedCount))
            let appendedAllSingleRow = appendedLines.allSatisfy {
                physicalRows(for: $0, width: terminalWidth) == 1
            }
            if appendedAllSingleRow {
                var output = "\r"
                // Rewind to first live line
                if prevLiveRows > 0 {
                    output += "\u{1B}[\(prevLiveRows)A"
                }
                // Insert empty lines for appended committed
                if appendedCount > 0 {
                    output += "\u{1B}[\(appendedCount)L"
                }
                // Output appended committed lines
                output += appendedLines.joined(separator: ttyNewline)
                output += "\r"
                // Move down to first live line
                output += "\u{1B}[1B"
                // Output live region
                output += live.joined(separator: ttyNewline)
                if trailingNewline {
                    output += ttyNewline
                }
                terminal.write(output)
                return
            }
        }

        // 3. 确定 diff 起始行（回退一行以保留上下文）
        let startLineIndex: Int
        if let cd = committedDiff {
            startLineIndex = cd > 0 ? cd - 1 : 0
        } else if let ld = liveDiff {
            let rawStart = committed.count + ld
            startLineIndex = rawStart > 0 ? rawStart - 1 : 0
        } else {
            startLineIndex = 0
        }

        // 3. 计算 prefixRows（到 startLineIndex 为止的物理行数）
        let prefixRows: Int
        if startLineIndex <= committed.count {
            prefixRows = totalPhysicalRows(for: committed.prefix(startLineIndex))
        } else {
            prefixRows = lastCommittedPhysicalRows + totalPhysicalRows(for: live.prefix(startLineIndex - committed.count))
        }

        // 4. 计算 prevTailRows（从 startLineIndex 到 prev 末尾的物理行数）
        let prevTailRows: Int
        if startLineIndex <= prevCommitted.count {
            let committedTail = totalPhysicalRows(for: prevCommitted.dropFirst(startLineIndex))
            prevTailRows = committedTail + prevLiveRows
        } else {
            prevTailRows = totalPhysicalRows(for: prevLive.dropFirst(startLineIndex - prevCommitted.count))
        }

        // 5. 计算 newTail 和 rewindRows
        let allNew = committed + live
        let newTail = Array(allNew.dropFirst(startLineIndex))
        let prevTotalRows = prevCommittedRows + prevLiveRows
        let rewindRows = wasAnchored
            ? max(0, (prevTotalRows - 1) - prefixRows)
            : max(0, prevTotalRows - prefixRows)

        // 6. 生成输出
        var output = prevTotalRows > 0 ? "\r" : ""
        if rewindRows > 0 {
            output += "\u{1B}[\(rewindRows)A"
        }

        for _ in 0..<prevTailRows {
            output += "\u{1B}[2K\r\n"
        }

        if prevTailRows > 0 {
            output += "\u{1B}[\(prevTailRows)A"
        }

        output += newTail.joined(separator: ttyNewline)
        if trailingNewline {
            output += ttyNewline
        }

        if let offset = cursorOffset, offset > 0 {
            output += "\u{1B}[\(offset)D"
        }

        terminal.write(output)
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
