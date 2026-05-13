import Foundation

/// Renders a ``ScreenLayout`` into a ``ComposedFrame`` with a minimal live-region policy.
///
/// Live-region policy (stable, testable, and visually neutral):
/// - **Live** = the final `input` lines (if any). Input is inherently transient and
///   may change on every keystroke, so it is the smallest, most stable candidate for
///   the live region.
/// - **Committed** = everything else (`header`, `transcript`, `queue`, `status`,
///   plus divider blank lines). These lines change far less frequently and are safe
///   to treat as stable history.
///
/// Budget policy (partition-priority, single-strategy):
/// - `terminalHeight` is enforced as a hard physical-row budget.
/// - **Priority order** (high → low): live (input) > status > queue > header > transcript.
/// - Each partition is evaluated independently. When the budget is exhausted, lower-
///   priority partitions are dropped *in full* before any higher-priority partition
///   is clipped. Within a single partition, clipping is tail-preserving (newest kept).
/// - `terminalWidth` is used for physical-row calculation (wrap-aware) but does not
///   truncate individual lines.
///
/// Pinned-transcript policy (additive to budget policy):
/// - `pinnedTranscriptRange` identifies a sub-range of `transcript` that must be kept
///   *intact* whenever possible (e.g. a streaming block).
/// - The final transcript output is always a subsequence of the original `transcript`
///   in the original index order (no reordering).
/// - When the transcript partition is evaluated:
///   1. If the range is missing, empty, or out-of-bounds → behave exactly like B1
///      (plain tail-preserving clip on the whole transcript).
///   2. If the range is valid:
///      a. Compute the physical rows of the pinned segment.
///      b. If the pinned segment alone fits in the remaining budget → try to also
///         include non-pinned lines, favouring lines closest to the pinned block
///         (after-tail first, then before-tail), all in original order.
///      c. If the pinned segment alone exceeds the remaining budget → clip the
///         pinned segment itself tail-preserving (keep the *end* of the pinned block).
/// - The pinned segment is never split in the middle; it is either fully present or
///   fully absent (or tail-clipped as a whole when the budget is smaller than the
///   pinned block itself).
public struct ScreenLayoutRenderer: Sendable {
    public init() {}

    public func render(
        layout: ScreenLayout,
        config: ScreenLayoutConfig,
        cursorOffset: Int? = nil
    ) -> ComposedFrame {
        let width = config.terminalWidth

        // Build partitions in visual order (top → bottom) with their priority rank.
        // Lower rank number = higher priority.
        var partitions: [(rank: Int, lines: [String], physical: [Int])] = []

        // 4. Header (visual top, lower priority)
        if config.showHeader && !layout.header.isEmpty {
            partitions.append((4, layout.header, layout.header.map { physicalRows(for: $0, width: width) }))
        }

        // 5. Transcript (visual below header, lowest priority)
        if !layout.transcript.isEmpty {
            let physical = layout.transcript.map { physicalRows(for: $0, width: width) }
            partitions.append((5, layout.transcript, physical))
        }

        // 3. Queue
        if !layout.queue.isEmpty {
            let lines = [""] + layout.queue
            partitions.append((3, lines, lines.map { physicalRows(for: $0, width: width) }))
        }

        // 2. Status
        if !layout.status.isEmpty {
            let lines = [""] + layout.status
            partitions.append((2, lines, lines.map { physicalRows(for: $0, width: width) }))
        }

        // 1. Live (input) — highest priority, visual bottom
        let inputLines: [String]
        let hasOtherContent = !layout.header.isEmpty
            || !layout.transcript.isEmpty
            || !layout.queue.isEmpty
            || !layout.status.isEmpty
        if layout.input.isEmpty {
            inputLines = []
        } else if hasOtherContent {
            inputLines = [""] + layout.input
        } else {
            inputLines = layout.input
        }
        if !inputLines.isEmpty {
            partitions.append((1, inputLines, inputLines.map { physicalRows(for: $0, width: width) }))
        }

        // Apply budget by priority rank (1 first, then 2, 3, 4, 5).
        let budget = config.terminalHeight
        var remaining = budget
        var accepted: [(rank: Int, lines: [String])] = []

        for rank in 1...5 {
            guard let idx = partitions.firstIndex(where: { $0.rank == rank }) else { continue }
            let part = partitions[idx]
            let totalPhysical = part.physical.reduce(0, +)
            if totalPhysical <= remaining {
                accepted.append((rank, part.lines))
                remaining -= totalPhysical
            } else {
                // Transcript (rank 5) gets pinned-aware clipping.
                let clipped: [String]
                let used: Int
                if rank == 5 {
                    (clipped, used) = clipTranscriptWithPinned(
                        transcript: part.lines,
                        physicalPerLine: part.physical,
                        pinnedRange: layout.pinnedTranscriptRange,
                        maxPhysicalRows: remaining
                    )
                } else {
                    (clipped, used) = clipTail(
                        lines: part.lines,
                        physicalPerLine: part.physical,
                        maxPhysicalRows: remaining
                    )
                }
                if !clipped.isEmpty {
                    accepted.append((rank, clipped))
                    remaining -= used
                }
                // Budget exhausted; drop all lower-priority partitions.
                break
            }
        }

        // Separate live (rank 1) from committed (ranks 2..5).
        let live = accepted.first(where: { $0.rank == 1 })?.lines ?? []
        // Committed must be in visual order: header (4) → transcript (5) → queue (3) → status (2)
        let committedRanks = [4, 5, 3, 2]
        var committed: [String] = []
        for r in committedRanks {
            if let part = accepted.first(where: { $0.rank == r }) {
                committed.append(contentsOf: part.lines)
            }
        }

        return ComposedFrame(
            committed: committed,
            live: live,
            cursorOffset: cursorOffset
        )
    }

