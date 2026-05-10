import Testing
@testable import ForgeLoopTUI

struct ScreenLayoutRendererTests {

    private let renderer = ScreenLayoutRenderer()

    // MARK: - Empty / boundary

    @Test func testEmptyLayoutReturnsEmpty() {
        let layout = ScreenLayout()
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed.isEmpty)
        #expect(frame.live.isEmpty)
        #expect(frame.cursorOffset == nil)
    }

    // MARK: - Committed-only baseline (must not regress)

    @Test func testHeaderOnly() {
        let layout = ScreenLayout(header: ["Header"])
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["Header"])
        #expect(frame.live.isEmpty)
    }

    @Test func testTranscriptOutputInFull() {
        let layout = ScreenLayout(transcript: ["a", "b", "c"])
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["a", "b", "c"])
        #expect(frame.live.isEmpty)
    }

    @Test func testLongTranscriptNotTruncatedWhenBudgetUnlimited() {
        let layout = ScreenLayout(transcript: (0..<100).map { "line\($0)" })
        let config = ScreenLayoutConfig(terminalHeight: 100)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed.count == 100)
        #expect(frame.committed.first == "line0")
        #expect(frame.committed.last == "line99")
        #expect(frame.live.isEmpty)
    }

    @Test func testLongTranscriptTruncatedToTailWhenOverBudget() {
        let layout = ScreenLayout(transcript: (0..<100).map { "line\($0)" })
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed.count == 10)
        #expect(frame.committed.first == "line90")
        #expect(frame.committed.last == "line99")
        #expect(frame.live.isEmpty)
    }

    @Test func testRenderOrderHeaderTranscriptStatusWithoutInput() {
        let layout = ScreenLayout(
            header: ["H"],
            transcript: ["T1", "T2"],
            status: ["S"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        #expect(frame.committed == [
            "H",
            "T1", "T2",
            "",
            "S",
        ])
        #expect(frame.live.isEmpty)
    }

    @Test func testStatusAndInputAfterTranscript() {
        let layout = ScreenLayout(
            transcript: ["t1", "t2"],
            status: ["STATUS"],
            input: ["> "]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["t1", "t2", "", "STATUS"])
        #expect(frame.live == ["", "> "])
    }

    @Test func testHeaderHiddenWhenShowHeaderFalse() {
        let layout = ScreenLayout(
            header: ["H1", "H2"],
            transcript: ["T"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24, showHeader: false)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["T"])
        #expect(frame.live.isEmpty)
    }

    @Test func testQueueRenderedBetweenTranscriptAndStatus() {
        let layout = ScreenLayout(
            transcript: ["t1"],
            queue: ["q1", "q2"],
            status: ["s1"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["t1", "", "q1", "q2", "", "s1"])
        #expect(frame.live.isEmpty)
    }

    @Test func testEmptyQueueDoesNotAddDivider() {
        let layout = ScreenLayout(
            transcript: ["t1"],
            status: ["STATUS"],
            input: ["> "]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["t1", "", "STATUS"])
        #expect(frame.live == ["", "> "])
    }

    @Test func testPinnedRangeDoesNotAffectOutputWhenBudgetSufficient() {
        let layout = ScreenLayout(
            transcript: ["old1", "old2", "stream1", "stream2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 4)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["old1", "old2", "stream1", "stream2"])
        #expect(frame.live.isEmpty)
    }

    @Test func testPinnedRangeClippedWithTranscriptWhenBudgetExceeded() {
        let layout = ScreenLayout(
            transcript: ["old1", "old2", "stream1", "stream2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 3)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["old2", "stream1", "stream2"])
        #expect(frame.live.isEmpty)
    }

    // MARK: - Live region structure

    @Test func testLiveContainsInputWithDividerWhenCommittedPresent() {
        let layout = ScreenLayout(
            header: ["H"],
            transcript: ["T"],
            input: ["I1", "I2"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        #expect(frame.committed == ["H", "T"])
        #expect(frame.live == ["", "I1", "I2"])
    }

    @Test func testLiveContainsInputWithoutDividerWhenCommittedEmpty() {
        let layout = ScreenLayout(input: ["> hello"])
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        #expect(frame.committed.isEmpty)
        #expect(frame.live == ["> hello"])
    }

    @Test func testLiveIsEmptyWhenInputIsEmpty() {
        let layout = ScreenLayout(
            header: ["H"],
            transcript: ["T"],
            status: ["S"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        #expect(frame.live.isEmpty)
    }

    @Test func testLivePreservesMultiLineInput() {
        let layout = ScreenLayout(input: ["line1", "line2", "line3"])
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        #expect(frame.committed.isEmpty)
        #expect(frame.live == ["line1", "line2", "line3"])
    }

    // MARK: - cursorOffset passthrough

    @Test func testCursorOffsetPassthrough() {
        let layout = ScreenLayout(input: ["> hello"])
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config, cursorOffset: 5)
        #expect(frame.cursorOffset == 5)
    }

    @Test func testCursorOffsetWithLiveAndCommitted() {
        let layout = ScreenLayout(
            transcript: ["t1"],
            input: ["> "]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config, cursorOffset: 2)

        #expect(frame.committed == ["t1"])
        #expect(frame.live == ["", "> "])
        #expect(frame.cursorOffset == 2)
    }

    @Test func testCursorOffsetNilWhenOmitted() {
        let layout = ScreenLayout(transcript: ["t1"], input: ["> "])
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.cursorOffset == nil)
    }

    // MARK: - Pinned protection

    @Test func testPinnedPreservedWhenBudgetSufficient() {
        let layout = ScreenLayout(
            transcript: ["old1", "old2", "pin1", "pin2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 4)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["old1", "old2", "pin1", "pin2"])
    }

    @Test func testPinnedPreservedBySacrificingNonPinnedWhenBudgetTight() {
        // Budget = 3, pinned = 2 lines (pin1, pin2). Non-pinned = 2 lines (old1, old2).
        // Expected: drop oldest non-pinned head (old1), keep [old2, pin1, pin2].
        let layout = ScreenLayout(
            transcript: ["old1", "old2", "pin1", "pin2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 3)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["old2", "pin1", "pin2"])
    }

    @Test func testPinnedTailClippedWhenPinnedAloneExceedsBudget() {
        // Budget = 1, pinned = 2 lines. Pinned itself must be tail-clipped.
        let layout = ScreenLayout(
            transcript: ["old1", "pin1", "pin2"],
            pinnedTranscriptRange: 1..<3
        )
        let config = ScreenLayoutConfig(terminalHeight: 1)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["pin2"])
    }

    @Test func testInvalidPinnedRangeSafelyDegradesToNonPinnedPath() {
        // Range out of bounds → behave like B1 (plain tail clip).
        let layout = ScreenLayout(
            transcript: ["a", "b", "c"],
            pinnedTranscriptRange: 5..<10
        )
        let config = ScreenLayoutConfig(terminalHeight: 2)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["b", "c"])
    }

    @Test func testEmptyPinnedRangeDegradesToNonPinnedPath() {
        let layout = ScreenLayout(
            transcript: ["a", "b", "c"],
            pinnedTranscriptRange: 2..<2
        )
        let config = ScreenLayoutConfig(terminalHeight: 2)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["b", "c"])
    }

    @Test func testPinnedDoesNotAffectPathWithNoTranscript() {
        let layout = ScreenLayout(
            header: ["H"],
            status: ["S"],
            input: ["> "],
            pinnedTranscriptRange: 0..<5 // irrelevant because transcript is empty
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["H", "", "S"])
        #expect(frame.live == ["", "> "])
    }

    @Test func testPinnedWithAfterContentPreservesOriginalOrder() {
        // Transcript: [before][pinned][after]
        // Budget tight but enough for pinned + some non-pinned.
        // Non-pinned closest to pinned (after-tail, then before-tail) are kept,
        // but final output must remain in original index order.
        let layout = ScreenLayout(
            transcript: ["b1", "b2", "p1", "p2", "a1", "a2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 5)
        let frame = renderer.render(layout: layout, config: config)
        // non-pinned = b1,b2,a1,a2 (4 lines) + pinned = p1,p2 (2 lines) = 6 total
        // budget 5 → keep pinned (2), then fill 3 from non-pinned closest to pinned:
        //   after-tail: a2 (idx 5), a1 (idx 4) — both fit (2 lines)
        //   before-tail: b2 (idx 1) — fits (1 line)
        //   b1 (idx 0) — dropped
        // Final order must be original index ascending: b2, p1, p2, a1, a2
        #expect(frame.committed == ["b2", "p1", "p2", "a1", "a2"])
    }

    // MARK: - Pinned regression guards (must never regress)

    @Test func testPinnedBudgetSufficientDoesNotReorder() {
        // When budget is sufficient, pinned must not alter the original order.
        let layout = ScreenLayout(
            transcript: ["b1", "b2", "p1", "p2", "a1", "a2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 6)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["b1", "b2", "p1", "p2", "a1", "a2"])
    }

    @Test func testPinnedBudgetTightOutputIsOriginalSubsequence() {
        // When budget is tight, output must still be a subsequence in original order.
        let layout = ScreenLayout(
            transcript: ["b1", "b2", "p1", "p2", "a1", "a2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 4)
        let frame = renderer.render(layout: layout, config: config)
        // budget 4: pinned (2 lines) + after-tail a2,a1 (2 lines) = 4
        // before lines b1,b2 dropped.
        let expected = ["p1", "p2", "a1", "a2"]
        #expect(frame.committed == expected)
        // Verify it is a subsequence of the original transcript.
        var idx = 0
        for line in frame.committed {
            while idx < layout.transcript.count && layout.transcript[idx] != line {
                idx += 1
            }
            #expect(idx < layout.transcript.count, "Output must be a subsequence of original transcript")
            idx += 1
        }
    }

    @Test func testPinnedExceedsBudgetTailClipsWithinPinnedOnly() {
        // When pinned alone exceeds budget, only pinned tail is kept.
        let layout = ScreenLayout(
            transcript: ["old1", "pin1", "pin2", "pin3"],
            pinnedTranscriptRange: 1..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 2)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["pin2", "pin3"])
    }

    @Test func testInvalidPinnedRangeDegradesToPlainTailClip() {
        // Invalid range must behave exactly like B1 (no pinned semantics).
        let layout = ScreenLayout(
            transcript: ["a", "b", "c", "d"],
            pinnedTranscriptRange: 10..<20
        )
        let config = ScreenLayoutConfig(terminalHeight: 2)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["c", "d"])
    }

    // MARK: - Full assembly equivalence

    @Test func testFullAssemblyCommittedPlusLiveEqualsOldFlatOutput() {
        let layout = ScreenLayout(
            header: ["H"],
            transcript: ["T1", "T2"],
            queue: ["Q"],
            status: ["S"],
            input: ["I"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        let flat = frame.committed + frame.live
        #expect(flat == [
            "H",
            "T1", "T2",
            "",
            "Q",
            "",
            "S",
            "",
            "I",
        ])
    }
}
