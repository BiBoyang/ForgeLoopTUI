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

    public static func user(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "36", mode: mode)
    }

    public static func prompt(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "1;36", mode: mode)
    }

    public static func dimmed(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "2", mode: mode)
    }

    public static func header(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "1;95", mode: mode)
    }

    public static func running(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "33", mode: mode)
    }

    public static func success(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "32", mode: mode)
    }

    public static func warning(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "33", mode: mode)
    }

    public static func error(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "31", mode: mode)
    }

    public static func selection(_ text: String, mode: RenderingMode = .automatic) -> String {
        styled(text, sgr: "7;1", mode: mode)
    }

    private static let escapePrefix = "\u{1B}["
    private static let escapeSuffix = "\(escapePrefix)0m"

    private static func styled(_ text: String, sgr: String, mode: RenderingMode) -> String {
        guard shouldEmitANSI(mode: mode) else { return text }
        return "\(escapePrefix)\(sgr)m\(text)\(escapeSuffix)"
    }

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
