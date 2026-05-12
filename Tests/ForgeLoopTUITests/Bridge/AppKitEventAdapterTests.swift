import Testing
import AppKit
@testable import ForgeLoopTUI

@Suite("AppKitEventAdapter")
struct AppKitEventAdapterTests {
    let adapter = AppKitEventAdapter()

    // MARK: - Printable characters

    @Test("plain ASCII character")
    func testPrintableASCII() {
        let event = makeEvent(characters: "a")
        let keyEvent = adapter.keyEvent(from: event)
        #expect(keyEvent == KeyEvent(key: .character("a")))
    }

    @Test("printable with Shift")
    func testPrintableWithShift() {
        let event = makeEvent(modifierFlags: .shift, characters: "A")
        let keyEvent = adapter.keyEvent(from: event)
        #expect(keyEvent == KeyEvent(key: .character("A"), modifiers: .shift))
    }

    @Test("printable with Option")
    func testPrintableWithOption() {
        let event = makeEvent(modifierFlags: .option, characters: "ø")
        let keyEvent = adapter.keyEvent(from: event)
        #expect(keyEvent == KeyEvent(key: .character("ø"), modifiers: .alt))
    }

    @Test("Ctrl+A control character")
    func testCtrlAControlCharacter() {
        let event = makeEvent(modifierFlags: .control, characters: "\u{01}")
        let keyEvent = adapter.keyEvent(from: event)
        #expect(keyEvent == KeyEvent(key: .character("A"), modifiers: .ctrl))
    }

    // MARK: - Special keys

