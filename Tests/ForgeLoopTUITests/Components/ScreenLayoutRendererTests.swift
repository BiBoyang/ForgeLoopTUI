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

    @Test func testLongTranscriptNotTruncated() {
        let layout = ScreenLayout(transcript: (0..<100).map { "line\($0)" })
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed.count == 100)
        #expect(frame.committed.first == "line0")
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

    @Test func testPinnedRangeDoesNotAffectOutput() {
        let layout = ScreenLayout(
            transcript: ["old1", "old2", "stream1", "stream2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 3)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["old1", "old2", "stream1", "stream2"])
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
