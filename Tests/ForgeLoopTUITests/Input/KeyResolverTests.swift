import Testing
@testable import ForgeLoopTUI

@Suite("KeyResolver")
struct KeyResolverTests {

    enum TestAction: Sendable, Equatable {
        case submit
        case insertNewline
        case saveChord
    }

    private func makeResolver(timeoutNanos: UInt64 = 50_000_000) -> (KeyResolver<TestAction>, TestInputClock) {
        var registry = KeybindingRegistry<TestAction>()
        try! registry.register(KeySequence(KeyStroke(key: .enter)), action: .submit)
        try! registry.register(
            KeySequence(KeyStroke(key: .character("O"), modifiers: .ctrl)),
            action: .insertNewline
        )
        try! registry.register(
            KeySequence([
                KeyStroke(key: .character("X"), modifiers: .ctrl),
                KeyStroke(key: .character("S"), modifiers: .ctrl),
            ]),
            action: .saveChord
        )
        let clock = TestInputClock()
        let resolver = KeyResolver(registry: registry, clock: clock, timeoutNanoseconds: timeoutNanos)
        return (resolver, clock)
    }

    private func expectAction(_ results: [ResolvedKey<TestAction>], at index: Int, equals action: TestAction) {
        guard index < results.count else {
            Issue.record("missing result at index \(index)")
            return
        }
        if case .action(let value) = results[index] {
            #expect(value == action)
        } else {
            Issue.record("expected .action(\(action)) at index \(index), got \(results[index])")
        }
    }

    private func expectPassthrough(_ results: [ResolvedKey<TestAction>], at index: Int, equals event: KeyEvent) {
        guard index < results.count else {
            Issue.record("missing result at index \(index)")
            return
        }
        if case .passthrough(let value) = results[index] {
            #expect(value == event)
        } else {
            Issue.record("expected .passthrough(\(event)) at index \(index), got \(results[index])")
        }
    }

    @Test("single-key binding emits action immediately")
    func testSingleKeyExact() {
        let (resolver, _) = makeResolver()
        let results = resolver.feed(KeyEvent(key: .enter))
        #expect(results.count == 1)
        expectAction(results, at: 0, equals: .submit)
        #expect(resolver.hasPending == false)
    }

    @Test("non-binding character is passed through unchanged")
    func testCharacterPassthrough() {
        let (resolver, _) = makeResolver()
        let event = KeyEvent(key: .character("a"))
        let results = resolver.feed(event)
        #expect(results.count == 1)
        expectPassthrough(results, at: 0, equals: event)
    }

    @Test("chord prefix buffers until the full chord arrives")
    func testChordPrefixThenExact() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        let sCtrl = KeyEvent(key: .character("S"), modifiers: .ctrl)

        let r1 = resolver.feed(xCtrl)
        #expect(r1.isEmpty)
        #expect(resolver.hasPending == true)

