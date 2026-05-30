import Foundation

/// 可注入的单调时间源，用于 `InputPipeline` 的 ESC 超时判断。
///
/// 生产环境使用 `SystemInputClock`，测试环境使用手动控制的实现。
public protocol InputClock: Sendable {
    /// 返回单调递增的时间戳，单位纳秒。
    func now() -> UInt64
}

/// 基于 `DispatchTime` 的系统时钟。
struct SystemInputClock: InputClock {
    public init() {}
    public func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
