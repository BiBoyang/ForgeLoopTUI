import Foundation

/// Unified render scheduler: 16ms frame coalescing + immediate flush for
/// critical scenarios.
///
/// Frames are submitted via `submit(frame:priority:)`:
/// - `.normal`: joins the coalescing queue; multiple submissions within the
///   same tick keep only the last frame.
/// - `.immediate`: renders the latest frame immediately, without waiting for
///   a tick.
///
/// The timer triggers a flush on each tick; after a flush, if the queue is
/// empty the timer stops to avoid spinning idle.
///
/// Concurrency contract: `render` invocations are **not** serialized by this
/// class. The closure runs on the submitting caller's context for `.immediate`
/// submissions and on the timer's `@MainActor` task for coalesced frames, so
/// concurrent invocations are possible (racing `.immediate` submissions, or an
/// `.immediate` submission racing a tick). The closure must be thread-safe —
/// this is the basis for `RenderLoop`'s `@unchecked Sendable` conformance.
public final class RenderLoop: @unchecked Sendable {
    public enum Priority: Sendable, Equatable {
        case normal
        case immediate
    }

    private let lock = NSLock()
    private let tickInterval: UInt64
    private let render: @Sendable ([String]) -> Void
    private var pendingFrame: [String]?
    private var timerTask: Task<Void, Never>?
    private var isStopped = false

    public init(
        tickIntervalNanoseconds: UInt64 = 16_000_000,
        render: @escaping @Sendable ([String]) -> Void
    ) {
        self.tickInterval = tickIntervalNanoseconds
        self.render = render
    }

    /// Submits a frame. `.normal` enters the coalescing queue; `.immediate`
    /// renders immediately.
    public func submit(frame: [String], priority: Priority = .normal) {
        lock.withLock {
            guard !isStopped else { return }
            pendingFrame = frame
        }
        switch priority {
        case .immediate:
            flush()
        case .normal:
            startTimerIfNeeded()
        }
    }

    /// Stops the scheduler, cancels the timer, and discards the pending frame.
    /// Calling `submit` again after stopping has no effect.
    public func stop() {
        let task: Task<Void, Never>? = lock.withLock {
            let current = timerTask
            timerTask = nil
            return current
        }
        task?.cancel()
        lock.withLock {
            isStopped = true
            pendingFrame = nil
        }
    }

    private func startTimerIfNeeded() {
        let shouldStart = lock.withLock {
            !isStopped && timerTask == nil
        }
        guard shouldStart else { return }

        let interval = tickInterval
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard let self else { return }
                if !self.flushAndShouldContinue() {
                    return
                }
            }
        }

        lock.withLock {
            if isStopped || timerTask != nil {
                task.cancel()
            } else {
                timerTask = task
            }
        }
    }

    private func flush() {
        let frame: [String]? = lock.withLock {
            let frame = pendingFrame
            pendingFrame = nil
            return frame
        }
        guard let frame else { return }
        render(frame)
        _ = stopTimerIfIdle(cancelTask: true)
    }

    private func flushAndShouldContinue() -> Bool {
        let frame: [String]? = lock.withLock {
            let frame = pendingFrame
            pendingFrame = nil
            return frame
        }
        if let frame {
            render(frame)
        }
        return !stopTimerIfIdle(cancelTask: false)
    }

    private func stopTimerIfIdle(cancelTask: Bool) -> Bool {
        let (shouldStop, taskToCancel): (Bool, Task<Void, Never>?) = lock.withLock {
            guard isStopped || pendingFrame == nil else {
                return (false, nil)
            }
            let current = cancelTask ? timerTask : nil
            timerTask = nil
            return (true, current)
        }
        taskToCancel?.cancel()
        return shouldStop
    }
}
