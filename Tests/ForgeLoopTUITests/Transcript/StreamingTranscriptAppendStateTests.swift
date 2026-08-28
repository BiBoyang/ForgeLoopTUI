import XCTest
@testable import ForgeLoopTUI

final class StreamingTranscriptAppendStateTests: XCTestCase {
    func testConsumeAppendsStablePrefixBeforeStreamingBlock() {
        var state = StreamingTranscriptAppendState()
        let transcript = ["❯ prompt", "", "partial"]

        let emitted = state.consume(transcript: transcript, activeRange: 2..<3)

        XCTAssertEqual(emitted, ["❯ prompt", ""])
    }

    func testConsumeDoesNotRepeatGrowingPartialLine() {
        var state = StreamingTranscriptAppendState()

        let first = state.consume(transcript: ["❯ prompt", "", "C"], activeRange: 2..<3)
        let second = state.consume(transcript: ["❯ prompt", "", "CASE"], activeRange: 2..<3)

        XCTAssertEqual(first, ["❯ prompt", ""])
        XCTAssertEqual(second, [])
    }

    func testConsumeAppendsCompletedStreamingLinesOnce() {
        var state = StreamingTranscriptAppendState()

        _ = state.consume(transcript: ["❯ prompt", "", "line1"], activeRange: 2..<3)
        let emitted = state.consume(transcript: ["❯ prompt", "", "line1", "partial"], activeRange: 2..<4)

        XCTAssertEqual(emitted, ["line1"])
    }

    func testConsumeFlushesRemainingLinesWhenStreamingEnds() {
        var state = StreamingTranscriptAppendState()

        let duringStreaming = state.consume(transcript: ["❯ prompt", "", "line1", "partial"], activeRange: 2..<4)
        let emitted = state.consume(transcript: ["❯ prompt", "", "line1", "partial", ""], activeRange: nil)

        XCTAssertEqual(duringStreaming, ["❯ prompt", "", "line1"])
        XCTAssertEqual(emitted, ["partial", ""])
    }

    func testConsumeClampsActiveRangeUpperBoundBeyondTranscriptEnd() {
        var state = StreamingTranscriptAppendState()

        // The streaming block claims lines 2..<6, but the transcript only has
        // 3 lines. Must clamp instead of crashing on the out-of-bounds
        // subscript.
        let emitted = state.consume(transcript: ["❯ prompt", "", "partial"], activeRange: 2..<6)

        XCTAssertEqual(emitted, ["❯ prompt", ""])
    }

    func testConsumeClampedRangeStillEmitsCompletedStreamingLines() {
        var state = StreamingTranscriptAppendState()

        let emitted = state.consume(
            transcript: ["❯ prompt", "", "line1", "partial"],
            activeRange: 2..<8
        )

        XCTAssertEqual(emitted, ["❯ prompt", "", "line1"])
    }

    func testConsumeFullyStaleActiveRangeAfterTranscriptShrank() {
        var state = StreamingTranscriptAppendState()
        _ = state.consume(transcript: ["a", "b", "c"], activeRange: nil)

        // Transcript shrank; a stale range lying entirely past the end must
        // not crash and must not emit anything.
        let emitted = state.consume(transcript: ["a"], activeRange: 2..<5)

        XCTAssertEqual(emitted, [])
    }
}
