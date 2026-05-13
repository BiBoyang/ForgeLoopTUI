import Foundation

/// 经 ``KeyResolver`` 解析后的输出。
///
/// - ``action(_:)``: 一段绑定的完整命令匹配成功。
/// - ``passthrough(_:)``: 该事件不属于任何绑定,应交回上层(例如插入文本)。
public enum ResolvedKey<Action: Sendable>: Sendable {
    case action(Action)
    case passthrough(KeyEvent)
}

/// 有状态的按键序列解析器。
///
/// 接受 ``KeyEvent``,根据注入的 ``KeybindingRegistry`` 输出 ``ResolvedKey``。
/// 维护一个 pending 缓冲区以支持多键 chord:在命中前缀时进入 pending 态,直到
/// (a) 后续输入凑齐 exact 匹配,(b) 后续输入打破匹配,或 (c) 超时。
///
/// 行为细节:
/// - 一旦超时,缓冲事件按顺序作为 passthrough 释放。
/// - 若 `pending + current` 不匹配但 `current` 单独是 prefix/exact,则把已 pending
///   事件 passthrough,然后用当前事件重新开始匹配。
/// - ``Key/paste(_:)`` 永远 passthrough,先把 pending 释放再透传 paste。
///
/// 并发约定:实例内部维护可变状态,**非 Sendable**。
/// 调用方需保证所有 `feed` / `tick` / `flush` / `replaceRegistry` 调用串行进行
/// (例如全部在同一个 actor 或同一线程上)。库不提供跨 actor 共享。
///
/// 稳定等级: Provisional。
public final class KeyResolver<Action: Sendable> {
    /// 默认 chord 超时(纳秒),约 500 毫秒。
    public static var defaultTimeoutNanoseconds: UInt64 { 500_000_000 }

    private let clock: InputClock
    private let timeout: UInt64
    private var registry: KeybindingRegistry<Action>

    private var pendingStrokes: [KeyStroke] = []
    private var pendingEvents: [KeyEvent] = []
    private var pendingDeadline: UInt64 = 0

    public init(
        registry: KeybindingRegistry<Action>,
        clock: InputClock = SystemInputClock(),
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.registry = registry
        self.clock = clock
        self.timeout = timeoutNanoseconds ?? Self.defaultTimeoutNanoseconds
    }

    /// 替换底层注册表。当前 pending 会被释放为 passthrough。
    public func replaceRegistry(_ registry: KeybindingRegistry<Action>) -> [ResolvedKey<Action>] {
        let flushed = flushPending()
        self.registry = registry
        return flushed
    }

    /// 喂入一个 ``KeyEvent``。返回零或多个解析结果。
    public func feed(_ event: KeyEvent) -> [ResolvedKey<Action>] {
        var output = flushIfExpired()

        // Paste 永远直接 passthrough,先把当前 pending 释放。
        if case .paste = event.key {
            output.append(contentsOf: flushPending())
            output.append(.passthrough(event))
            return output
        }

        guard let stroke = KeyStroke(event: event) else {
            output.append(contentsOf: flushPending())
            output.append(.passthrough(event))
            return output
        }

        let candidate = pendingStrokes + [stroke]
        switch registry.match(candidate) {
        case .exact(let action):
            pendingStrokes.removeAll()
            pendingEvents.removeAll()
            output.append(.action(action))
            return output

        case .prefix:
            pendingStrokes = candidate
            pendingEvents.append(event)
            pendingDeadline = clock.now() &+ timeout
            return output

        case .miss:
            if !pendingStrokes.isEmpty {
                // 释放已 pending 的事件作为 passthrough,再用当前事件作单事件重试。
                output.append(contentsOf: flushPending())
                switch registry.match([stroke]) {
                case .exact(let action):
                    output.append(.action(action))
                case .prefix:
                    pendingStrokes = [stroke]
                    pendingEvents = [event]
                    pendingDeadline = clock.now() &+ timeout
                case .miss:
                    output.append(.passthrough(event))
                }
                return output
            } else {
                output.append(.passthrough(event))
                return output
            }
        }
    }

    /// 由外部驱动的时钟钩子(例如事件循环空转时)。处理超时回退。
    public func tick() -> [ResolvedKey<Action>] {
        flushIfExpired()
    }

    /// 强制释放 pending 缓冲(忽略超时窗口)。
    public func flush() -> [ResolvedKey<Action>] {
        flushPending()
    }

    /// 是否存在等待延续的 chord 前缀。
    public var hasPending: Bool { !pendingStrokes.isEmpty }

    // MARK: - Private

    private func flushIfExpired() -> [ResolvedKey<Action>] {
        guard !pendingStrokes.isEmpty else { return [] }
        if clock.now() >= pendingDeadline {
            return flushPending()
        }
        return []
    }

    private func flushPending() -> [ResolvedKey<Action>] {
        guard !pendingEvents.isEmpty else {
            pendingStrokes.removeAll()
            return []
        }
        let events = pendingEvents
        pendingStrokes.removeAll()
        pendingEvents.removeAll()
        return events.map { .passthrough($0) }
    }
}
