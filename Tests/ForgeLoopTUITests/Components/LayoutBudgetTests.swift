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
