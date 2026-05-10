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
            partitions.append((5, layout.transcript, layout.transcript.map { physicalRows(for: $0, width: width) }))
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
                let (clipped, used) = clipTail(
                    lines: part.lines,
                    physicalPerLine: part.physical,
                    maxPhysicalRows: remaining
                )
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
}