    @Test("arrow keys")
    func testArrowKeys() {
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .upArrow)) == KeyEvent(key: .up))
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .downArrow)) == KeyEvent(key: .down))
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .leftArrow)) == KeyEvent(key: .left))
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .rightArrow)) == KeyEvent(key: .right))
    }

    @Test("navigation keys")
    func testNavigationKeys() {
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .home)) == KeyEvent(key: .home))
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .end)) == KeyEvent(key: .end))
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .pageUp)) == KeyEvent(key: .pageUp))
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .pageDown)) == KeyEvent(key: .pageDown))
    }

    @Test("delete keys")
    func testDeleteKeys() {
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .delete)) == KeyEvent(key: .backspace))
        // forwardDelete (Fn+Delete / 扩展键盘 Delete) rawValue = 63272
        let forwardDelete = NSEvent.SpecialKey(rawValue: 63272)
        #expect(adapter.keyEvent(from: makeEvent(specialKey: forwardDelete)) == KeyEvent(key: .delete))
    }

    @Test("line feed via specialKey rawValue")
    func testLineFeed() {
        // lineFeed rawValue = 10
        let lineFeed = NSEvent.SpecialKey(rawValue: 10)
        #expect(adapter.keyEvent(from: makeEvent(specialKey: lineFeed)) == KeyEvent(key: .enter))
    }

    @Test("enter variants")
    func testEnterVariants() {
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .carriageReturn)) == KeyEvent(key: .enter))
        #expect(adapter.keyEvent(from: makeEvent(keyCode: 36)) == KeyEvent(key: .enter))
        #expect(adapter.keyEvent(from: makeEvent(keyCode: 76)) == KeyEvent(key: .enter))
    }

    @Test("tab")
    func testTab() {
        #expect(adapter.keyEvent(from: makeEvent(specialKey: .tab)) == KeyEvent(key: .tab))
    }

    @Test("function keys F1–F12")
    func testFunctionKeys() {
        let specialKeys: [NSEvent.SpecialKey: Key] = [
            .f1: .f1, .f2: .f2, .f3: .f3, .f4: .f4,
            .f5: .f5, .f6: .f6, .f7: .f7, .f8: .f8,
            .f9: .f9, .f10: .f10, .f11: .f11, .f12: .f12,
        ]
        for (special, expectedKey) in specialKeys {
            let result = adapter.keyEvent(from: makeEvent(specialKey: special))
            #expect(result == KeyEvent(key: expectedKey), "Expected \(expectedKey) for \(special)")
        }
    }

    // MARK: - Modifier combinations

    @Test("modifier combinations")
    func testModifierCombinations() {
        let shiftOptionUp = makeEvent(
            modifierFlags: [.shift, .option],
            specialKey: .upArrow
        )
        #expect(adapter.keyEvent(from: shiftOptionUp) == KeyEvent(key: .up, modifiers: [.shift, .alt]))

        let ctrlDown = makeEvent(
            modifierFlags: .control,
            specialKey: .downArrow
        )
        #expect(adapter.keyEvent(from: ctrlDown) == KeyEvent(key: .down, modifiers: .ctrl))
    }

    @Test("command key returns nil")
    func testCommandKeyReturnsNil() {
        let event = makeEvent(modifierFlags: .command, characters: "c")
        #expect(adapter.keyEvent(from: event) == nil)
    }

    // MARK: - Boundaries and degradation

    @Test("keyUp returns nil")
    func testKeyUpReturnsNil() {
        let event = makeEvent(type: .keyUp, characters: "a")
        #expect(adapter.keyEvent(from: event) == nil)
    }

    @Test("flagsChanged returns nil")
    func testFlagsChangedReturnsNil() {
        let event = makeEvent(type: .flagsChanged, characters: "")
        #expect(adapter.keyEvent(from: event) == nil)
    }

    @Test("no characters and no special key returns nil")
    func testNoCharactersNoSpecialKey() {
        let event = makeEvent(characters: nil)
        #expect(adapter.keyEvent(from: event) == nil)
    }

    @Test("multi-character string returns nil")
    func testMultiCharacterStringReturnsNil() {
        let event = makeEvent(characters: "abc")
        #expect(adapter.keyEvent(from: event) == nil)
    }

    // MARK: - Semantic parity with KeyParser

    @Test("semantic parity with KeyParser subset")
    func testSemanticParityWithKeyParser() {
        let knownEvents: [KeyEvent] = [
            KeyEvent(key: .character("x")),
            KeyEvent(key: .up),
            KeyEvent(key: .down, modifiers: .shift),
            KeyEvent(key: .enter),
            KeyEvent(key: .tab, modifiers: .alt),
            KeyEvent(key: .f1, modifiers: .ctrl),
        ]

        for expected in knownEvents {
            let nsEvent = makeEvent(from: expected)
            let result = adapter.keyEvent(from: nsEvent)
            #expect(result?.key == expected.key)
            #expect(result?.modifiers == expected.modifiers)
        }
    }

    // MARK: - Helpers

    private func makeEvent(
        type: NSEvent.EventType = .keyDown,
        location: NSPoint = .zero,
        modifierFlags: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = 0,
        windowNumber: Int = 0,
        context: NSGraphicsContext? = nil,
        characters: String? = nil,
        charactersIgnoringModifiers: String? = nil,
        isARepeat: Bool = false,
        keyCode: UInt16 = 0,
        specialKey: NSEvent.SpecialKey? = nil
    ) -> NSEvent {
        let effectiveCharacters: String
        if let characters {
            effectiveCharacters = characters
        } else if let specialKey {
            effectiveCharacters = String(UnicodeScalar(specialKey.rawValue)!)
        } else {
            effectiveCharacters = ""
        }
        let effectiveCharactersIgnoringModifiers = charactersIgnoringModifiers ?? effectiveCharacters
        return NSEvent.keyEvent(
            with: type,
            location: location,
            modifierFlags: modifierFlags,
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: context,
            characters: effectiveCharacters,
            charactersIgnoringModifiers: effectiveCharactersIgnoringModifiers,
            isARepeat: isARepeat,
            keyCode: keyCode
        )!
    }

    private func makeEvent(
        type: NSEvent.EventType = .keyDown,
        modifierFlags: NSEvent.ModifierFlags = [],
        characters: String? = nil,
        keyCode: UInt16 = 0
    ) -> NSEvent {
        makeEvent(
            type: type,
            modifierFlags: modifierFlags,
            characters: characters,
            keyCode: keyCode,
            specialKey: nil
        )
    }

    private func makeEvent(
        modifierFlags: NSEvent.ModifierFlags = [],
        specialKey: NSEvent.SpecialKey
    ) -> NSEvent {
        makeEvent(
            modifierFlags: modifierFlags,
            keyCode: 0,
            specialKey: specialKey
        )
    }

    private func makeEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        makeEvent(
            modifierFlags: modifierFlags,
            characters: nil,
            keyCode: keyCode
        )
    }

    private func makeEvent(from keyEvent: KeyEvent) -> NSEvent {
        switch keyEvent.key {
        case .character(let c):
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                characters: String(c)
            )
        case .up:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .upArrow
            )
        case .down:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .downArrow
            )
        case .left:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .leftArrow
            )
        case .right:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .rightArrow
            )
        case .enter:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .carriageReturn
            )
        case .tab:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .tab
            )
        case .f1:
            return makeEvent(
                modifierFlags: cocoaModifiers(keyEvent.modifiers),
                specialKey: .f1
            )
        default:
            return makeEvent(characters: "?")
        }
    }

    private func cocoaModifiers(_ modifiers: Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.alt) { flags.insert(.option) }
        if modifiers.contains(.ctrl) { flags.insert(.control) }
        return flags
    }
}
