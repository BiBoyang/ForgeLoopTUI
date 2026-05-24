import AppKit

/// 将 AppKit NSEvent 按键事件转换为 ForgeLoopTUI 的规范化 KeyEvent。
///
/// 本适配器是纯数据转换，不保留状态，不依赖 RunLoop 或 Window。
/// 应用侧在 NSView.keyDown(with:) 中调用即可获得库级 KeyEvent。
///
/// ## 映射范围
/// - 单字符可打印输入（含组合键）：→ .character(c)
/// - 方向键、功能键、导航键：→ 对应 Key 枚举值
/// - 修饰符映射：NSEvent.ModifierFlags → ForgeLoopTUI.Modifiers
/// - 未知/不可映射事件：返回 nil（静默丢弃，不抛错）
///
/// ## 不处理
/// - keyUp、flagsChanged、mouse 事件：直接返回 nil
/// - 多字符输入：返回 nil（每个 keyDown 只应产生一个逻辑按键）
/// - IME 组合态：返回 nil（P0 不处理多字符组合输入）
/// - 系统级快捷键（Cmd+Q 等）：由 NSApplication 拦截，不会到达 keyDown
public struct AppKitEventAdapter: Sendable {
    public init() {}

    /// 从 NSEvent.keyDown 事件创建 KeyEvent。
    ///
    /// - Parameter event: NSEvent（仅处理 .keyDown 类型）
    /// - Returns: 规范化 KeyEvent，无法映射时返回 nil（静默丢弃）
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
    /// 控制字符按 KeyParser.parseCharacter(_:) 语义对齐：
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
            let letter = Character(Unicode.Scalar(value + 0x40)!)
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
