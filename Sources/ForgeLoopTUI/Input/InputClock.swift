import Foundation

/// An injectable monotonic time source, used by `InputPipeline` for ESC
/// timeout decisions.
///
/// Production code uses `SystemInputClock`; tests use a manually controlled
/// implementation.
public protocol InputClock: Sendable {
    /// Returns a monotonically increasing timestamp in nanoseconds.
    func now() -> UInt64
}

/// 基于 `DispatchTime` 的系统时钟。
struct SystemInputClock: InputClock {
    public init() {}
    public func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
