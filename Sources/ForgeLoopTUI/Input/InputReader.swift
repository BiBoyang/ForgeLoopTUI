import Foundation
import Dispatch

import Darwin

/// High-level input reader: wraps `RawTTY`, `InputPipeline`, and event-loop
/// scheduling into a component that can be started and stopped directly.
///
/// Internally it uses a `DispatchSourceRead` to watch stdin and a
/// `DispatchSourceTimer` that calls `InputPipeline.tick()` every 10ms to
/// resolve the ESC/Alt ambiguity.
///
/// Supports multiple `start()` / `stop()` cycles: each `start()` re-enters
/// raw mode, and `stop()` restores the terminal attributes.
///
/// Usage:
/// ```swift
/// let reader = try InputReader { events in
///     for event in events { print(event) }
/// }
/// try reader.start()
/// // ...
/// reader.stop()
/// ```
public final class InputReader: @unchecked Sendable {
    private let lock = NSLock()
    private let tty: RawTTY
    private let pipeline: InputPipeline
    private let queue: DispatchQueue
    private let onEvent: @Sendable ([KeyEvent]) -> Void
    private var readSource: DispatchSourceRead?
    private var tickSource: DispatchSourceTimer?
    private var isRunning = false

    /// Whether the reader is currently running.
    public var running: Bool {
        lock.withLock { isRunning }
    }

    /// Creates a reader (does not enter raw mode immediately).
    /// - Parameters:
    ///   - tty: A `RawTTY` instance, defaulting to `STDIN_FILENO`.
    ///   - pipeline: An `InputPipeline` instance.
    ///   - queue: The event dispatch queue, defaulting to `.global(qos: .userInteractive)`.
    ///   - onEvent: Callback for key events.
    public init(
        tty: RawTTY = RawTTY(),
        pipeline: InputPipeline = InputPipeline(),
        queue: DispatchQueue = .global(qos: .userInteractive),
        onEvent: @escaping @Sendable ([KeyEvent]) -> Void
    ) {
        self.tty = tty
        self.pipeline = pipeline
        self.queue = queue
        self.onEvent = onEvent
    }

    /// Enters raw mode and starts the stdin listener and tick timer.
    /// Idempotent: returns immediately if already running.
    /// - Throws: `RawTTYError` if entering raw mode fails.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }

        try tty.enter()

        let fd = tty.fd
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = buffer.withUnsafeMutableBufferPointer { ptr in
                read(fd, ptr.baseAddress!, ptr.count)
            }
            guard count > 0 else { return }
            let bytes = Array(buffer.prefix(count))
            let events = self.pipeline.feed(bytes)
            if !events.isEmpty {
                self.onEvent(events)
            }
        }
        readSource.resume()
        self.readSource = readSource

        let tickSource = DispatchSource.makeTimerSource(queue: queue)
        tickSource.schedule(deadline: .now(), repeating: .milliseconds(10))
        tickSource.setEventHandler { [weak self] in
            guard let self else { return }
            let events = self.pipeline.tick()
            if !events.isEmpty {
                self.onEvent(events)
            }
        }
        tickSource.resume()
        self.tickSource = tickSource

        isRunning = true
    }

    /// Stops listening and restores the terminal attributes.
    /// Idempotent: does nothing if not running.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }

        readSource?.cancel()
        tickSource?.cancel()
        readSource = nil
        tickSource = nil
        tty.restore()
        isRunning = false
    }

    deinit {
        stop()
    }
}