    /// Overload that accepts a 2D `CursorPlacement` instead of a single `cursorOffset`.
    ///
    /// Convenience wrapper that re-uses the partition / budget logic of the primary
    /// `render(layout:config:cursorOffset:)` and only swaps in the 2D cursor anchor.
    public func render(
        layout: ScreenLayout,
        config: ScreenLayoutConfig,
        cursorPlacement: CursorPlacement
    ) -> ComposedFrame {
        let frame = render(layout: layout, config: config, cursorOffset: nil)
        return ComposedFrame(
            committed: frame.committed,
            live: frame.live,
            cursorPlacement: cursorPlacement
        )
    }

    // MARK: - Pinned-aware transcript clipping (order-preserving)

    /// Clips a transcript while respecting a pinned range and preserving original order.
    ///
    /// Rules:
    /// 1. Invalid/missing/empty range → plain tail clip (B1).
    /// 2. Valid range, pinned fits in budget → keep all pinned, then fill remaining
    ///    budget with non-pinned lines closest to pinned (after-tail first, then
    ///    before-tail), all in original index order.
    /// 3. Valid range, pinned exceeds budget → tail-clip the pinned block itself
    ///    (never split in the middle).
    private func clipTranscriptWithPinned(
        transcript: [String],
        physicalPerLine: [Int],
        pinnedRange: Range<Int>?,
        maxPhysicalRows: Int
    ) -> (lines: [String], used: Int) {
        guard let range = pinnedRange,
              range.lowerBound >= 0,
              range.upperBound <= transcript.count,
              !range.isEmpty else {
            return clipTail(lines: transcript, physicalPerLine: physicalPerLine, maxPhysicalRows: maxPhysicalRows)
        }

        let pinnedPhysical = physicalPerLine[range].reduce(0, +)

        // Case 3: pinned alone exceeds budget → tail-clip within pinned only.
        if pinnedPhysical > maxPhysicalRows {
            let pinnedLines = Array(transcript[range])
            let pinnedPhys = Array(physicalPerLine[range])
            return clipTail(lines: pinnedLines, physicalPerLine: pinnedPhys, maxPhysicalRows: maxPhysicalRows)
        }

        // Case 2: pinned fits. Keep all pinned, then fill with non-pinned.
        var selected = Set(range)
        var used = pinnedPhysical
        var remaining = maxPhysicalRows - used

        // Collect candidates closest to pinned: after-tail (higher indices) first,
        // then before-tail (lower indices), both in reverse index order so that
        // adding them preserves original ascending order once sorted.
        var candidates: [(index: Int, physical: Int)] = []
        for i in (range.upperBound..<transcript.count).reversed() {
            candidates.append((i, physicalPerLine[i]))
        }
        for i in (0..<range.lowerBound).reversed() {
            candidates.append((i, physicalPerLine[i]))
        }

        for (i, phys) in candidates {
            if phys <= remaining {
                selected.insert(i)
                used += phys
                remaining -= phys
            }
        }

        let result = selected.sorted().map { transcript[$0] }
        return (result, used)
    }
}
