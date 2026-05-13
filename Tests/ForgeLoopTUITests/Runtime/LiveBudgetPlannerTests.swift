import Testing
@testable import ForgeLoopTUI

@Suite("LiveBudgetPlanner")
struct LiveBudgetPlannerTests {

    // MARK: - Budget 0 / empty input

    @Test("budget = 0 returns inputs unchanged")
    func testBudgetZeroIsNoop() {
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 0, width: 80)
        let plan = planner.plan(committed: ["c1"], live: ["l1", "l2"])
        #expect(plan.committed == ["c1"])
        #expect(plan.live == ["l1", "l2"])
    }

    @Test("empty live returns inputs unchanged")
    func testEmptyLive() {
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 2, width: 80)
        let plan = planner.plan(committed: ["c1"], live: [])
        #expect(plan.committed == ["c1"])
        #expect(plan.live == [])
    }

    // MARK: - logicalLines mode

    @Test("logicalLines: live within budget = no settle")
    func testLogicalNoSettle() {
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 2, width: 80)
        let plan = planner.plan(committed: ["c1"], live: ["l1", "l2"])
        #expect(plan.committed == ["c1"])
        #expect(plan.live == ["l1", "l2"])
    }

    @Test("logicalLines: settles head overflow into committed")
    func testLogicalSettleOverflow() {
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 2, width: 80)
        let plan = planner.plan(committed: ["c1"], live: ["l1", "l2", "l3", "l4"])
        // Live=4 > budget=2 → settle l1, l2 into committed tail; live keeps last 2.
        #expect(plan.committed == ["c1", "l1", "l2"])
        #expect(plan.live == ["l3", "l4"])
    }

    @Test("logicalLines: matches historical TUI semantics for budget=2")
    func testLogicalMatchesHistorical() {
        // Mirror the case in CommittedLiveRenderTests where prior behaviour was
        // committed += live.prefix(overflow); live = live.suffix(budget).
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 2, width: 80)
        let plan = planner.plan(committed: ["c1"], live: ["l1", "l2", "l3", "l4", "l5", "l6"])
        // overflow=4: l1,l2,l3,l4 → committed; live=l5,l6
        #expect(plan.committed == ["c1", "l1", "l2", "l3", "l4"])
        #expect(plan.live == ["l5", "l6"])
    }

    // MARK: - physicalRows mode

    @Test("physicalRows: budget counts wrap, not logical lines")
    func testPhysicalCountsWrap() {
        let wide = String(repeating: "x", count: 30) // 30/20 = 2 rows @ width=20
        let planner = LiveBudgetPlanner(mode: .physicalRows, budget: 2, width: 20)
        // live: [wide(2), wide(2), short(1)] = 5 rows; budget=2.
        // After settling wide(2) → remaining=[wide,short]=3 rows > 2 → settle wide(2) → remaining=[short]=1.
        let plan = planner.plan(committed: [], live: [wide, wide, "tail"])
        #expect(plan.committed == [wide, wide])
        #expect(plan.live == ["tail"])
    }

    @Test("physicalRows: preserves at least one live line even if it overflows alone")
    func testPhysicalPreservesLastLine() {
        let huge = String(repeating: "y", count: 200) // 10 rows @ width=20
        let planner = LiveBudgetPlanner(mode: .physicalRows, budget: 2, width: 20)
        let plan = planner.plan(committed: [], live: [huge])
        #expect(plan.committed == [])
        #expect(plan.live == [huge])
    }

    @Test("physicalRows: live within budget = no settle")
    func testPhysicalNoSettle() {
        let planner = LiveBudgetPlanner(mode: .physicalRows, budget: 4, width: 80)
        let plan = planner.plan(committed: ["c1"], live: ["l1", "l2"])
        #expect(plan.committed == ["c1"])
        #expect(plan.live == ["l1", "l2"])
    }

    // MARK: - resize equivalence (width change ⇒ different settle decision)

    @Test("physicalRows: width shrink triggers additional settle on same content")
    func testPhysicalResizeShrinks() {
        let content = ["abcdefghij", "klmnopqrst", "uvwxyz0123"]
        // width=10: 3 lines × 1 row = 3 rows
        let plannerWide = LiveBudgetPlanner(mode: .physicalRows, budget: 3, width: 10)
        let planWide = plannerWide.plan(committed: [], live: content)
        // total=3 == budget → no settle
        #expect(planWide.committed == [])
        #expect(planWide.live == content)

        // width=5 (resize): each 10-char line wraps to 2 rows → 6 rows
        let plannerNarrow = LiveBudgetPlanner(mode: .physicalRows, budget: 3, width: 5)
        let planNarrow = plannerNarrow.plan(committed: [], live: content)
        // total=6 > 3 → settle [0] → remaining=[1,2] (4 rows) > 3 → settle [1] → remaining=[2] (count=1, stop)
        #expect(planNarrow.committed == [content[0], content[1]])
        #expect(planNarrow.live == [content[2]])
    }

    @Test("physicalRows: width grow allows previously settled content to stay live")
    func testPhysicalResizeGrows() {
        let line = String(repeating: "z", count: 20)
        // width=10: each line = 2 rows. Two lines = 4 rows.
        let narrow = LiveBudgetPlanner(mode: .physicalRows, budget: 3, width: 10)
        let planNarrow = narrow.plan(committed: [], live: [line, line])
        // 4 > 3 → settle head → remaining=[line]=2, count=1 stop
        #expect(planNarrow.committed == [line])
        #expect(planNarrow.live == [line])

        // width=20: each line = 1 row. Two lines = 2 rows ≤ budget=3 → no settle.
        let wide = LiveBudgetPlanner(mode: .physicalRows, budget: 3, width: 20)
        let planWide = wide.plan(committed: [], live: [line, line])
        #expect(planWide.committed == [])
        #expect(planWide.live == [line, line])
    }

    // MARK: - Order invariants

    @Test("settled head order is preserved when appended to committed tail")
    func testSettleOrderPreserved() {
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 1, width: 80)
        let plan = planner.plan(committed: ["c1", "c2"], live: ["a", "b", "c"])
        // settle a then b → committed=[c1,c2,a,b], live=[c]
        #expect(plan.committed == ["c1", "c2", "a", "b"])
        #expect(plan.live == ["c"])
    }
}
