import Testing
@testable import ForgeLoopTUI

// MARK: - No budget

@Test func testNoBudgetPreservesAllLines() {
    let composer = FrameComposer(
        committed: [AnyComponent(TextInputComponent(prompt: "C: ", value: "1"))],
        live: [AnyComponent(TextInputComponent(prompt: "L: ", value: "2"))]
    )
    let frame = composer.render(width: 80)
    #expect(frame.committed == ["C: 1"])
    #expect(frame.live == ["L: 2"])
}

// MARK: - Budget clips committed head

@Test func testBudgetClipsCommittedHeadKeepsLiveTail() {
    let composer = FrameComposer(
        committed: [
            AnyComponent(TextInputComponent(prompt: "C1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "C2: ", value: "b")),
            AnyComponent(TextInputComponent(prompt: "C3: ", value: "c"))
        ],
        live: [
            AnyComponent(TextInputComponent(prompt: "L1: ", value: "x"))
        ],
        layoutBudget: LayoutBudget(maxRows: 3)
    )
    let frame = composer.render(width: 80)
    // live uses 1 row, committed gets remaining 2 rows → C2 + C3
    #expect(frame.committed.count == 2)
    #expect(frame.committed[0] == "C2: b")
    #expect(frame.committed[1] == "C3: c")
    #expect(frame.live == ["L1: x"])
}

// MARK: - Live alone exceeds budget

@Test func testBudgetClipsLiveHeadWhenLiveExceedsBudget() {
    let composer = FrameComposer(
        committed: [AnyComponent(TextInputComponent(prompt: "C: ", value: "stay"))],
        live: [
            AnyComponent(TextInputComponent(prompt: "L1: ", value: "old")),
            AnyComponent(TextInputComponent(prompt: "L2: ", value: "new"))
        ],
        layoutBudget: LayoutBudget(maxRows: 1)
    )
    let frame = composer.render(width: 80)
    // live uses 2 rows, budget is 1 → committed dropped, live clipped to L2
    #expect(frame.committed.isEmpty)
    #expect(frame.live.count == 1)
    #expect(frame.live[0] == "L2: new")
}

// MARK: - Physical rows (wrap case)

@Test func testBudgetUsesPhysicalRowsNotLogicalLines() {
    // A 120-char line at width 40 wraps to 3 physical rows.
    let longLine = String(repeating: "x", count: 120)
    let composer = FrameComposer(
        committed: [AnyComponent(TextInputComponent(prompt: "", value: longLine))],
        live: [],
        layoutBudget: LayoutBudget(maxRows: 2)
    )
    let frame = composer.render(width: 40)
    // 3 physical rows > budget 2 → committed clipped to empty
    #expect(frame.committed.isEmpty)
    #expect(frame.live.isEmpty)
}

@Test func testBudgetWrapCaseKeepsTail() {
    let short = String(repeating: "a", count: 40)  // 1 row @ width 40
    let long = String(repeating: "b", count: 120)  // 3 rows @ width 40
    let composer = FrameComposer(
        committed: [],
        live: [
            AnyComponent(TextInputComponent(prompt: "", value: short)),
            AnyComponent(TextInputComponent(prompt: "", value: long))
        ],
        layoutBudget: LayoutBudget(maxRows: 3)
    )
    let frame = composer.render(width: 40)
    // total 4 physical rows, budget 3 → short (1 row) is clipped, keep long (3 rows)
    #expect(frame.committed.isEmpty)
    #expect(frame.live.count == 1)
    #expect(frame.live[0] == long)
}

// MARK: - Overflow marker

@Test func testMarkerAppearsOnlyWhenClipped() {
    let composer = FrameComposer(
        committed: [
            AnyComponent(TextInputComponent(prompt: "C1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "C2: ", value: "b"))
        ],
        live: [],
        layoutBudget: LayoutBudget(maxRows: 2, overflowMarker: "…")
    )
    // total 2 rows == budget → no clipping, no marker
    let frame = composer.render(width: 80)
    #expect(frame.committed == ["C1: a", "C2: b"])
}

@Test func testMarkerAppearsWhenCommittedClipped() {
    let composer = FrameComposer(
        committed: [
            AnyComponent(TextInputComponent(prompt: "C1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "C2: ", value: "b")),
            AnyComponent(TextInputComponent(prompt: "C3: ", value: "c"))
        ],
        live: [],
        layoutBudget: LayoutBudget(maxRows: 2, overflowMarker: "…")
    )
    let frame = composer.render(width: 80)
    #expect(frame.committed.count == 2)
    #expect(frame.committed[0] == "…")
    #expect(frame.committed[1] == "C3: c")
}

@Test func testMarkerAppearsWhenLiveClipped() {
    let composer = FrameComposer(
        committed: [],
        live: [
            AnyComponent(TextInputComponent(prompt: "L1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "L2: ", value: "b")),
            AnyComponent(TextInputComponent(prompt: "L3: ", value: "c"))
        ],
        layoutBudget: LayoutBudget(maxRows: 2, overflowMarker: "…")
    )
    let frame = composer.render(width: 80)
    #expect(frame.live.count == 2)
    #expect(frame.live[0] == "…")
    #expect(frame.live[1] == "L3: c")
}

@Test func testNoMarkerWhenClippedButDisabled() {
    let composer = FrameComposer(
        committed: [
            AnyComponent(TextInputComponent(prompt: "C1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "C2: ", value: "b"))
        ],
        live: [],
        layoutBudget: LayoutBudget(maxRows: 1, overflowMarker: nil)
    )
    let frame = composer.render(width: 80)
    #expect(frame.committed.count == 1)
    #expect(frame.committed[0] == "C2: b")
}

// MARK: - Cursor offset passthrough

@Test func testCursorOffsetPassedThrough() {
    let composer = FrameComposer(
        live: [AnyComponent(TextInputComponent(prompt: "> ", value: "abc"))],
        layoutBudget: LayoutBudget(maxRows: 5)
    )
    let frame = composer.render(width: 80, cursorOffset: 7)
    #expect(frame.cursorOffset == 7)
}

// MARK: - liveOverflow .settleThenClip

@Test func testSettleThenClipMovesLiveHeadIntoCommitted() {
    // Live exceeds maxRows alone; with .settleThenClip the head live lines
    // become part of committed before tail-clip.
    let composer = FrameComposer(
        committed: [],
        live: [
            AnyComponent(TextInputComponent(prompt: "L1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "L2: ", value: "b")),
            AnyComponent(TextInputComponent(prompt: "L3: ", value: "c")),
            AnyComponent(TextInputComponent(prompt: "L4: ", value: "d"))
        ],
        layoutBudget: LayoutBudget(maxRows: 2, liveOverflow: .settleThenClip)
    )
    let frame = composer.render(width: 80)
    // Settle: live=4 rows > 2 → settle L1,L2 → committed=[L1,L2], live=[L3,L4].
    // Then total=4 > 2; clipTail prioritises live tail → committed dropped, live kept.
    #expect(frame.committed.isEmpty)
    #expect(frame.live.count == 2)
    #expect(frame.live[0] == "L3: c")
    #expect(frame.live[1] == "L4: d")
}

@Test func testSettleThenClipStillRespectsFinalTailClip() {
    // Live exceeds maxRows; .settleThenClip promotes head live lines into
    // committed, but the subsequent tail-clip still drops them because the
    // consolidated buffer (committed + live) remains over budget and the
    // clip pass prioritises the live tail. This documents that settlement
    // does not bypass the final clip — it only changes which lines are
    // treated as committed history while the clip runs.
    let composer = FrameComposer(
        committed: [],
        live: [
            AnyComponent(TextInputComponent(prompt: "L1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "L2: ", value: "b")),
            AnyComponent(TextInputComponent(prompt: "L3: ", value: "c"))
        ],
        layoutBudget: LayoutBudget(maxRows: 2, liveOverflow: .settleThenClip)
    )
    let frame = composer.render(width: 80)
    // Settle: live=3 > 2 → settle L1 → live=[L2,L3] (2 rows).
    // Total=3 > 2; clipTail keeps live=2 fully and gives committed budget=0,
    // so the settled L1 is dropped on the way out. Same visible outcome as
    // .clipOnly, but the intermediate commit/live shape is well-defined.
    #expect(frame.committed.isEmpty)
    #expect(frame.live == ["L2: b", "L3: c"])
}

@Test func testClipOnlyPreservedAsDefault() {
    let composer = FrameComposer(
        committed: [],
        live: [
            AnyComponent(TextInputComponent(prompt: "L1: ", value: "a")),
            AnyComponent(TextInputComponent(prompt: "L2: ", value: "b")),
            AnyComponent(TextInputComponent(prompt: "L3: ", value: "c"))
        ],
        layoutBudget: LayoutBudget(maxRows: 2)
    )
    let frame = composer.render(width: 80)
    // Default is clipOnly; same outcome as before this refactor.
    #expect(frame.committed.isEmpty)
    #expect(frame.live == ["L2: b", "L3: c"])
}

@Test func testSettleThenClipUnderBudgetIsNoop() {
    let composer = FrameComposer(
        committed: [AnyComponent(TextInputComponent(prompt: "C: ", value: "history"))],
        live: [AnyComponent(TextInputComponent(prompt: "L: ", value: "now"))],
        layoutBudget: LayoutBudget(maxRows: 5, liveOverflow: .settleThenClip)
    )
    let frame = composer.render(width: 80)
    #expect(frame.committed == ["C: history"])
    #expect(frame.live == ["L: now"])
}
