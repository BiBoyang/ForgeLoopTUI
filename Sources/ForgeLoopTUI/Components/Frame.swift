import Foundation

/// A frame ready for `TUI.render(frame:)`.
///
/// Mirrors `TUI.render(committed:live:cursorOffset:)` so that a composer
/// can assemble committed/live regions from multiple components.
public struct ComposedFrame: Sendable {
    public let committed: [String]
    public let live: [String]
    public let cursorOffset: Int?

    public init(committed: [String] = [], live: [String] = [], cursorOffset: Int? = nil) {
        self.committed = committed
        self.live = live
        self.cursorOffset = cursorOffset
    }
}

/// View-port budget expressed in physical rows.
///
/// When a budget is applied, content is clipped from the *head* so that
/// the newest (tail) content is retained.  The optional
/// `overflowMarker` is emitted as a single line only when clipping
/// actually occurs.
public struct LayoutBudget: Sendable {
    public let maxRows: Int
    public let overflowMarker: String?

    public init(maxRows: Int, overflowMarker: String? = nil) {
        self.maxRows = maxRows
        self.overflowMarker = overflowMarker
    }
}

/// Assembles a `ComposedFrame` from committed/live component regions.
public struct FrameComposer: Sendable {
    public var committedComponents: [AnyComponent]
    public var liveComponents: [AnyComponent]
    public var layoutBudget: LayoutBudget?

    public init(
        committed: [AnyComponent] = [],
        live: [AnyComponent] = [],
        layoutBudget: LayoutBudget? = nil
    ) {
        self.committedComponents = committed
        self.liveComponents = live
        self.layoutBudget = layoutBudget
    }

    /// Renders all components into a single `ComposedFrame`.
    ///
    /// - Parameters:
    ///   - width: terminal width passed to each component
    ///   - cursorOffset: optional cursor offset for the live region
    /// - Returns: a `ComposedFrame` ready for `TUI.render(frame:)`
    public func render(width: Int, cursorOffset: Int? = nil) -> ComposedFrame {
        let committedLines = committedComponents.flatMap { $0.render(width: width) }
        let liveLines = liveComponents.flatMap { $0.render(width: width) }

        guard let budget = layoutBudget else {
            return ComposedFrame(
                committed: committedLines,
                live: liveLines,
                cursorOffset: cursorOffset
            )
        }

        return applyBudget(
            committed: committedLines,
            live: liveLines,
            width: width,
            budget: budget,
            cursorOffset: cursorOffset
        )
    }

    // MARK: - Budget Application

    private func applyBudget(
        committed: [String],
        live: [String],
        width: Int,
        budget: LayoutBudget,
        cursorOffset: Int?
    ) -> ComposedFrame {
        let livePhysical = live.map { physicalRows(for: $0, width: width) }
        let committedPhysical = committed.map { physicalRows(for: $0, width: width) }
        let totalLive = livePhysical.reduce(0, +)
        let totalCommitted = committedPhysical.reduce(0, +)
        let total = totalLive + totalCommitted

        guard total > budget.maxRows else {
            return ComposedFrame(committed: committed, live: live, cursorOffset: cursorOffset)
        }

        let marker = budget.overflowMarker
        let markerRows = marker != nil ? 1 : 0
        let available = budget.maxRows - markerRows

        // 1. Prioritise live tail
        let (liveClipped, liveUsed) = clipTail(
            lines: live,
            physicalPerLine: livePhysical,
            maxPhysicalRows: available
        )

        if liveClipped.count < live.count {
            // Live itself exceeds budget; committed is completely dropped.
            let finalLive = marker != nil ? [marker!] + liveClipped : liveClipped
            return ComposedFrame(committed: [], live: finalLive, cursorOffset: cursorOffset)
        }

        // 2. Live fits entirely; give remainder to committed tail
        let committedBudget = available - liveUsed
        let (committedClipped, _) = clipTail(
            lines: committed,
            physicalPerLine: committedPhysical,
            maxPhysicalRows: committedBudget
        )

        let finalCommitted = (committedClipped.count < committed.count && marker != nil)
            ? [marker!] + committedClipped
            : committedClipped

        return ComposedFrame(
            committed: finalCommitted,
            live: liveClipped,
            cursorOffset: cursorOffset
        )
    }
}

// MARK: - Tail-clipping helper

/// Returns the tail slice of `lines` whose physical rows do not exceed
/// `maxPhysicalRows`, together with the exact physical row count used.
func clipTail(lines: [String], physicalPerLine: [Int], maxPhysicalRows: Int) -> (lines: [String], used: Int) {
    var accumulated = 0
    var startIndex = lines.count

    for i in (0..<lines.count).reversed() {
        let rows = physicalPerLine[i]
        if accumulated + rows > maxPhysicalRows {
            break
        }
        accumulated += rows
        startIndex = i
    }

    return (Array(lines[startIndex...]), accumulated)
}
