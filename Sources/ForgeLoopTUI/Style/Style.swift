import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum Style {
    public enum RenderingMode: Sendable {
        case automatic
        case ansi
        case plain
    }

    public static func user(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(foreground: .standard(6)), mode: mode, capability: capability)
    }

    public static func prompt(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(bold: true, foreground: .standard(6)), mode: mode, capability: capability)
    }

    public static func dimmed(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(dim: true), mode: mode, capability: capability)
    }

    public static func header(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(bold: true, foreground: .bright(5)), mode: mode, capability: capability)
    }

    public static func running(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(foreground: .standard(3)), mode: mode, capability: capability)
    }

    public static func success(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(foreground: .standard(2)), mode: mode, capability: capability)
    }

    public static func warning(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(foreground: .standard(3)), mode: mode, capability: capability)
    }

    public static func error(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        styled(text, spec: StyleSpec(foreground: .standard(1)), mode: mode, capability: capability)
    }

    public static func selection(_ text: String, mode: RenderingMode = .automatic, capability: TerminalCapability = .truecolor) -> String {
        // reverse video (7) + bold (1)
        styled(text, spec: StyleSpec(bold: true, reverse: true), mode: mode, capability: capability)
    }

    // MARK: - Internal

    /// 将结构化样式规格渲染为带 ANSI 转义序列的文本。
    static func styled(_ text: String, spec: StyleSpec, mode: RenderingMode, capability: TerminalCapability) -> String {
        guard shouldEmitANSI(mode: mode) else { return text }
        let prefix = renderSGR(spec, capability: capability)
        let reset = capability == .plain ? "" : "\(escapePrefix)0m"
        guard !prefix.isEmpty else { return text }
        return "\(prefix)\(text)\(reset)"
    }

    static func renderSGR(_ spec: StyleSpec, capability: TerminalCapability) -> String {
        guard capability != .plain else { return "" }
        var codes: [Int] = []
        if spec.reverse { codes.append(7) }
        if spec.bold { codes.append(1) }
        if spec.dim { codes.append(2) }
        if let fg = spec.foreground {
            codes.append(contentsOf: fg.sgrCodes(isBackground: false, capability: capability))
        }
        if let bg = spec.background {
            codes.append(contentsOf: bg.sgrCodes(isBackground: true, capability: capability))
        }
        guard !codes.isEmpty else { return "" }
        return "\(escapePrefix)\(codes.map(String.init).joined(separator: ";"))m"
    }

    // MARK: - Private

    private static let escapePrefix = "\u{1B}["

    private static func shouldEmitANSI(mode: RenderingMode) -> Bool {
        switch mode {
        case .ansi:
            return true
        case .plain:
            return false
        case .automatic:
            return supportsANSIStyling()
        }
    }

    private static func supportsANSIStyling(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["NO_COLOR"] != nil {
            return false
        }
        if let forceColor = environment["FORGELOOP_TUI_FORCE_COLOR"], forceColor != "0" {
            return true
        }
        if let forceColor = environment["CLICOLOR_FORCE"], forceColor != "0" {
            return true
        }
        if environment["TERM"]?.lowercased() == "dumb" {
            return false
        }
        return isatty(STDOUT_FILENO) == 1
    }
}

/// 结构化样式规格，供 `Style` 内部使用。
public struct StyleSpec: Sendable, Equatable {
    public var bold: Bool = false
    public var dim: Bool = false
    public var reverse: Bool = false
    public var foreground: Color? = nil
    public var background: Color? = nil

    public init(bold: Bool = false, dim: Bool = false, reverse: Bool = false, foreground: Color? = nil, background: Color? = nil) {
        self.bold = bold
        self.dim = dim
        self.reverse = reverse
        self.foreground = foreground
        self.background = background
    }
}
