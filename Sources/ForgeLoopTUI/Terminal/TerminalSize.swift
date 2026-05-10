import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct TerminalSize: Sendable, Equatable {
    public let rows: Int
    public let columns: Int

    public init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
    }
}

public func getTerminalSize() -> TerminalSize? {
    var ws = winsize()
    guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 else { return nil }
    return TerminalSize(rows: Int(ws.ws_row), columns: Int(ws.ws_col))
}
