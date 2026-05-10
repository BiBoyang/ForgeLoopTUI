import Testing
@testable import ForgeLoopTUI

struct ScreenLayoutTests {

    @Test func testDefaultValues() {
        let layout = ScreenLayout()
        #expect(layout.header.isEmpty)
        #expect(layout.transcript.isEmpty)
        #expect(layout.queue.isEmpty)
        #expect(layout.status.isEmpty)
        #expect(layout.input.isEmpty)
        #expect(layout.pinnedTranscriptRange == nil)
    }

    @Test func testFieldPassThrough() {
        let layout = ScreenLayout(
            header: ["H1", "H2"],
            transcript: ["T1", "T2", "T3"],
            queue: ["Q1"],
            status: ["S1", "S2"],
            input: ["> ", "input"],
            pinnedTranscriptRange: 1..<3
        )
        #expect(layout.header == ["H1", "H2"])
        #expect(layout.transcript == ["T1", "T2", "T3"])
        #expect(layout.queue == ["Q1"])
        #expect(layout.status == ["S1", "S2"])
        #expect(layout.input == ["> ", "input"])
        #expect(layout.pinnedTranscriptRange == 1..<3)
    }

    @Test func testConfigDefaults() {
        let config = ScreenLayoutConfig()
        #expect(config.terminalHeight == 24)
        #expect(config.terminalWidth == 80)
        #expect(config.showHeader == true)
    }

    @Test func testConfigCustomValues() {
        let config = ScreenLayoutConfig(
            terminalHeight: 50,
            terminalWidth: 120,
            showHeader: false
        )
        #expect(config.terminalHeight == 50)
        #expect(config.terminalWidth == 120)
        #expect(config.showHeader == false)
    }
}
