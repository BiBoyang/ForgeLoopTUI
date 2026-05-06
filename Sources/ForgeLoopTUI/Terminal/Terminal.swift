import Foundation

/// 终端 ANSI 能力等级。
public enum TerminalCapability: Sendable {
    /// 无颜色/无样式。
    case plain
    /// 标准 8 色 + 高亮 8 色。
    case ansi16
    /// 256 色索引。
    case ansi256
    /// 24-bit True Color。
    case truecolor
}

/// 统一终端抽象，覆盖输出能力与 TTY 状态查询。
///
/// 最小协议：实现者只需提供 `write(_:)` 发送原始字节，以及 `isTTY` 声明环境属性。
public protocol Terminal: Sendable {
    /// 当前终端是否处于 TTY（交互式）环境。
    var isTTY: Bool { get }

    /// 终端支持的 ANSI 颜色能力等级。
    var capability: TerminalCapability { get }

    /// 向终端写入原始文本。
    func write(_ text: String)
}
