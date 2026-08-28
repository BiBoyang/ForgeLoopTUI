import Foundation

/// A normalized single key press, the basic element of ``KeySequence`` and ``KeybindingRegistry``.
///
/// Unlike ``KeyEvent``, ``KeyStroke`` only describes the key state that triggers a binding;
/// ``Key/paste(_:)`` does not participate in matching — ``KeyResolver`` passes paste through directly.
/// The public initializer triggers `preconditionFailure` when given paste, preventing the
/// construction of "dead bindings" that can never fire.
///
/// Stability: Provisional.
public struct KeyStroke: Sendable, Hashable {
    public let key: Key
    public let modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers = []) {
        if case .paste = key {
            preconditionFailure("KeyStroke does not accept Key.paste; paste events pass through KeyResolver and must not be registered as bindings")
        }
        self.key = key
        self.modifiers = modifiers
    }

    /// Creates a stroke from a ``KeyEvent``. Paste events return nil.
    public init?(event: KeyEvent) {
        if case .paste = event.key { return nil }
        self.key = event.key
        self.modifiers = event.modifiers
    }

    /// 仅供本模块测试构造"绕过 paste 检查"的样本使用。
    /// 生产代码不应使用——若 key 为 `.paste(_:)`,后续注册会被 ``KeybindingRegistry``
    /// 以 ``KeybindingRegistry/RegistrationError/containsPaste`` 拒绝。
    internal init(uncheckedKey key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// A sequence of key strokes. May be a single key or a multi-key chord.
///
/// Contains at least one ``KeyStroke``; an empty sequence triggers an assertion.
///
/// Stability: Provisional.
public struct KeySequence: Sendable, Hashable {
    public let strokes: [KeyStroke]

    public init(_ strokes: [KeyStroke]) {
        precondition(!strokes.isEmpty, "KeySequence must contain at least one stroke")
        self.strokes = strokes
    }

    public init(_ stroke: KeyStroke) {
        self.strokes = [stroke]
    }

    public var first: KeyStroke { strokes[0] }
    public var count: Int { strokes.count }
}

extension KeySequence: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: KeyStroke...) {
        self.init(elements)
    }
}

/// Maps a ``KeySequence`` to a downstream `Action`.
///
/// Stability: Provisional.
public struct KeyBinding<Action: Sendable>: Sendable {
    public let sequence: KeySequence
    public let action: Action
    public let description: String?

    public init(_ sequence: KeySequence, action: Action, description: String? = nil) {
        self.sequence = sequence
        self.action = action
        self.description = description
    }
}

/// A container for key bindings, providing registration, unregistration, and prefix queries.
///
/// Conflicts are rejected at registration time:
/// - Re-registering the same sequence throws `RegistrationError.duplicate`.
/// - If a sequence is a prefix of another registered sequence (or vice versa), throws
///   `RegistrationError.prefixConflict`.
///
/// Under these constraints, a match has only three outcomes (``Match``): `miss`, `prefix`,
/// `exact(Action)`, so ``KeyResolver`` never needs an ambiguity policy between "fire now or wait".
///
/// Stability: Provisional.
public struct KeybindingRegistry<Action: Sendable>: Sendable {
    public enum RegistrationError: Error, Equatable, Sendable {
        case duplicate
        case prefixConflict
        case containsPaste
    }

    public enum Match: Sendable {
        case miss
        case prefix
        case exact(Action)
    }

    private var bindings: [KeySequence: Action] = [:]

    public init() {}

    public var isEmpty: Bool { bindings.isEmpty }
    public var count: Int { bindings.count }

    /// Registers a binding.
    public mutating func register(_ binding: KeyBinding<Action>) throws {
        try register(binding.sequence, action: binding.action)
    }

    /// Registers the action for the given sequence.
    public mutating func register(_ sequence: KeySequence, action: Action) throws {
        // 防御:即使调用方绕过 ``KeyStroke`` 的公共 init 构造出 paste-bearing stroke,
        // 也不允许注册——否则会留下"可注册但永远不可触发"的死绑定。
        for stroke in sequence.strokes {
            if case .paste = stroke.key {
                throw RegistrationError.containsPaste
            }
        }
        if bindings[sequence] != nil {
            throw RegistrationError.duplicate
        }
        // 新序列的任一真前缀都不能是已注册的完整命令。
        if sequence.count > 1 {
            for length in 1..<sequence.count {
                let prefix = KeySequence(Array(sequence.strokes.prefix(length)))
                if bindings[prefix] != nil {
                    throw RegistrationError.prefixConflict
                }
            }
        }
        // 已注册的任何序列都不能以新序列为真前缀。
        for existing in bindings.keys where existing.count > sequence.count {
            let head = Array(existing.strokes.prefix(sequence.count))
            if head == sequence.strokes {
                throw RegistrationError.prefixConflict
            }
        }
        bindings[sequence] = action
    }

    /// Unregisters the given sequence. Returns false if it does not exist.
    @discardableResult
    public mutating func unregister(_ sequence: KeySequence) -> Bool {
        bindings.removeValue(forKey: sequence) != nil
    }

    /// Clears the registry.
    public mutating func removeAll() {
        bindings.removeAll()
    }

    /// Queries the match state of the currently buffered sequence.
    public func match(_ strokes: [KeyStroke]) -> Match {
        guard !strokes.isEmpty else { return .miss }
        let sequence = KeySequence(strokes)
        if let action = bindings[sequence] {
            return .exact(action)
        }
        for existing in bindings.keys where existing.count > strokes.count {
            if Array(existing.strokes.prefix(strokes.count)) == strokes {
                return .prefix
            }
        }
        return .miss
    }

    /// A snapshot of all registered bindings (order not guaranteed).
    public var allBindings: [(KeySequence, Action)] {
        bindings.map { ($0.key, $0.value) }
    }
}
