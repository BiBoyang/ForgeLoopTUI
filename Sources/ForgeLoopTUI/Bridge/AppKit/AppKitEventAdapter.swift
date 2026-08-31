import AppKit

/// Converts AppKit NSEvent key events into ForgeLoopTUI's normalized KeyEvent.
///
/// This adapter performs pure data conversion: it keeps no state and does not
/// depend on the RunLoop or a Window. The app side calls it from
/// NSView.keyDown(with:) to obtain a library-level KeyEvent.
///
/// ## Mapping Scope
/// - Single printable characters (including with modifier combinations): → .character(c)
/// - Arrow keys, function keys, navigation keys: → the corresponding Key enum case
/// - Modifier mapping: NSEvent.ModifierFlags → ForgeLoopTUI.Modifiers
/// - Unknown/unmappable events: returns nil (silently dropped, no error thrown)
///
/// ## Not Handled
/// - keyUp, flagsChanged, and mouse events: return nil directly
/// - Multi-character input: returns nil (each keyDown should produce exactly one logical key)
/// - IME composition states: returns nil (P0 does not handle multi-character composed input)
/// - System-level shortcuts (Cmd+Q etc.): intercepted by NSApplication and never reach keyDown
public struct AppKitEventAdapter: Sendable {
    public init() {}

    /// Creates a KeyEvent from an NSEvent.keyDown event.
    ///
    /// - Parameter event: The NSEvent (only `.keyDown` type is handled)
    /// - Returns: A normalized KeyEvent, or nil when it cannot be mapped (silently dropped)
    public func keyEvent(from event: NSEvent) -> KeyEvent? {
        guard event.type == .keyDown else {
            return nil
        }

        let modifiers = mapModifiers(event.modifierFlags)

        if let specialKey = event.specialKey {
            return mapSpecialKey(specialKey, modifiers: modifiers)
                ?? mapKeyCodeFallback(event.keyCode, modifiers: modifiers)
        }

        if let characters = event.characters, !characters.isEmpty {
            return mapPrintableCharacters(characters, modifiers: modifiers)
        }

        return mapKeyCodeFallback(event.keyCode, modifiers: modifiers)
    }

    // MARK: - Private

    /// 将 NSEvent.SpecialKey 映射为 KeyEvent.Key。
    ///
    /// 注意：`.forwardDelete`、`.lineFeed`、`.escape` 在部分 SDK 版本中以 rawValue 形式存在，
    /// 因此通过 `rawValue` 匹配以确保跨版本兼容。
    private func mapSpecialKey(_ specialKey: NSEvent.SpecialKey, modifiers: Modifiers) -> KeyEvent? {
        let key: Key

        switch specialKey {
        case .upArrow:
            key = .up
        case .downArrow:
            key = .down
        case .leftArrow:
            key = .left
        case .rightArrow:
            key = .right
        case .home:
            key = .home
        case .end:
            key = .end
        case .pageUp:
            key = .pageUp
        case .pageDown:
            key = .pageDown
        case .delete:
            key = .backspace
        case .tab:
            key = .tab
        case .carriageReturn, .enter:
            key = .enter
        case .f1:
            key = .f1
        case .f2:
            key = .f2
        case .f3:
            key = .f3
        case .f4:
            key = .f4
        case .f5:
            key = .f5
        case .f6:
            key = .f6
        case .f7:
            key = .f7
        case .f8:
            key = .f8
        case .f9:
            key = .f9
        case .f10:
            key = .f10
        case .f11:
            key = .f11
        case .f12:
            key = .f12
        case .insert:
            key = .insert
        default:
            // 通过 rawValue 匹配 SDK 中未直接暴露的 specialKey
            switch specialKey.rawValue {
            case 63272:
                key = .delete
            case 10:
                key = .enter
            default:
                return nil
            }
        }

        return KeyEvent(key: key, modifiers: modifiers)
    }

    /// 通过 keyCode 回退映射特殊键（用于 NSEvent.SpecialKey 未覆盖的键）。
    private func mapKeyCodeFallback(_ keyCode: UInt16, modifiers: Modifiers) -> KeyEvent? {
        let key: Key

        switch keyCode {
        case 53:
            key = .escape
        case 117:
            key = .delete
        case 36, 76:
            key = .enter
        case 48:
            key = .tab
        default:
            return nil
        }

        return KeyEvent(key: key, modifiers: modifiers)
    }

    /// 将可打印字符映射为 KeyEvent。
    ///
    /// 控制字符与 KeyParser.parseCharacter(_:) 语义对齐，唯一例外是
    /// 0x0A：NSEvent 的 LF（SpecialKey lineFeed / Ctrl+J 场景）自带修饰位，
    /// 桥接层保持 enter 语义；终端字节流中的 0x0A 由 KeyParser 解码为 ctrl+j。
    /// - 0x0D / 0x0A → .enter
    /// - 0x09 → .tab
    /// - 0x7F → .backspace
    /// - 0x1B → .escape
    /// - 0x00 → .character("@") + .ctrl
    /// - 0x01...0x1A → .character("A"..."Z") + .ctrl
    ///
    /// 多字符输入统一返回 nil。
    private func mapPrintableCharacters(_ characters: String, modifiers: Modifiers) -> KeyEvent? {
        guard characters.count == 1, let scalar = characters.unicodeScalars.first else {
            return nil
        }

        let value = scalar.value

        switch value {
        case 0x0D, 0x0A:
            return KeyEvent(key: .enter, modifiers: modifiers)
        case 0x09:
            return KeyEvent(key: .tab, modifiers: modifiers)
        case 0x7F:
            return KeyEvent(key: .backspace, modifiers: modifiers)
        case 0x1B:
            return KeyEvent(key: .escape, modifiers: modifiers)
        case 0x00:
            return KeyEvent(key: .character("@"), modifiers: modifiers.union(.ctrl))
        case 0x01...0x1A:
            // 0x01...0x1A + 0x40 = A...Z；UInt8 构造 scalar 非可选。
            let letter = Character(Unicode.Scalar(UInt8(value + 0x40)))
            return KeyEvent(key: .character(letter), modifiers: modifiers.union(.ctrl))
        default:
            return KeyEvent(key: .character(Character(scalar)), modifiers: modifiers)
        }
    }

    /// 将 NSEvent.ModifierFlags 映射为 ForgeLoopTUI.Modifiers。
    private func mapModifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        var modifiers: Modifiers = []

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }

        if flags.contains(.option) {
            modifiers.insert(.alt)
        }

        if flags.contains(.control) {
            modifiers.insert(.ctrl)
        }

        if flags.contains(.command) {
            modifiers.insert(.command)
        }

        return modifiers
    }
}
