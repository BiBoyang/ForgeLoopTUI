import Testing
@testable import ForgeLoopTUI

struct ScreenLayoutRendererTests {

    private let renderer = ScreenLayoutRenderer()

    @Test func testEmptyLayoutReturnsEmpty() {
        let layout = ScreenLayout()
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed.isEmpty)
        #expect(frame.live.isEmpty)
        #expect(frame.cursorOffset == nil)
    }

    @Test func testHeaderOnly() {
        let layout = ScreenLayout(header: ["Header"])
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["Header"])
    }

    @Test func testTranscriptOutputInFull() {
        let layout = ScreenLayout(transcript: ["a", "b", "c"])
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["a", "b", "c"])
    }

    @Test func testLongTranscriptNotTruncated() {
        let layout = ScreenLayout(transcript: (0..<100).map { "line\($0)" })
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed.count == 100)
        #expect(frame.committed.first == "line0")
        #expect(frame.committed.last == "line99")
    }

    @Test func testRenderOrderHeaderTranscriptStatusInput() {
        let layout = ScreenLayout(
            header: ["H"],
            transcript: ["T1", "T2"],
            status: ["S"],
            input: ["I"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)

        #expect(frame.committed == [
            "H",
            "T1", "T2",
            "",   // divider
            "S",
            "",   // divider
            "I",
        ])
    }

    @Test func testStatusAndInputAfterTranscript() {
        let layout = ScreenLayout(
            transcript: ["t1", "t2"],
            status: ["STATUS"],
            input: ["> "]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["t1", "t2", "", "STATUS", "", "> "])
    }

    @Test func testHeaderHiddenWhenShowHeaderFalse() {
        let layout = ScreenLayout(
            header: ["H1", "H2"],
            transcript: ["T"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24, showHeader: false)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["T"])
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
    }

    @Test func testEmptyQueueDoesNotAddDivider() {
        let layout = ScreenLayout(
            transcript: ["t1"],
            status: ["STATUS"],
            input: ["> "]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["t1", "", "STATUS", "", "> "])
    }

    @Test func testPinnedRangeDoesNotAffectOutput() {
        let layout = ScreenLayout(
            transcript: ["old1", "old2", "stream1", "stream2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 3)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.committed == ["old1", "old2", "stream1", "stream2"])
    }

    @Test func testCursorOffsetPassthrough() {
        let layout = ScreenLayout(input: ["> hello"])
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config, cursorOffset: 5)
        #expect(frame.cursorOffset == 5)
    }

    @Test func testLiveIsAlwaysEmpty() {
        let layout = ScreenLayout(
            header: ["H"],
            transcript: ["T"],
            queue: ["Q"],
            status: ["S"],
            input: ["I"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)
        let frame = renderer.render(layout: layout, config: config)
        #expect(frame.live.isEmpty)
    }
}
