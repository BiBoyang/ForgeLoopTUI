import Foundation

public struct StreamingTranscriptAppendState: Sendable {
    public private(set) var printedTranscriptCount = 0
    public private(set) var printedCompletedStreamingLines: [String] = []

    public init() {}

    /// Delta computation for append-only UIs driven by an engine-certified
    /// stable prefix.
    ///
    /// - Lines before `activeRange` are settled transcript and are emitted
    ///   exactly once.
    /// - Inside the streaming block only the leading `stableLineCount` lines
    ///   are emitted (exactly once each): the engine guarantees they never
    ///   re-render, so committing them to scrollback is safe. Lines past the
    ///   stable boundary may still change mid-stream (tables gaining rows,
    ///   degrade↔render flips, fence chrome) and must stay in the live
    ///   region. Pass `TranscriptRenderer.activeStreamingStableLineCount`.
    /// - When the block ends (`activeRange == nil`) everything remaining is
    ///   flushed; the final render is frozen, so nothing can change anymore.
    ///
    /// `printedTranscriptCount` never rewinds while the transcript only
    /// grows: even if a caller passes a shrinking `stableLineCount`,
    /// already-printed lines are never re-emitted — the worst case is a
    /// delayed line, never a duplicate. (A transcript that *shrinks*, e.g.
    /// via `blockCancel`, is the deliberate recovery path: the count clamps
    /// and the replacement lines flush.)
    public mutating func consume(
        transcript: [String],
        activeRange: Range<Int>?,
        stableLineCount: Int
    ) -> [String] {
        if printedTranscriptCount > transcript.count {
            printedTranscriptCount = transcript.count
        }

        var newLines: [String] = []
        if let activeRange {
            let blockStart = min(activeRange.lowerBound, transcript.count)
            if blockStart > printedTranscriptCount {
                newLines.append(contentsOf: transcript[printedTranscriptCount..<blockStart])
                printedTranscriptCount = blockStart
            }

            let blockEnd = min(activeRange.upperBound, transcript.count)
            let stableUpperBound = min(blockStart + max(0, stableLineCount), blockEnd)
            if stableUpperBound > printedTranscriptCount {
                newLines.append(contentsOf: transcript[printedTranscriptCount..<stableUpperBound])
                printedTranscriptCount = stableUpperBound
            }
            return newLines
        }

        guard transcript.count > printedTranscriptCount else { return [] }
        let flushed = Array(transcript[printedTranscriptCount..<transcript.count])
        printedTranscriptCount = transcript.count
        return flushed
    }

    /// Legacy heuristic: treats every rendered line of the streaming block
    /// except the last as committed. That assumption breaks whenever the
    /// engine re-renders earlier lines mid-stream (streaming tables, code
    /// fences), which re-emits already-printed lines and duplicates output.
    @available(*, deprecated, message: "Use consume(transcript:activeRange:stableLineCount:) with TranscriptRenderer.activeStreamingStableLineCount — the drop-last heuristic duplicates lines when mid-stream re-renders change earlier lines. Deprecated in 1.3.0; will be removed in 2.0.")
    public mutating func consume(transcript: [String], activeRange: Range<Int>?) -> [String] {
        let clampedPrintedCount = min(printedTranscriptCount, transcript.count)
        if clampedPrintedCount != printedTranscriptCount {
            printedTranscriptCount = clampedPrintedCount
            printedCompletedStreamingLines = []
        }

        if let activeRange {
            let stableUpperBound = min(activeRange.lowerBound, transcript.count)
            // Clamp the active range's upper bound too: callers may hold a
            // stale range after the transcript shrank, and subscripting past
            // `transcript.count` crashes.
            let clampedActiveRange = stableUpperBound..<min(activeRange.upperBound, transcript.count)
            var newLines: [String] = []

            if stableUpperBound > printedTranscriptCount {
                newLines.append(contentsOf: transcript[printedTranscriptCount..<stableUpperBound])
                printedTranscriptCount = stableUpperBound
            }

            let activeLines = Array(transcript[clampedActiveRange])
            let completedLines = activeLines.isEmpty ? [] : Array(activeLines.dropLast())
            let commonPrefixCount = zip(printedCompletedStreamingLines, completedLines)
                .prefix { $0 == $1 }
                .count

            if completedLines.count > commonPrefixCount {
                let appendedCompletedLines = Array(completedLines.dropFirst(commonPrefixCount))
                newLines.append(contentsOf: appendedCompletedLines)
                printedTranscriptCount += appendedCompletedLines.count
            }

            printedCompletedStreamingLines = completedLines
            return newLines
        }

        printedCompletedStreamingLines = []
        guard transcript.count > printedTranscriptCount else { return [] }
        let newLines = Array(transcript[printedTranscriptCount..<transcript.count])
        printedTranscriptCount = transcript.count
        return newLines
    }
}
