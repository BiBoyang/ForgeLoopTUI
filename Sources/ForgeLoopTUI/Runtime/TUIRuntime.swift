import Foundation

/// TUI 渲染诊断事件，通过 `TUI.diagnosticsHandler` 可选回调发出。
/// 默认关闭，零性能侵入。
public enum TUIRenderDiagnostic: Sendable {
    /// 触发了全量重绘（清屏+重写），包含触发原因。
    case fullRedraw(reason: String)
    /// 使用了增量 diff 渲染。
    case diff(linesChanged: Int, physicalRows: Int)
    /// live budget 沉降发生。
    case budgetSettled(linesSettled: Int)
    /// 触发了 committed 纯追加快速路径。
    case fastPath(appendedLines: Int)
}

/// 将旧版 `FrameWriter` 桥接到 `Terminal` 协议的内部适配器。
private struct WriterTerminal: Terminal {
    let isTTY: Bool
    let capability: TerminalCapability
    let writer: FrameWriter

    func write(_ text: String) {
        writer(text)
    }
}

/// `cursorPlacement` 渲染时,光标的硬件定位策略。
///
/// - ``relative``: 用相对位移 `ESC[nA` / `ESC[nD` / `ESC[nC` 把光标从内容末尾
///   移动到目标。实现简单,但在 wrap 行 / IME 候选窗等场景下,硬件实际位置
///   会与逻辑位移产生差距。**这是默认值,保持现有行为**。
/// - ``marker``: 基于物理行计算的精确路径——上下用 `ESC[nA`,水平用
///   `ESC[<col>G`(CHA 绝对列)定位。对 wrap / 中文输入法候选窗等场景更可靠。
///
/// 非 TTY 输出永远不发任何 ANSI 序列;mode 仅在 `isTTY == true` 时生效。
///
/// 稳定等级: Provisional。
public enum CursorPositioningMode: Sendable, Equatable {
    case relative
    case marker
}

public final class TUI: @unchecked Sendable {
    public let strategy: RenderStrategy
    public let isTTY: Bool
    public let liveBudget: Int
    public let liveBudgetMode: LiveBudgetMode
    public let cursorPositioningMode: CursorPositioningMode
    public private(set) var terminalWidth: Int
    public private(set) var terminalHeight: Int
    private let terminal: Terminal

    /// 可选诊断回调，默认 nil（零开销）。设置后，渲染关键决策会触发回调。
    public var diagnosticsHandler: (@Sendable (TUIRenderDiagnostic) -> Void)?

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

    // MARK: - 2D cursor placement state
    /// Tracks pending cursor displacement from canonical anchor (end of last live line)
    /// caused by a previous `cursorPlacement` render. On the next render, this is emitted
    /// first to restore the cursor to the anchor so the diff / fast-path logic remains
    /// consistent. Cleared after each emit.
    private var pendingPlacementUndoUp: Int = 0
    private var pendingPlacementUndoHorizontal: Int = 0
    /// `.marker` 路径下使用的预渲染 undo 序列。一旦非空,优先于上面两个 delta 字段。
    /// 写入一次后由 ``consumePlacementUndo`` 在下次输出时清空。
    private var pendingPlacementUndoOverride: String? = nil

