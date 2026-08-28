/// Normalized key event model that hides differences between terminal input
/// sequences.
///
/// `KeyParser` converts the `InputUnit`s produced by `ByteStreamBuffer` into
/// `KeyEvent`s. All modifiers (Shift / Alt / Ctrl) are represented uniformly
/// at the `KeyEvent` level, without exposing whether the underlying sequence
/// was CSI, SS3, or a single-byte control character.
public struct KeyEvent: Sendable, Equatable {
    public var key: Key
    public var modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Recognizable key types.
public enum Key: Sendable, Hashable {
    case character(Character)
    /// Aggregated content of a bracketed paste.
    case paste(String)
    case up, down, left, right
    case home, end, pageUp, pageDown
    case insert, delete
    case enter, tab, backspace, escape
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
}

/// A set of modifiers.
public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let alt = Modifiers(rawValue: 1 << 1)
    public static let ctrl = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public init(rawValue: UInt8) { self.rawValue = rawValue }
}
