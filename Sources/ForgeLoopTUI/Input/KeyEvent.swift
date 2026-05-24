/// 规范化按键事件模型，屏蔽终端输入序列的差异。
///
/// `KeyParser` 将 `ByteStreamBuffer` 输出的 `InputUnit` 转换为 `KeyEvent`。
/// 所有修饰符（Shift / Alt / Ctrl）在 `KeyEvent` 层面统一表示，
/// 不暴露底层是 CSI、SS3 还是单字节控制字符。
public struct KeyEvent: Sendable, Equatable {
    public var key: Key
    public var modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// 可识别的按键类型。
public enum Key: Sendable, Hashable {
    case character(Character)
    /// Bracketed paste 聚合内容。
    case paste(String)
    case up, down, left, right
    case home, end, pageUp, pageDown
    case insert, delete
    case enter, tab, backspace, escape
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
}

/// 修饰符集合。
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let alt = Modifiers(rawValue: 1 << 1)
    public static let ctrl = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public init(rawValue: UInt8) { self.rawValue = rawValue }
}
