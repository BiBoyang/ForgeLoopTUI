import Foundation

/// 归一化的单次按键,作为 ``KeySequence`` 与 ``KeybindingRegistry`` 的基础元素。
///
/// 与 ``KeyEvent`` 的差别在于 ``KeyStroke`` 仅描述触发绑定的按键状态;
/// ``Key/paste(_:)`` 不参与匹配——``KeyResolver`` 会将 paste 直接 passthrough。
/// 公共初始化器在传入 paste 时会触发 `preconditionFailure`,以防止构造永远不可触发
/// 的"死绑定"。
///
/// 稳定等级: Provisional。
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

    /// 从 ``KeyEvent`` 构造。Paste 事件返回 nil。
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

/// 一段按键序列。可以是单键也可以是多键 chord。
///
/// 至少包含一个 ``KeyStroke``;空序列触发断言。
///
/// 稳定等级: Provisional。
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

/// 把一段 ``KeySequence`` 映射到下游业务的 `Action`。
///
/// 稳定等级: Provisional。
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

/// 注册按键绑定的容器,提供注册、注销与前缀查询。
///
/// 注册时禁止冲突:
/// - 同一序列重复注册抛出 `RegistrationError.duplicate`。
/// - 某序列同时是另一已注册序列的前缀(或反之),抛出
///   `RegistrationError.prefixConflict`。
///
/// 由此约束,匹配结果只有三种(``Match``):`miss`、`prefix`、`exact(Action)`,
/// ``KeyResolver`` 无需在"立即执行还是等待"间做歧义策略。
///
/// 稳定等级: Provisional。
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

    /// 注册一条绑定。
    public mutating func register(_ binding: KeyBinding<Action>) throws {
        try register(binding.sequence, action: binding.action)
    }

    /// 注册指定序列对应的动作。
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

    /// 注销指定序列。若不存在返回 false。
    @discardableResult
    public mutating func unregister(_ sequence: KeySequence) -> Bool {
        bindings.removeValue(forKey: sequence) != nil
    }

    /// 清空注册表。
    public mutating func removeAll() {
        bindings.removeAll()
    }

    /// 查询当前缓冲序列的匹配状态。
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

    /// 已注册绑定的快照(顺序无保证)。
    public var allBindings: [(KeySequence, Action)] {
        bindings.map { ($0.key, $0.value) }
    }
}
