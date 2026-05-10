import Foundation

public struct ScreenLayout: Sendable, Equatable {
    public var header: [String]
    public var transcript: [String]
    public var queue: [String]
    public var status: [String]
    public var input: [String]

    /// transcript 中需完整保留的行范围（例如 streaming block）
    public var pinnedTranscriptRange: Range<Int>?

    public init(
        header: [String] = [],
        transcript: [String] = [],
        queue: [String] = [],
        status: [String] = [],
        input: [String] = [],
        pinnedTranscriptRange: Range<Int>? = nil
    ) {
        self.header = header
        self.transcript = transcript
        self.queue = queue
        self.status = status
        self.input = input
        self.pinnedTranscriptRange = pinnedTranscriptRange
    }
}

public struct ScreenLayoutConfig: Sendable, Equatable {
    public let terminalHeight: Int
    public let terminalWidth: Int
    public let showHeader: Bool

    public init(
        terminalHeight: Int = 24,
        terminalWidth: Int = 80,
        showHeader: Bool = true
    ) {
        self.terminalHeight = terminalHeight
        self.terminalWidth = terminalWidth
        self.showHeader = showHeader
    }
}
