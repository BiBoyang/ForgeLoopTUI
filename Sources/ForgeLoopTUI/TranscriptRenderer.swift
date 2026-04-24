import Foundation

@MainActor
public final class TranscriptRenderer {
    let lines: TranscriptBuffer
    private var streamingRange: Range<Int>?
    private var completedRange: Range<Int>?
    private var pendingTools: [String: Int] = [:]
    private var notificationLines: [Int] = []
    private let markdownEngine: MarkdownEngine

    public var pendingToolCount: Int { pendingTools.count }
    public var activeStreamingRange: Range<Int>? { streamingRange }
    public var lastCompletedAssistantRange: Range<Int>? { completedRange }
    public var preferredPinnedRange: Range<Int>? { streamingRange ?? completedRange }

    private let maxSummaryChars = 120
    private let maxSummaryLines = 3
    private let maxNotificationLines = 3

    public init(markdownEngine: MarkdownEngine = StreamingMarkdownEngine()) {
        self.lines = TranscriptBuffer()
        self.markdownEngine = markdownEngine
    }

    public convenience init(markdownOptions: MarkdownRenderOptions) {
        self.init(markdownEngine: StreamingMarkdownEngine(options: markdownOptions))
    }

    public var transcriptLines: [String] { lines.all }

    public func applyCore(_ event: CoreRenderEvent) {
        switch event {
        case .insert(let newLines):
            completedRange = nil
            for line in newLines {
                append(line)
            }

        case .blockStart:
            let start = lines.count
            streamingRange = start..<start
            markdownEngine.reset()

        case .blockUpdate(_, let newLines):
            replaceStreaming(with: renderMarkdown(lines: newLines, isFinal: false))

        case .blockEnd(_, let newLines, let footer):
            replaceStreaming(with: renderMarkdown(lines: newLines, isFinal: true))
            completedRange = streamingRange
            streamingRange = nil
            markdownEngine.reset()
            append("")

            if let footer, !footer.isEmpty {
                let trimmed = footer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    append("[error] \(trimmed)")
                    append("")
                }
            }

        case .operationStart(let id, let header, let status):
            append(header)
            append(status)
            pendingTools[id] = lines.count - 1

        case .operationEnd(let id, let isError, let result):
            guard let lineIndex = pendingTools.removeValue(forKey: id) else { break }
            let prefix = isError ? "⎿ failed" : "⎿ done"
            let previewLines = formatToolResult(result)
            let resultLines = previewLines.isEmpty ? [prefix] : previewLines.map { "\(prefix): \($0)" }
            lines.replace(range: lineIndex..<(lineIndex + 1), with: resultLines)
            let delta = resultLines.count - 1
            if delta != 0 {
                shiftIndices(after: lineIndex, by: delta)
            }

        case .notification(let text):
            appendNotification("▸ \(text)")
        }
    }

    @available(*, deprecated, message: "Use applyCore(_:) with CoreRenderEvent instead")
    public func apply(_ event: RenderEvent) {
        applyCore(LegacyRenderEventAdapter.adapt(event))
    }

    private func formatToolResult(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }

        let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var previewLines = Array(allLines.prefix(maxSummaryLines))

        if allLines.count > maxSummaryLines {
            previewLines.append("...")
        }

        return previewLines.map { line in
            if line.count > maxSummaryChars {
                let endIndex = line.index(line.startIndex, offsetBy: maxSummaryChars)
                return String(line[..<endIndex]) + "..."
            }
            return line
        }
    }

    private func appendNotification(_ line: String) {
        lines.append(line)
        notificationLines.append(lines.count - 1)

        while notificationLines.count > maxNotificationLines {
            let oldIndex = notificationLines.removeFirst()
            lines.replace(range: oldIndex..<(oldIndex + 1), with: [])
            shiftIndices(after: oldIndex - 1, by: -1)
        }
    }

    private func shiftIndices(after threshold: Int, by delta: Int) {
        for (toolCallId, lineIdx) in pendingTools {
            if lineIdx > threshold {
                pendingTools[toolCallId] = lineIdx + delta
            }
        }
        for index in notificationLines.indices {
            if notificationLines[index] > threshold {
                notificationLines[index] += delta
            }
        }
        if let range = streamingRange {
            let newLower = range.lowerBound > threshold ? range.lowerBound + delta : range.lowerBound
            let newUpper = range.upperBound > threshold ? range.upperBound + delta : range.upperBound
            streamingRange = newLower..<newUpper
        }
        if let range = completedRange {
            let newLower = range.lowerBound > threshold ? range.lowerBound + delta : range.lowerBound
            let newUpper = range.upperBound > threshold ? range.upperBound + delta : range.upperBound
            completedRange = newLower..<newUpper
        }
    }

    private func replaceStreaming(with newLines: [String]) {
        let range = streamingRange ?? (lines.count..<lines.count)
        lines.replace(range: range, with: newLines)
        streamingRange = range.lowerBound..<(range.lowerBound + newLines.count)
    }

    private func renderMarkdown(lines rawLines: [String], isFinal: Bool) -> [String] {
        guard !rawLines.isEmpty else { return [] }

        var prefixLines: [String] = []
        var contentStart = 0
        for (index, line) in rawLines.enumerated() {
            let plain = ansiStripped(line)
            if plain.hasPrefix("💭 ") {
                prefixLines.append(line)
                contentStart = index + 1
                continue
            }
            break
        }

        let contentLines = Array(rawLines.dropFirst(contentStart))
        guard !contentLines.isEmpty else { return prefixLines }
        let text = contentLines.joined(separator: "\n")
        let rendered = markdownEngine.render(text: text, isFinal: isFinal)
        return prefixLines + rendered
    }

    private func append(_ line: String) {
        lines.append(line)
    }
}

@MainActor
final class TranscriptBuffer {
    init() {}

    private(set) var all: [String] = []

    var count: Int { all.count }

    func append(_ line: String) {
        all.append(line)
    }

    func replace(range: Range<Int>, with lines: [String]) {
        let lower = max(0, min(range.lowerBound, all.count))
        let upper = max(lower, min(range.upperBound, all.count))
        all.replaceSubrange(lower..<upper, with: lines)
    }
}
