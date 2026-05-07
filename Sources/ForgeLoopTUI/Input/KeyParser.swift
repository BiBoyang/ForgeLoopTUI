/// 将 `InputUnit` 序列解析为规范化 `KeyEvent`。
///
/// 支持的输入来源：
/// - CSI 序列：方向键、功能键、Home/End、PageUp/PageDown、Insert/Delete
/// - SS3 序列：ESC O A/B/C/D/H/F/P/Q/R/S（常见于 xterm Application Keypad）
/// - Alt+字符：ESC 后接普通字符
/// - 控制字符：Ctrl+A-Z（0x01-0x1A）、Tab、Enter、Backspace、Escape
///
/// 未知或无法映射的序列会被静默丢弃。
public struct KeyParser: Sendable {
    public init() {}

    /// 解析一批 `InputUnit`，返回对应的 `KeyEvent` 序列。
    public func parse(_ units: [InputUnit]) -> [KeyEvent] {
        var events: [KeyEvent] = []
        var i = 0
        while i < units.count {
            let (event, consumed) = parseUnit(units, at: i)
            if let event {
                events.append(event)
            }
            i += consumed
        }
        return events
    }

    // MARK: - Private

    /// 解析单个逻辑按键，返回 (事件, 消费的单元数)。
    private func parseUnit(_ units: [InputUnit], at i: Int) -> (KeyEvent?, Int) {
        guard i < units.count else { return (nil, 0) }

        switch units[i] {
        case .character(let c):
            return (parseCharacter(c), 1)

        case .byte(let b):
            return (parseByte(b), 1)

        case .csi(let params, let command):
            return (parseCSI(params: params, command: command), 1)

        case .escape(let command):
            // SS3 前缀 ESC O，需要和下一个单元组合
            if command == "O", i + 1 < units.count {
                if case .character(let next) = units[i + 1] {
                    if let event = parseSS3(next) {
                        return (event, 2)
                    }
                }
            }
            // Alt + 普通字符
            if let c = command.unicodeScalars.first, c.properties.isAlphabetic || c.isASCII {
                return (KeyEvent(key: .character(command), modifiers: .alt), 1)
            }
            return (nil, 1)
        }
    }

    /// 解析普通字符（含控制字符）。
    private func parseCharacter(_ c: Character) -> KeyEvent {
        let scalar = c.unicodeScalars.first!
        let value = scalar.value

        switch value {
        case 0x0D, 0x0A:
            return KeyEvent(key: .enter)
        case 0x09:
            return KeyEvent(key: .tab)
        case 0x7F:
            return KeyEvent(key: .backspace)
        case 0x1B:
            return KeyEvent(key: .escape)
        case 0x00:
            return KeyEvent(key: .character("@"), modifiers: .ctrl)
        case 0x01...0x1A:
            let letter = Character(Unicode.Scalar(value + 0x40)!)
            return KeyEvent(key: .character(letter), modifiers: .ctrl)
        default:
            return KeyEvent(key: .character(c))
        }
    }

    /// 解析原始字节（flush 兜底或非法字节）。
    private func parseByte(_ b: UInt8) -> KeyEvent {
        switch b {
        case 0x0D, 0x0A:
            return KeyEvent(key: .enter)
        case 0x09:
            return KeyEvent(key: .tab)
        case 0x7F:
            return KeyEvent(key: .backspace)
        case 0x1B:
            return KeyEvent(key: .escape)
        case 0x00:
            return KeyEvent(key: .character("@"), modifiers: .ctrl)
        case 0x01...0x1A:
            let letter = Character(Unicode.Scalar(UInt32(b) + 0x40)!)
            return KeyEvent(key: .character(letter), modifiers: .ctrl)
        default:
            // 可打印 ASCII 兜底为字符，其他丢弃
            if b < 0x7F {
                return KeyEvent(key: .character(Character(Unicode.Scalar(UInt32(b))!)))
            }
            return KeyEvent(key: .character("\u{FFFD}"))
        }
    }

    /// 解析 CSI 序列。
    private func parseCSI(params: [Int], command: Character) -> KeyEvent? {
        switch command {
        case "A": return makeKey(.up, params: params)
        case "B": return makeKey(.down, params: params)
        case "C": return makeKey(.right, params: params)
        case "D": return makeKey(.left, params: params)
        case "H": return makeKey(.home, params: params)
        case "F": return makeKey(.end, params: params)
        case "Z": return makeKey(.tab, params: params, extraModifiers: .shift)
        case "~":
            guard let code = params.first else { return nil }
            let key: Key
            switch code {
            case 1, 7: key = .home
            case 2: key = .insert
            case 3: key = .delete
            case 4, 8: key = .end
            case 5: key = .pageUp
            case 6: key = .pageDown
            case 11: key = .f1
            case 12: key = .f2
            case 13: key = .f3
            case 14: key = .f4
            case 15: key = .f5
            case 17: key = .f6
            case 18: key = .f7
            case 19: key = .f8
            case 20: key = .f9
            case 21: key = .f10
            case 23: key = .f11
            case 24: key = .f12
            default: return nil
            }
            let modifiers = extractModifiers(from: params)
            return KeyEvent(key: key, modifiers: modifiers)
        default:
            return nil
        }
    }

    /// 解析 SS3 序列（ESC O <final>）。
    private func parseSS3(_ final: Character) -> KeyEvent? {
        switch final {
        case "A": return KeyEvent(key: .up)
        case "B": return KeyEvent(key: .down)
        case "C": return KeyEvent(key: .right)
        case "D": return KeyEvent(key: .left)
        case "H": return KeyEvent(key: .home)
        case "F": return KeyEvent(key: .end)
        case "P": return KeyEvent(key: .f1)
        case "Q": return KeyEvent(key: .f2)
        case "R": return KeyEvent(key: .f3)
        case "S": return KeyEvent(key: .f4)
        default: return nil
        }
    }

    /// 从 CSI params 构造按键事件（支持修饰符）。
    private func makeKey(_ key: Key, params: [Int], extraModifiers: Modifiers = []) -> KeyEvent {
        var modifiers = extractModifiers(from: params)
        modifiers.formUnion(extraModifiers)
        return KeyEvent(key: key, modifiers: modifiers)
    }

    /// 从 CSI params 提取修饰符值。
    ///
    /// 标准格式：`CSI code ; modifier final`
    /// - 对于 `~` 命令：第一个 param 是键码，最后一个（如果 count>=2）是修饰符。
    /// - 对于方向键：最后一个 param（如果 count>=2）或单个 param（如果 >1）是修饰符。
    ///
    /// Modifier 值：
    ///   1 = 无，2 = Shift，3 = Alt，4 = Shift+Alt，
    ///   5 = Ctrl，6 = Shift+Ctrl，7 = Alt+Ctrl，8 = Shift+Alt+Ctrl
    private func extractModifiers(from params: [Int]) -> Modifiers {
        guard params.count >= 2 else { return [] }
        guard let value = params.last, value >= 1 else { return [] }
        switch value {
        case 2: return .shift
        case 3: return .alt
        case 4: return [.shift, .alt]
        case 5: return .ctrl
        case 6: return [.shift, .ctrl]
        case 7: return [.alt, .ctrl]
        case 8: return [.shift, .alt, .ctrl]
        default: return []
        }
    }
}
