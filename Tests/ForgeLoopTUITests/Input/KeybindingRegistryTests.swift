import Testing
@testable import ForgeLoopTUI

@Suite("KeybindingRegistry")
struct KeybindingRegistryTests {

    enum TestAction: Sendable, Equatable {
        case alpha
        case beta
        case gamma
    }

    private func stroke(_ c: Character, ctrl: Bool = false) -> KeyStroke {
        KeyStroke(key: .character(c), modifiers: ctrl ? .ctrl : [])
    }

    @Test("single-key binding matches exactly")
    func testSingleKeyExact() throws {
        var registry = KeybindingRegistry<TestAction>()
        try registry.register(KeySequence(stroke("A", ctrl: true)), action: .alpha)

        switch registry.match([stroke("A", ctrl: true)]) {
        case .exact(let action):
            #expect(action == .alpha)
        default:
            Issue.record("expected exact match")
        }
    }

    @Test("non-registered single key misses")
    func testSingleKeyMiss() {
        let registry = KeybindingRegistry<TestAction>()
        switch registry.match([stroke("Z")]) {
        case .miss:
            break
        default:
            Issue.record("expected miss for unbound stroke")
        }
    }

    @Test("first stroke of chord reports prefix; full chord reports exact")
    func testChordPrefixAndExact() throws {
        var registry = KeybindingRegistry<TestAction>()
        let chord = KeySequence([
            stroke("X", ctrl: true),
            stroke("S", ctrl: true),
        ])
        try registry.register(chord, action: .alpha)

        switch registry.match([stroke("X", ctrl: true)]) {
        case .prefix:
            break
        default:
            Issue.record("expected prefix for first stroke of chord")
        }

        switch registry.match([stroke("X", ctrl: true), stroke("S", ctrl: true)]) {
        case .exact(let action):
            #expect(action == .alpha)
        default:
            Issue.record("expected exact match for full chord")
        }
    }

    @Test("duplicate registration throws .duplicate")
    func testDuplicateRegistrationThrows() throws {
        var registry = KeybindingRegistry<TestAction>()
        let seq = KeySequence(KeyStroke(key: .enter))
        try registry.register(seq, action: .alpha)

        #expect(throws: KeybindingRegistry<TestAction>.RegistrationError.duplicate) {
            try registry.register(seq, action: .beta)
        }
    }

    @Test("registering a shorter prefix of an existing binding throws .prefixConflict")
    func testPrefixOfExistingThrows() throws {
        var registry = KeybindingRegistry<TestAction>()
        let chord = KeySequence([
            stroke("X", ctrl: true),
            stroke("S", ctrl: true),
        ])
        try registry.register(chord, action: .alpha)

        #expect(throws: KeybindingRegistry<TestAction>.RegistrationError.prefixConflict) {
            try registry.register(KeySequence(stroke("X", ctrl: true)), action: .beta)
        }
    }

    @Test("registering a binding that extends an existing exact binding throws .prefixConflict")
    func testExtendingExistingThrows() throws {
        var registry = KeybindingRegistry<TestAction>()
        try registry.register(KeySequence(stroke("X", ctrl: true)), action: .alpha)

        let chord = KeySequence([
            stroke("X", ctrl: true),
            stroke("S", ctrl: true),
        ])
        #expect(throws: KeybindingRegistry<TestAction>.RegistrationError.prefixConflict) {
            try registry.register(chord, action: .beta)
        }
    }

    @Test("unregister removes the binding and returns true")
    func testUnregisterExisting() throws {
        var registry = KeybindingRegistry<TestAction>()
        let seq = KeySequence(KeyStroke(key: .enter))
        try registry.register(seq, action: .alpha)

        let removed = registry.unregister(seq)
        #expect(removed == true)

        switch registry.match([KeyStroke(key: .enter)]) {
        case .miss:
            break
        default:
            Issue.record("expected miss after unregister")
        }
    }

    @Test("unregister returns false for unknown sequence")
    func testUnregisterMissing() {
        var registry = KeybindingRegistry<TestAction>()
        let removed = registry.unregister(KeySequence(KeyStroke(key: .enter)))
        #expect(removed == false)
    }

    @Test("match on empty stroke list returns miss")
    func testEmptyMatchIsMiss() {
        let registry = KeybindingRegistry<TestAction>()
        switch registry.match([]) {
        case .miss:
            break
        default:
            Issue.record("expected miss for empty stroke list")
        }
    }

    @Test("independent bindings coexist; count and isEmpty reflect state")
    func testIndependentBindingsCoexist() throws {
        var registry = KeybindingRegistry<TestAction>()
        #expect(registry.isEmpty == true)

        try registry.register(KeySequence(KeyStroke(key: .enter)), action: .alpha)
        try registry.register(KeySequence(KeyStroke(key: .escape)), action: .beta)
        try registry.register(KeySequence([
            stroke("X", ctrl: true),
            stroke("S", ctrl: true),
        ]), action: .gamma)

        #expect(registry.count == 3)
        #expect(registry.isEmpty == false)
    }

    @Test("removeAll clears registry")
    func testRemoveAll() throws {
        var registry = KeybindingRegistry<TestAction>()
        try registry.register(KeySequence(KeyStroke(key: .enter)), action: .alpha)
        try registry.register(KeySequence(KeyStroke(key: .escape)), action: .beta)
        registry.removeAll()
        #expect(registry.isEmpty == true)
        switch registry.match([KeyStroke(key: .enter)]) {
        case .miss:
            break
        default:
            Issue.record("expected miss after removeAll")
        }
    }

    @Test("KeyStroke rejects paste events")
    func testKeyStrokeRejectsPaste() {
        let pasteEvent = KeyEvent(key: .paste("hello"))
        #expect(KeyStroke(event: pasteEvent) == nil)

        let charEvent = KeyEvent(key: .character("a"))
        #expect(KeyStroke(event: charEvent) != nil)
    }

    @Test("registering a sequence containing paste throws .containsPaste")
    func testRegisterContainsPasteThrows() {
        var registry = KeybindingRegistry<TestAction>()
        // Production callers cannot build a paste-bearing stroke through the public
        // initializer (it traps). The unchecked init is reserved for verifying that
        // the registry's defense-in-depth guard fires when somebody bypasses it.
        let pasteStroke = KeyStroke(uncheckedKey: .paste("hi"))
        let sequence = KeySequence(pasteStroke)

        #expect(throws: KeybindingRegistry<TestAction>.RegistrationError.containsPaste) {
            try registry.register(sequence, action: .alpha)
        }
        #expect(registry.isEmpty == true)
    }

    @Test("registering a chord with paste in the middle throws .containsPaste")
    func testRegisterChordContainsPasteThrows() {
        var registry = KeybindingRegistry<TestAction>()
        let mixed = KeySequence([
            KeyStroke(key: .character("X"), modifiers: .ctrl),
            KeyStroke(uncheckedKey: .paste("payload")),
        ])

        #expect(throws: KeybindingRegistry<TestAction>.RegistrationError.containsPaste) {
            try registry.register(mixed, action: .alpha)
        }
    }
}
