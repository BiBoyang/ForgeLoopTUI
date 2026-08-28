import Foundation

/// The output produced by ``KeyResolver``.
///
/// - ``action(_:)``: a bound command was matched in full.
/// - ``passthrough(_:)``: the event belongs to no binding and should be handed back to the caller (e.g. to insert text).
public enum ResolvedKey<Action: Sendable>: Sendable {
    case action(Action)
    case passthrough(KeyEvent)
}

/// A stateful key-sequence resolver.
///
/// Accepts ``KeyEvent`` values and emits ``ResolvedKey`` based on the injected ``KeybindingRegistry``.
/// Maintains a pending buffer to support multi-key chords: on a prefix hit it enters the pending
/// state until (a) later input completes an exact match, (b) later input breaks the match, or (c) timeout.
///
/// Behavioral details:
/// - On timeout, buffered events are released in order as passthrough.
/// - If `pending + current` does not match but `current` alone is a prefix/exact match, the pending
///   events are passed through and matching restarts from the current event.
/// - ``Key/paste(_:)`` always passes through: pending events are released first, then paste is forwarded.
///
/// Concurrency: instances keep mutable state and are **not Sendable**.
/// Callers must serialize all `feed` / `tick` / `flush` / `replaceRegistry` calls
/// (e.g. on a single actor or thread). The library does not support cross-actor sharing.
///
/// Stability: Provisional.
public final class KeyResolver<Action: Sendable> {
    /// The default chord timeout (nanoseconds), about 500 milliseconds.
    public static var defaultTimeoutNanoseconds: UInt64 { 500_000_000 }

    private let clock: InputClock
    private let timeout: UInt64
    private var registry: KeybindingRegistry<Action>

    private var pendingStrokes: [KeyStroke] = []
    private var pendingEvents: [KeyEvent] = []
    private var pendingDeadline: UInt64 = 0

    public init(
        registry: KeybindingRegistry<Action>,
        clock: (any InputClock)? = nil,
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.registry = registry
        self.clock = clock ?? SystemInputClock()
        self.timeout = timeoutNanoseconds ?? Self.defaultTimeoutNanoseconds
    }

    /// Replaces the underlying registry. Any current pending events are released as passthrough.
    public func replaceRegistry(_ registry: KeybindingRegistry<Action>) -> [ResolvedKey<Action>] {
        let flushed = flushPending()
        self.registry = registry
        return flushed
    }

    /// Feeds a ``KeyEvent``. Returns zero or more resolved results.
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

    /// A clock hook driven externally (e.g. when the event loop is idle). Handles timeout fallback.
    public func tick() -> [ResolvedKey<Action>] {
        flushIfExpired()
    }

    /// Forces the pending buffer to be released (ignoring the timeout window).
    public func flush() -> [ResolvedKey<Action>] {
        flushPending()
    }

    /// Whether a chord prefix is awaiting continuation.
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
