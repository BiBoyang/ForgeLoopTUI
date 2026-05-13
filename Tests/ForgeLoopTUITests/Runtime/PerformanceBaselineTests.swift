import Foundation
import Testing
@testable import ForgeLoopTUI

/// Performance gates for the hot paths documented in
/// `docs/performance-baseline.md`. These tests are intentionally generous
/// (≈10× local measurements) so they catch algorithmic regressions while
/// remaining stable across CI hardware.
@Suite("PerformanceBaseline")
struct PerformanceBaselineTests {

    private func measure(_ body: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        body()
        return CFAbsoluteTimeGetCurrent() - start
    }

    @Test("LiveBudgetPlanner.plan stays linear on a large live region")
    func testPlannerLinearOnLargeLive() {
        let live = (0..<10_000).map { _ in "abcdefgh" }
        let planner = LiveBudgetPlanner(mode: .logicalLines, budget: 100, width: 80)

        let elapsed = measure {
            for _ in 0..<50 {
                _ = planner.plan(committed: [], live: live)
            }
        }

        // Gate: 50 invocations on 10 000-line live in under 300 ms.
        // Local measurement is <50 ms on M-series in -c release.
        #expect(elapsed < 0.300, "planner regressed: \(elapsed)s for 50×10k-line plans")
    }

    @Test("MultiLineInputState handles long paste plus navigation under budget")
    func testMultiLineInputLongPaste() {
        var state = MultiLineInputState(viewport: Viewport(width: 80))
        let longLine = String(repeating: "x", count: 4_000)

        let elapsed = measure {
            state.handle(.insertText(longLine))
            for _ in 0..<200 {
                state.handle(.moveLeft)
                state.handle(.moveRight)
            }
            for _ in 0..<50 {
                state.handle(.moveUp)
                state.handle(.moveDown)
            }
        }

        // Gate: full sequence in under 150 ms.
        #expect(elapsed < 0.150, "input state regressed: \(elapsed)s")
        // Sanity: state still consistent.
        #expect(state.lines.count == 1)
        #expect(state.cursorColumn <= longLine.count)
    }

    @Test("KeyResolver.feed character passthrough scales linearly")
    func testKeyResolverPassthrough() {
        var registry = KeybindingRegistry<TestAction>()
        try! registry.register(KeySequence(KeyStroke(key: .enter)), action: .alpha)
        try! registry.register(KeySequence(KeyStroke(key: .escape)), action: .beta)
        try! registry.register(KeySequence([
            KeyStroke(key: .character("X"), modifiers: .ctrl),
            KeyStroke(key: .character("S"), modifiers: .ctrl),
        ]), action: .gamma)

        let resolver = KeyResolver(registry: registry)
        let event = KeyEvent(key: .character("a"))

        let elapsed = measure {
            for _ in 0..<5_000 {
                _ = resolver.feed(event)
            }
        }

        // Gate: 5 000 character feeds under 200 ms.
        #expect(elapsed < 0.200, "key resolver regressed: \(elapsed)s for 5k events")
    }

    enum TestAction: Sendable, Equatable {
        case alpha
        case beta
        case gamma
    }
}
