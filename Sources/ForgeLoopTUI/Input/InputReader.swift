import Foundation
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 高阶输入读取器：将 `RawTTY`、`InputPipeline` 和事件循环调度封装为
/// 一个可直接启动/停止的组件。
///
/// 内部使用 `DispatchSourceRead` 监听 stdin，`DispatchSourceTimer`
/// 以 10ms 周期调用 `InputPipeline.tick()` 解决 ESC/Alt 歧义。
///
/// 支持多次 `start()` / `stop()`：每次 `start()` 都会重新进入 raw mode，
/// `stop()` 恢复终端属性。
///
/// 用法：
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

    /// 当前是否处于运行态。
    public var running: Bool {
        lock.withLock { isRunning }
    }

    /// 创建读取器（不立即进入 raw mode）。
    /// - Parameters:
    ///   - tty: `RawTTY` 实例，默认 `STDIN_FILENO`。
    ///   - pipeline: `InputPipeline` 实例。
    ///   - queue: 事件调度队列，默认 `.global(qos: .userInteractive)`。
    ///   - onEvent: 按键事件回调。
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

    /// 进入 raw mode 并启动 stdin 监听和 tick 定时器。
    /// 幂等：若已在运行，直接返回。
    /// - Throws: `RawTTYError` 若进入 raw mode 失败。
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

    /// 停止监听并恢复终端属性。
    /// 幂等：若未运行，无操作。
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
