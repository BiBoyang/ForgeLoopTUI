import Foundation

/// Terminal ANSI capability level.
public enum TerminalCapability: Sendable {
    /// No color / no styling.
    case plain
    /// Standard 8 colors + bright 8 colors.
    case ansi16
    /// 256-color indexed.
    case ansi256
    /// 24-bit True Color.
    case truecolor
}

/// Unified terminal abstraction covering output capability and TTY state queries.
///
/// Minimal protocol: implementers only need to provide `write(_:)` to send raw
/// bytes, and `isTTY` to declare the environment property.
public protocol Terminal: Sendable {
    /// Whether the terminal is in a TTY (interactive) environment.
    var isTTY: Bool { get }

    /// The ANSI color capability level supported by the terminal.
    var capability: TerminalCapability { get }

    /// Writes raw text to the terminal.
    func write(_ text: String)
}
