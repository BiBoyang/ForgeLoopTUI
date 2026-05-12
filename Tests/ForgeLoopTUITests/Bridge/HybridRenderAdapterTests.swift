import Testing
@testable import ForgeLoopTUI

// MARK: - HybridRenderAdapter Contract Tests

@Suite("HybridRenderAdapter")
struct HybridRenderAdapterTests {

    private let adapter = HybridRenderAdapter()

    // MARK: 1) Same input produces both terminal and appkit projections

    @Test func testSameInputProducesBothProjections() {
        let state = HybridRenderState(
            headerLines: ["Header"],
            transcriptLines: ["T1", "T2"],
            queueLines: ["Q1"],
            statusLines: ["Status"],
            inputLines: ["> "],
            panelMeta: PanelMeta(title: "Demo", summary: "2 msgs", statusBadge: "Ready", isActive: false)
        )
        let config = ScreenLayoutConfig(terminalHeight: 24, terminalWidth: 80, showHeader: true)

        let (terminal, appKit) = adapter.renderBoth(state: state, config: config)

        // Terminal must contain the header in committed output.
        #expect(terminal.committed.contains("Header"))
        // AppKit must preserve the title from panelMeta.
        #expect(appKit.meta.title == "Demo")
        // Both derive from the same transcript lines.
        #expect(terminal.committed.contains("T1"))
        #expect(appKit.transcriptLines == ["T1", "T2"])
    }

    // MARK: 2) committed/live/cursorOffset in terminal projection remain correct