    public init(
        strategy: RenderStrategy? = nil,
        isTTY: Bool? = nil,
        terminalWidth: Int = 80,
        terminalHeight: Int = 24,
        liveBudget: Int = 0,
        liveBudgetMode: LiveBudgetMode = .logicalLines,
        cursorPositioningMode: CursorPositioningMode = .relative,
        terminal: Terminal? = nil,
        writer: FrameWriter? = nil
    ) {
        self.liveBudget = liveBudget
        self.liveBudgetMode = liveBudgetMode
        self.cursorPositioningMode = cursorPositioningMode
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

    /// 标记终端缓存状态已失效（如 resize、外部清屏等），强制重算所有物理行缓存。
    /// 仅重算缓存，不修改终端宽高；幂等。
    public func invalidate() {
        lock.withLock {
            // 仅重算物理行缓存，不修改宽高（避免并发场景下覆盖并发更新的尺寸值）
            lastFramePhysicalRows = totalPhysicalRows(for: previousLines)
            lastCommittedPhysicalRows = totalPhysicalRows(for: committedLines)
            lastLivePhysicalRows = totalPhysicalRows(for: previousLiveLines)
        }
    }

    // MARK: - Placement undo plumbing
    //
    // 二维光标 (cursorPlacement) 在内容渲染之后将终端光标移到目标行/列；
    // 下一帧渲染前必须先把光标移回 "canonical anchor"（最后一行末尾），
    // 否则 diff/快路径里基于 cursor offset 的相对位移会算错位置。
    // 这里把 undo 序列单点拼接到每次输出的最前面。

    private func consumePlacementUndo() -> String {
        let (override, up, h): (String?, Int, Int) = lock.withLock {
            let ov = pendingPlacementUndoOverride
            let u = pendingPlacementUndoUp
            let hh = pendingPlacementUndoHorizontal
            pendingPlacementUndoOverride = nil
            pendingPlacementUndoUp = 0
            pendingPlacementUndoHorizontal = 0
            return (ov, u, hh)
        }
        if let override { return override }
        var s = ""
        if up > 0 {
            s += "\u{1B}[\(up)B"
        }
        if h > 0 {
            s += "\u{1B}[\(h)C"
        } else if h < 0 {
            s += "\u{1B}[\(-h)D"
        }
        return s
    }

    private func writeFrameOutput(_ output: String) {
        let undo = consumePlacementUndo()
        let combined = undo + output
        if !combined.isEmpty {
            terminal.write(combined)
        }
    }

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
                diagnosticsHandler?(.fullRedraw(reason: "frame exceeds terminal height"))
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
        if isTTY {
            writeFrameOutput(output)
        } else {
            terminal.write(output)
        }
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
            pendingPlacementUndoUp = 0
            pendingPlacementUndoHorizontal = 0
            pendingPlacementUndoOverride = nil
        }
    }

    // MARK: - Commit / Live Rendering

    /// 两区域渲染：稳定区（committed）只追加，可变区（live）支持 diff。
    ///
    /// 与 `requestRender(lines:)` 相比，此 API 将帧显式分割为 committed 和 live
    /// 两部分，使运行时只需要对 live 区做 diff，避免对稳定历史行进行不必要的
    /// 比较和重绘。
    ///
    /// 若构造 `TUI` 时配置了 `liveBudget`,该方法会在 diff 前调用 ``applyLiveBudget(committed:live:)``
    /// 把超出预算的 live 头部沉降到 committed。
    public func render(committed: [String], live: [String], cursorOffset: Int? = nil) {
        let normalizedCommitted = splitLogicalLines(committed)
        let normalizedLive = splitLogicalLines(live)
        let (effectiveCommitted, effectiveLive) = applyLiveBudget(committed: normalizedCommitted, live: normalizedLive)
        renderEffective(committed: effectiveCommitted, live: effectiveLive, cursorOffset: cursorOffset)
    }

    /// 两区域渲染 + 二维光标锚点（cursorPlacement）。
    ///
    /// `cursorPlacement.up` 表示光标从 live 末行向上的行数偏移，
    /// `cursorPlacement.offset` 表示光标在目标行内从该行末尾向左的列偏移。
    /// 当 `up = 0` 时与 `render(committed:live:cursorOffset:)` 行为完全一致。
    ///
    /// 实现策略：先用 `cursorOffset = 0` 把内容渲染到位（终端光标停在最后一行末尾），
    /// 再额外发出 `ESC[<up>A` 和水平调整序列把光标移到目标位置；下一帧渲染前
    /// 会把这次位移自动 undo，保证内部 diff/快路径的相对位移计算仍然正确。
    ///
    /// 与 `render(committed:live:cursorOffset:)` 走同一个 ``applyLiveBudget(committed:live:)``
    /// 入口,确保两条渲染路径下沉降语义完全一致。
    public func render(committed: [String], live: [String], cursorPlacement: CursorPlacement) {
        let normalizedCommitted = splitLogicalLines(committed)
        let normalizedLive = splitLogicalLines(live)
        let (effectiveCommitted, effectiveLive) = applyLiveBudget(committed: normalizedCommitted, live: normalizedLive)

        // Delegate content rendering with cursor anchored at canonical position.
        // 传入已沉降的版本,避免 renderEffective 重复沉降。
        renderEffective(committed: effectiveCommitted, live: effectiveLive, cursorOffset: 0)

        guard isTTY, !effectiveLive.isEmpty else { return }

        switch cursorPositioningMode {
        case .relative:
            emitRelativePlacement(live: effectiveLive, placement: cursorPlacement)
        case .marker:
            emitMarkerPlacement(live: effectiveLive, placement: cursorPlacement)
        }
    }

    /// `.relative` 模式下的相对位移光标定位:`ESC[<n>A` 上移 + `ESC[<n>D/C` 左/右移。
    /// 这是兼容旧调用方的默认实现。
    private func emitRelativePlacement(live: [String], placement: CursorPlacement) {
        let liveCount = live.count
        let upClamped = max(0, min(placement.up, liveCount - 1))
        let targetRowIndex = liveCount - 1 - upClamped
        let targetRowWidth = visibleWidth(live[targetRowIndex])
        let targetCol = max(0, targetRowWidth - placement.offset)
        let lastLineWidth = visibleWidth(live[liveCount - 1])
        let leftDelta = lastLineWidth - targetCol

        var output = ""
        if upClamped > 0 {
            output += "\u{1B}[\(upClamped)A"
        }
        if leftDelta > 0 {
            output += "\u{1B}[\(leftDelta)D"
        } else if leftDelta < 0 {
            output += "\u{1B}[\(-leftDelta)C"
        }

        if !output.isEmpty {
            terminal.write(output)
        }

        lock.withLock {
            pendingPlacementUndoUp = upClamped
            pendingPlacementUndoHorizontal = leftDelta
        }
    }

    /// `.marker` 模式下的精确光标定位:基于物理行的 `ESC[<n>A` + CHA 绝对列
    /// `ESC[<col>G`。对 wrap / 中文输入法候选窗等场景更可靠。
    private func emitMarkerPlacement(live: [String], placement: CursorPlacement) {
        let w = max(1, terminalWidth)
        let liveCount = live.count
        let upClamped = max(0, min(placement.up, liveCount - 1))
        let targetRowIndex = liveCount - 1 - upClamped
        let targetRowWidth = visibleWidth(live[targetRowIndex])
        let targetCol = max(0, targetRowWidth - placement.offset)
        let lastLineWidth = visibleWidth(live[liveCount - 1])

        // Per-row physical row counts. Calling physicalRows once per row keeps
        // this O(n) over live lines.
        let physPerRow = live.map { physicalRows(for: $0, width: w) }
        let lastRowPhys = physPerRow[liveCount - 1]
        // Cursor's absolute physical row after content rendering: the last
        // physical row of the last logical line. (We assume autowrap-on: the
        // cursor sits at column `lastLineWidth + 1`, clamped to the right
        // margin; wrap edge cases are handled below.)
        let physRowsBeforeLast = physPerRow.dropLast().reduce(0, +)
        let cursorAbsRow = physRowsBeforeLast + (lastRowPhys - 1)

        // Target absolute physical row: rows of all prior logical lines plus
        // how many physical rows we descend within the target logical line.
        let sumBeforeTarget = physPerRow.prefix(targetRowIndex).reduce(0, +)
        let physRowInsideTarget = targetCol / w
        let targetAbsRow = sumBeforeTarget + physRowInsideTarget

        // Target physical column inside the row (1-indexed for CHA).
        let targetPhysColZero = targetCol % w
        let targetPhysColOne = targetPhysColZero + 1

        let upDelta = max(0, cursorAbsRow - targetAbsRow)

        var output = ""
        if upDelta > 0 {
            output += "\u{1B}[\(upDelta)A"
        }
        output += "\u{1B}[\(targetPhysColOne)G"
        terminal.write(output)

        // Undo: move cursor back to canonical anchor (end of last logical
        // line as left by content rendering). We use the same CHA + relative
        // vertical move so the undo is itself precise.
        //
        // The cursor's natural column after writing `lastLineWidth` chars
        // (autowrap on) is `((lastLineWidth - 1) % w) + 2` (1-indexed,
        // pointing AT the cell after the last char). When the line is empty
        // the cursor sits at column 1. The CHA target is clamped to `w`
        // because some terminals defer wrap to the next character.
        let canonicalCol: Int
        if lastLineWidth == 0 {
            canonicalCol = 1
        } else {
            canonicalCol = ((lastLineWidth - 1) % w) + 2
        }
        let canonicalColClamped = min(canonicalCol, w)

        var undo = ""
        if upDelta > 0 {
            undo += "\u{1B}[\(upDelta)B"
        }
        undo += "\u{1B}[\(canonicalColClamped)G"

        lock.withLock {
            pendingPlacementUndoOverride = undo
            pendingPlacementUndoUp = 0
            pendingPlacementUndoHorizontal = 0
        }
    }

    /// 统一沉降入口。把 `committed` / `live` 输入交给 ``LiveBudgetPlanner``,
    /// 把超出 `liveBudget` 的 live 头部沉降到 committed。
    ///
    /// 此方法是 ``render(committed:live:cursorOffset:)`` 与
    /// ``render(committed:live:cursorPlacement:)`` 共享的单点入口,
    /// 用于杜绝两条路径间的语义漂移。
    private func applyLiveBudget(committed: [String], live: [String]) -> (committed: [String], live: [String]) {
        let planner = LiveBudgetPlanner(mode: liveBudgetMode, budget: liveBudget, width: terminalWidth)
        let plan = planner.plan(committed: committed, live: live)
        let settled = plan.committed.count - committed.count
        if settled > 0 {
            diagnosticsHandler?(.budgetSettled(linesSettled: settled))
        }
        return (plan.committed, plan.live)
    }

    /// 不再做 normalize/budget,直接渲染已沉降后的 committed/live。
    private func renderEffective(committed: [String], live: [String], cursorOffset: Int?) {
        if !isTTY {
            let allLines = committed + live
            var output = allLines.joined(separator: "\n")
            if !allLines.isEmpty && cursorOffset == nil {
                output += "\n"
            }
            terminal.write(output)
            return
        }

        switch strategy {
        case .legacyAbsolute:
            let allLines = committed + live
            syncRetainedState(lines: allLines, committed: committed, live: live, cursorOffset: cursorOffset)
            renderLegacy(lines: allLines, cursorOffset: cursorOffset)
        case .inlineAnchor:
            if shouldFallbackToFullRedraw(committed: committed, live: live) {
                diagnosticsHandler?(.fullRedraw(reason: "committed+live exceeds terminal height"))
                let allLines = committed + live
                syncRetainedState(lines: allLines, committed: committed, live: live, cursorOffset: cursorOffset)
                renderLegacy(lines: allLines, cursorOffset: cursorOffset)
            } else {
                renderInlineCommittedLive(committed: committed, live: live, cursorOffset: cursorOffset)
            }
        }
    }

    private func renderLegacy(lines: [String], cursorOffset: Int?) {
        // Clear-screen sequences invalidate any prior 2D cursor placement.
        lock.withLock {
            pendingPlacementUndoUp = 0
            pendingPlacementUndoHorizontal = 0
            pendingPlacementUndoOverride = nil
        }
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

                writeFrameOutput(output)
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

        writeFrameOutput(output)
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
            writeFrameOutput(output)
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
                diagnosticsHandler?(.fastPath(appendedLines: appendedCount))
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
                writeFrameOutput(output)
                return
            }
        }

        // Emit diff diagnostic before generating output
        let totalChangedLines: Int
        if let cd = committedDiff { totalChangedLines = committed.count - cd }
        else if let ld = liveDiff { totalChangedLines = live.count - ld }
        else { totalChangedLines = 0 }
        diagnosticsHandler?(.diff(linesChanged: totalChangedLines, physicalRows: 0))

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

        writeFrameOutput(output)
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
