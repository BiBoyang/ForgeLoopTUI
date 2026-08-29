import XCTest
@testable import ForgeLoopTUI

final class StreamingTranscriptAppendStateTests: XCTestCase {
    func testConsumeAppendsSettledPrefixBeforeStreamingBlock() {
        var state = StreamingTranscriptAppendState()
        let transcript = ["❯ prompt", "", "partial"]

        let emitted = state.consume(transcript: transcript, activeRange: 2..<3, stableLineCount: 0)

        XCTAssertEqual(emitted, ["❯ prompt", ""])
    }

    func testConsumeEmitsOnlyEngineCertifiedStableLinesInsideBlock() {
        var state = StreamingTranscriptAppendState()

        // stableLineCount 0: nothing inside the block is committed, even
        // though the legacy heuristic would have committed "line1".
        let first = state.consume(
            transcript: ["❯ prompt", "", "line1", "partial"],
            activeRange: 2..<4,
            stableLineCount: 0
        )
        XCTAssertEqual(first, ["❯ prompt", ""])

        // Once the engine certifies one stable line, exactly that line lands.
        let second = state.consume(
            transcript: ["❯ prompt", "", "line1", "partial"],
            activeRange: 2..<4,
            stableLineCount: 1
        )
        XCTAssertEqual(second, ["line1"])

        // Already printed: never emitted again.
        let third = state.consume(
            transcript: ["❯ prompt", "", "line1", "partial", "more"],
            activeRange: 2..<5,
            stableLineCount: 1
        )
        XCTAssertEqual(third, [])
    }

    func testConsumeNeverRewindsWhenStableLineCountShrinks() {
        var state = StreamingTranscriptAppendState()

        _ = state.consume(
            transcript: ["a", "b", "c", "d"],
            activeRange: 1..<4,
            stableLineCount: 2
        )

        // A buggy or resetting engine reporting a smaller stable count must
        // not cause re-emission; the printed watermark only moves forward.
        let emitted = state.consume(
            transcript: ["a", "b", "c", "d"],
            activeRange: 1..<4,
            stableLineCount: 1
        )
        XCTAssertEqual(emitted, [])

        // …and forward progress resumes exactly at the watermark.
        let resumed = state.consume(
            transcript: ["a", "b", "c", "d"],
            activeRange: 1..<4,
            stableLineCount: 3
        )
        XCTAssertEqual(resumed, ["d"])
    }

    func testConsumeFlushesRemainingLinesWhenStreamingEnds() {
        var state = StreamingTranscriptAppendState()

        let duringStreaming = state.consume(
            transcript: ["❯ prompt", "", "line1", "partial"],
            activeRange: 2..<4,
            stableLineCount: 1
        )
        let emitted = state.consume(
            transcript: ["❯ prompt", "", "line1", "partial", ""],
            activeRange: nil,
            stableLineCount: 0
        )

        XCTAssertEqual(duringStreaming, ["❯ prompt", "", "line1"])
        XCTAssertEqual(emitted, ["partial", ""])
    }

    func testConsumeClampsActiveRangeUpperBoundBeyondTranscriptEnd() {
        var state = StreamingTranscriptAppendState()

        // The streaming block claims lines 2..<6, but the transcript only has
        // 3 lines. Must clamp instead of crashing on the out-of-bounds
        // subscript.
        let emitted = state.consume(
            transcript: ["❯ prompt", "", "partial"],
            activeRange: 2..<6,
            stableLineCount: 5
        )

        XCTAssertEqual(emitted, ["❯ prompt", "", "partial"])
    }

    func testConsumeFullyStaleActiveRangeAfterTranscriptShrank() {
        var state = StreamingTranscriptAppendState()
        _ = state.consume(transcript: ["a", "b", "c"], activeRange: nil, stableLineCount: 0)

        // Transcript shrank; a stale range lying entirely past the end must
        // not crash and must not emit anything.
        let emitted = state.consume(transcript: ["a"], activeRange: 2..<5, stableLineCount: 2)

        XCTAssertEqual(emitted, [])
    }

    func testConsumeClampsWatermarkAfterTranscriptShrink() {
        var state = StreamingTranscriptAppendState()

        _ = state.consume(
            transcript: ["prompt", "s1", "s2", "partial"],
            activeRange: 1..<4,
            stableLineCount: 2
        )

        // The transcript shrank below the watermark (e.g. blockCancel
        // replaced the block with a marker). The shrink itself emits nothing…
        let shrinkFlush = state.consume(
            transcript: ["prompt", "x"],
            activeRange: nil,
            stableLineCount: 0
        )
        XCTAssertEqual(shrinkFlush, [])

        // …but the watermark clamps, so lines appended afterwards are not
        // swallowed by the stale count.
        let regrown = state.consume(
            transcript: ["prompt", "x", "next1", "next2"],
            activeRange: nil,
            stableLineCount: 0
        )
        XCTAssertEqual(regrown, ["next1", "next2"])
    }
}