    @Test func testTerminalProjectionPreservesCommittedLiveAndCursor() {
        let state = HybridRenderState(
            transcriptLines: ["old1", "old2"],
            inputLines: ["> hello"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 10, terminalWidth: 80, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config, cursorOffset: 7)

        #expect(frame.committed == ["old1", "old2"])
        #expect(frame.live == ["", "> hello"])
        #expect(frame.cursorOffset == 7)
    }

    @Test func testTerminalProjectionEmptyInputHasNoLive() {
        let state = HybridRenderState(
            transcriptLines: ["only committed"],
            inputLines: []
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)

        let frame = adapter.renderTerminal(state: state, config: config)

        #expect(frame.live.isEmpty)
        #expect(frame.cursorOffset == nil)
    }

    // MARK: 3) AppKit projection fields are stable

    @Test func testAppKitProjectionPreservesMetaFields() {
        let meta = PanelMeta(
            title: "Test Panel",
            summary: "3 items",
            statusBadge: "Streaming",
            isActive: true
        )
        let state = HybridRenderState(
            transcriptLines: ["a", "b", "c"],
            queueLines: ["pending"],
            statusLines: ["ok"],
            inputLines: ["input"],
            panelMeta: meta
        )

        let appKit = adapter.appKitProjection(of: state)

        #expect(appKit.meta.title == "Test Panel")
        #expect(appKit.meta.summary == "3 items")
        #expect(appKit.meta.statusBadge == "Streaming")
        #expect(appKit.meta.isActive == true)
    }

    @Test func testAppKitProjectionMapsInputFocusWhenInputPresent() {
        let stateWithInput = HybridRenderState(inputLines: ["> "])
        let stateWithoutInput = HybridRenderState(inputLines: [])

        #expect(adapter.appKitProjection(of: stateWithInput).inputFocused == true)
        #expect(adapter.appKitProjection(of: stateWithoutInput).inputFocused == false)
    }

    @Test func testAppKitProjectionDefaultsMetaWhenNil() {
        let state = HybridRenderState(transcriptLines: ["x"])
        let appKit = adapter.appKitProjection(of: state)

        #expect(appKit.meta.title == "")
        #expect(appKit.meta.summary == "")
        #expect(appKit.meta.statusBadge == "")
        #expect(appKit.meta.isActive == false)
    }

    // MARK: 4) Pinned / budget scenarios do not regress terminal projection

    @Test func testPinnedRangePreservesStreamingBlockUnderBudget() {
        let state = HybridRenderState(
            transcriptLines: ["before", "pin1", "pin2", "after"],
            pinnedTranscriptRange: 1..<3
        )
        let config = ScreenLayoutConfig(terminalHeight: 4, terminalWidth: 80, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config)

        // Budget sufficient for all 4 lines → everything kept.
        #expect(frame.committed == ["before", "pin1", "pin2", "after"])
    }

    @Test func testPinnedRangeSacrificesNonPinnedWhenBudgetTight() {
        let state = HybridRenderState(
            transcriptLines: ["old1", "old2", "pin1", "pin2"],
            pinnedTranscriptRange: 2..<4
        )
        let config = ScreenLayoutConfig(terminalHeight: 3, terminalWidth: 80, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config)

        // Budget = 3, pinned = 2 lines. Non-pinned closest to pinned kept first.
        #expect(frame.committed == ["old2", "pin1", "pin2"])
    }

    @Test func testBudgetClipsLiveWhenInputExceedsHeight() {
        let state = HybridRenderState(
            transcriptLines: (0..<20).map { "t\($0)" },
            inputLines: ["> line1", "> line2"]
        )
        let config = ScreenLayoutConfig(terminalHeight: 5, terminalWidth: 80, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config)

        // Live has highest priority, so input + divider should consume budget first.
        // Input = 2 lines + 1 divider = 3 physical rows.
        // Remaining 2 rows go to committed tail.
        #expect(frame.live == ["", "> line1", "> line2"])
        #expect(frame.committed.count == 2)
        #expect(frame.committed.last == "t19")
    }

    // MARK: 5) Empty state and boundary inputs do not crash

    @Test func testEmptyStateProducesEmptyTerminalAndAppKit() {
        let state = HybridRenderState()
        let config = ScreenLayoutConfig(terminalHeight: 24)

        let (terminal, appKit) = adapter.renderBoth(state: state, config: config)

        #expect(terminal.committed.isEmpty)
        #expect(terminal.live.isEmpty)
        #expect(terminal.cursorOffset == nil)
        #expect(appKit.transcriptLines.isEmpty)
        #expect(appKit.inputLines.isEmpty)
        #expect(appKit.meta.title == "")
    }

    @Test func testZeroHeightBudgetDoesNotCrash() {
        let state = HybridRenderState(
            transcriptLines: ["a", "b"],
            inputLines: ["> "]
        )
        let config = ScreenLayoutConfig(terminalHeight: 0, terminalWidth: 80, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config)

        // With zero budget, nothing fits.
        #expect(frame.committed.isEmpty)
        #expect(frame.live.isEmpty)
    }

    @Test func testVeryLargeTranscriptDoesNotCrash() {
        let state = HybridRenderState(
            transcriptLines: (0..<10_000).map { "line\($0)" }
        )
        let config = ScreenLayoutConfig(terminalHeight: 10)

        let frame = adapter.renderTerminal(state: state, config: config)

        #expect(frame.committed.count == 10)
        #expect(frame.committed.first == "line9990")
        #expect(frame.committed.last == "line9999")
    }

    // MARK: 6) Degradation paths

    @Test("negative width budget returns empty frame")
    func testNegativeWidthBudgetReturnsEmptyFrame() {
        let state = HybridRenderState(transcriptLines: ["a", "b"])
        let config = ScreenLayoutConfig(terminalHeight: 10, terminalWidth: -1, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config)

        #expect(frame.committed.isEmpty)
        #expect(frame.live.isEmpty)
        #expect(frame.cursorOffset == nil)
    }

    @Test("negative height budget returns empty frame")
    func testNegativeHeightBudgetReturnsEmptyFrame() {
        let state = HybridRenderState(transcriptLines: ["a", "b"])
        let config = ScreenLayoutConfig(terminalHeight: -5, terminalWidth: 80, showHeader: false)

        let frame = adapter.renderTerminal(state: state, config: config)

        #expect(frame.committed.isEmpty)
        #expect(frame.live.isEmpty)
        #expect(frame.cursorOffset == nil)
    }

    // MARK: 7) PanelMeta new fields

    @Test("appKit projection preserves subtitle and accessory")
    func testAppKitProjectionPreservesSubtitleAndAccessory() {
        let meta = PanelMeta(
            title: "T",
            summary: "S",
            statusBadge: "B",
            isActive: true,
            subtitle: "gpt-4o",
            accessoryBadge: "Beta"
        )
        let state = HybridRenderState(panelMeta: meta)
        let appKit = adapter.appKitProjection(of: state)

        #expect(appKit.meta.subtitle == "gpt-4o")
        #expect(appKit.meta.accessoryBadge == "Beta")
    }

    @Test("appKit projection nil subtitle and accessory does not affect existing behavior")
    func testAppKitProjectionNilSubtitleAndAccessory() {
        let meta = PanelMeta(title: "T", summary: "S", statusBadge: "B", isActive: false)
        let state = HybridRenderState(panelMeta: meta)
        let appKit = adapter.appKitProjection(of: state)

        #expect(appKit.meta.title == "T")
        #expect(appKit.meta.summary == "S")
        #expect(appKit.meta.statusBadge == "B")
        #expect(appKit.meta.isActive == false)
        #expect(appKit.meta.subtitle == nil)
        #expect(appKit.meta.accessoryBadge == nil)
    }

    // MARK: 8) Dual projection consistency (same source, no divergence)

    @Test func testDualProjectionTranscriptConsistency() {
        let state = HybridRenderState(
            transcriptLines: ["shared1", "shared2"],
            inputLines: ["input"],
            panelMeta: PanelMeta(title: "Same", summary: "Same", statusBadge: "Same")
        )
        let config = ScreenLayoutConfig(terminalHeight: 24)

        let (terminal, appKit) = adapter.renderBoth(state: state, config: config)

        // Terminal committed contains transcript; AppKit carries same lines.
        #expect(terminal.committed.contains("shared1"))
        #expect(terminal.committed.contains("shared2"))
        #expect(appKit.transcriptLines == ["shared1", "shared2"])
    }
}