        let r2 = resolver.feed(sCtrl)
        #expect(r2.count == 1)
        expectAction(r2, at: 0, equals: .saveChord)
        #expect(resolver.hasPending == false)
    }

    @Test("prefix timeout flushes pending events as passthrough")
    func testPrefixTimeoutFlush() {
        let (resolver, clock) = makeResolver(timeoutNanos: 50_000_000)
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        _ = resolver.feed(xCtrl)
        #expect(resolver.hasPending == true)

        // Not yet expired.
        clock.advance(by: 10_000_000)
        #expect(resolver.tick().isEmpty)
        #expect(resolver.hasPending == true)

        // Now past the timeout.
        clock.advance(by: 60_000_000)
        let results = resolver.tick()
        #expect(results.count == 1)
        expectPassthrough(results, at: 0, equals: xCtrl)
        #expect(resolver.hasPending == false)
    }

    @Test("pending miss retries the current event as a fresh sequence")
    func testPendingMissRetry() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        let enter = KeyEvent(key: .enter)

        _ = resolver.feed(xCtrl)
        let results = resolver.feed(enter)

        // First the pending X-ctrl is passed through, then Enter matches .submit alone.
        #expect(results.count == 2)
        expectPassthrough(results, at: 0, equals: xCtrl)
        expectAction(results, at: 1, equals: .submit)
        #expect(resolver.hasPending == false)
    }

    @Test("pending miss with unbound current event passes both through")
    func testPendingMissBothPassthrough() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        let aChar = KeyEvent(key: .character("a"))

        _ = resolver.feed(xCtrl)
        let results = resolver.feed(aChar)

        #expect(results.count == 2)
        expectPassthrough(results, at: 0, equals: xCtrl)
        expectPassthrough(results, at: 1, equals: aChar)
        #expect(resolver.hasPending == false)
    }

    @Test("pending miss retries into another prefix")
    func testPendingMissRetryBecomesPrefix() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)

        // Push X-ctrl twice: second X-ctrl misses the [X,X] sequence but is a fresh prefix.
        _ = resolver.feed(xCtrl)
        let results = resolver.feed(xCtrl)

        #expect(results.count == 1)
        expectPassthrough(results, at: 0, equals: xCtrl)
        #expect(resolver.hasPending == true)
    }

    @Test("paste event always passes through")
    func testPasteAlwaysPassthrough() {
        let (resolver, _) = makeResolver()
        let paste = KeyEvent(key: .paste("hello"))
        let results = resolver.feed(paste)
        #expect(results.count == 1)
        expectPassthrough(results, at: 0, equals: paste)
    }

    @Test("paste while pending flushes pending then passes paste")
    func testPasteWhilePending() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        let paste = KeyEvent(key: .paste("hi"))

        _ = resolver.feed(xCtrl)
        let results = resolver.feed(paste)

        #expect(results.count == 2)
        expectPassthrough(results, at: 0, equals: xCtrl)
        expectPassthrough(results, at: 1, equals: paste)
        #expect(resolver.hasPending == false)
    }

    @Test("flush() drains pending regardless of timeout")
    func testFlushDrainsPending() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        _ = resolver.feed(xCtrl)
        let results = resolver.flush()
        #expect(results.count == 1)
        expectPassthrough(results, at: 0, equals: xCtrl)
        #expect(resolver.hasPending == false)
    }

    @Test("tick before timeout is a no-op and keeps pending state")
    func testTickBeforeTimeoutNoOp() {
        let (resolver, clock) = makeResolver(timeoutNanos: 50_000_000)
        _ = resolver.feed(KeyEvent(key: .character("X"), modifiers: .ctrl))
        clock.advance(by: 10_000_000)
        #expect(resolver.tick().isEmpty)
        #expect(resolver.hasPending == true)
    }

    @Test("feed past timeout flushes pending before matching the new event")
    func testFeedPastTimeout() {
        let (resolver, clock) = makeResolver(timeoutNanos: 50_000_000)
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        let enter = KeyEvent(key: .enter)

        _ = resolver.feed(xCtrl)
        clock.advance(by: 60_000_000)
        let results = resolver.feed(enter)

        #expect(results.count == 2)
        expectPassthrough(results, at: 0, equals: xCtrl)
        expectAction(results, at: 1, equals: .submit)
        #expect(resolver.hasPending == false)
    }

    @Test("replaceRegistry drains pending and swaps bindings")
    func testReplaceRegistryFlushesPending() {
        let (resolver, _) = makeResolver()
        let xCtrl = KeyEvent(key: .character("X"), modifiers: .ctrl)
        _ = resolver.feed(xCtrl)

        var fresh = KeybindingRegistry<TestAction>()
        try! fresh.register(KeySequence(KeyStroke(key: .enter)), action: .submit)

        let flushed = resolver.replaceRegistry(fresh)
        #expect(flushed.count == 1)
        expectPassthrough(flushed, at: 0, equals: xCtrl)
        #expect(resolver.hasPending == false)

        // Old chord no longer registered.
        let after = resolver.feed(xCtrl)
        #expect(after.count == 1)
        expectPassthrough(after, at: 0, equals: xCtrl)
    }
}
