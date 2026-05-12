import Testing
@testable import ForgeLoopTUI

@Suite("HybridObservableState")
struct HybridObservableStateTests {

    // MARK: - Initialization

    @Test("default init produces empty fields")
    @MainActor
    func testDefaultInit() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState()
        #expect(state.transcriptLines.isEmpty)
        #expect(state.inputLines.isEmpty)
        #expect(state.statusLines.isEmpty)
        #expect(state.queueLines.isEmpty)
        #expect(state.headerLines.isEmpty)
        #expect(state.panelMeta == PanelMeta())
        #expect(state.isInputFocused == false)
    }

    @Test("custom init preserves provided state")
    @MainActor
    func testCustomInit() {
        guard #available(macOS 14, *) else { return }
        let initial = HybridRenderState(
            headerLines: ["H"],
            transcriptLines: ["T"],
            queueLines: ["Q"],
            statusLines: ["S"],
            inputLines: [">"],
            panelMeta: PanelMeta(title: "Demo")
        )
        let state = HybridObservableState(initialState: initial)
        #expect(state.headerLines == ["H"])
        #expect(state.transcriptLines == ["T"])
        #expect(state.queueLines == ["Q"])
        #expect(state.statusLines == ["S"])
        #expect(state.inputLines == [">"])
        #expect(state.panelMeta.title == "Demo")
        #expect(state.isInputFocused == true)
    }

    // MARK: - Full state update

    @Test("update replaces entire state")
    @MainActor
    func testUpdateReplacesState() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState()
        let newState = HybridRenderState(
            headerLines: ["H1"],
            transcriptLines: ["T1"],
            inputLines: ["I1"]
        )
        state.update(newState)
        #expect(state.headerLines == ["H1"])
        #expect(state.transcriptLines == ["T1"])
        #expect(state.inputLines == ["I1"])
    }

    @Test("update to empty state clears all fields")
    @MainActor
    func testUpdateToEmptyState() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState(initialState: HybridRenderState(transcriptLines: ["x"]))
        state.update(HybridRenderState())
        #expect(state.transcriptLines.isEmpty)
        #expect(state.inputLines.isEmpty)
        #expect(state.isInputFocused == false)
    }

    // MARK: - Granular field updates

    @Test("updateTranscript changes only transcript")
    @MainActor
    func testUpdateTranscript() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState(initialState: HybridRenderState(statusLines: ["S"]))
        state.updateTranscript(["T1", "T2"])
        #expect(state.transcriptLines == ["T1", "T2"])
        #expect(state.statusLines == ["S"])
    }

    @Test("updateInput changes input and affects isInputFocused")
    @MainActor
    func testUpdateInput() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState()
        state.updateInput(["> "])
        #expect(state.inputLines == ["> "])
        #expect(state.isInputFocused == true)
    }

    @Test("updateStatus changes only status")
    @MainActor
    func testUpdateStatus() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState(initialState: HybridRenderState(transcriptLines: ["T"]))
        state.updateStatus(["S1"])
        #expect(state.statusLines == ["S1"])
        #expect(state.transcriptLines == ["T"])
    }

    @Test("updateQueue changes only queue")
    @MainActor
    func testUpdateQueue() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState(initialState: HybridRenderState(transcriptLines: ["T"]))
        state.updateQueue(["Q1"])
        #expect(state.queueLines == ["Q1"])
        #expect(state.transcriptLines == ["T"])
    }

    @Test("updateHeader changes only header")
    @MainActor
    func testUpdateHeader() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState(initialState: HybridRenderState(transcriptLines: ["T"]))
        state.updateHeader(["H1"])
        #expect(state.headerLines == ["H1"])
        #expect(state.transcriptLines == ["T"])
    }

    @Test("updateMeta changes panelMeta")
    @MainActor
    func testUpdateMeta() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState()
        let meta = PanelMeta(title: "New", summary: "Sum", statusBadge: "Ready", isActive: true)
        state.updateMeta(meta)
        #expect(state.panelMeta == meta)
    }

    @Test("updatePinnedRange sets and clears range")
    @MainActor
    func testUpdatePinnedRange() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState()
        state.updatePinnedRange(2..<5)
        #expect(state.state.pinnedTranscriptRange == 2..<5)
        state.updatePinnedRange(nil)
        #expect(state.state.pinnedTranscriptRange == nil)
    }

    // MARK: - Computed property consistency

    @Test("computed properties match underlying state")
    @MainActor
    func testComputedPropertiesMatchState() {
        guard #available(macOS 14, *) else { return }
        let underlying = HybridRenderState(
            headerLines: ["H"],
            transcriptLines: ["T"],
            queueLines: ["Q"],
            statusLines: ["S"],
            inputLines: [">"],
            panelMeta: PanelMeta(title: "Demo")
        )
        let state = HybridObservableState(initialState: underlying)
        #expect(state.transcriptLines == underlying.transcriptLines)
        #expect(state.inputLines == underlying.inputLines)
        #expect(state.statusLines == underlying.statusLines)
        #expect(state.queueLines == underlying.queueLines)
        #expect(state.headerLines == underlying.headerLines)
        #expect(state.panelMeta == underlying.panelMeta!)
        #expect(state.isInputFocused == !underlying.inputLines.isEmpty)
    }

    // MARK: - Nil PanelMeta fallback

    @Test("panelMeta defaults when underlying is nil")
    @MainActor
    func testPanelMetaDefaultsWhenNil() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState(initialState: HybridRenderState())
        #expect(state.panelMeta == PanelMeta())
    }

    // MARK: - Boundary

    @Test("large dataset update does not crash")
    @MainActor
    func testLargeDatasetNoCrash() {
        guard #available(macOS 14, *) else { return }
        let state = HybridObservableState()
        let lines = (0..<10_000).map { "line\($0)" }
        state.updateTranscript(lines)
        #expect(state.transcriptLines.count == 10_000)
        #expect(state.transcriptLines.first == "line0")
        #expect(state.transcriptLines.last == "line9999")
    }
}
