import Foundation

/// 控制 TranscriptRenderer 摘要截断与通知上限的配置。
public struct TranscriptRenderOptions: Sendable, Equatable {
    public var maxSummaryChars: Int
    public var maxSummaryLines: Int
    public var maxNotificationLines: Int

    public static let `default` = TranscriptRenderOptions(
        maxSummaryChars: 120,
        maxSummaryLines: 3,
        maxNotificationLines: 3
    )

    public init(
        maxSummaryChars: Int = 120,
        maxSummaryLines: Int = 3,
        maxNotificationLines: Int = 3
    ) {
        self.maxSummaryChars = max(1, maxSummaryChars)
        self.maxSummaryLines = max(1, maxSummaryLines)
        self.maxNotificationLines = max(1, maxNotificationLines)
    }
}

@MainActor
public final class TranscriptRenderer {
    let lines: TranscriptBuffer
    private var streamingRange: Range<Int>?
    private var completedRange: Range<Int>?
    private var thinkingRange: Range<Int>?
    /// 按开始顺序（slot 顺序）存储的 pending tool。
    private var pendingTools: [(id: String, lineIndex: Int)] = []
    private var notificationLines: [Int] = []
    /// The id of the currently open streaming block, if any.
    ///
    /// Block events are single-active-block: a new `blockStart` implicitly
    /// finalizes the previous block, and `blockUpdate`/`blockEnd`/
    /// `blockCancel` with a non-matching id are ignored.
    private var activeBlockID: String?
    private let markdownEngine: MarkdownEngine
    private let options: TranscriptRenderOptions

    public var pendingToolCount: Int { pendingTools.count }
    public var slotOrderedToolIDs: [String] { pendingTools.map { $0.id } }
    public var activeStreamingRange: Range<Int>? { streamingRange }
    public var lastCompletedAssistantRange: Range<Int>? { completedRange }
    public var preferredPinnedRange: Range<Int>? { streamingRange ?? completedRange }

    public init(
        markdownEngine: MarkdownEngine = StreamingMarkdownEngine(),
        options: TranscriptRenderOptions = .default
    ) {
        self.lines = TranscriptBuffer()
        self.markdownEngine = markdownEngine
        self.options = options
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

        case .blockStart(let id):
            if activeBlockID != nil {
                // 防御性收尾：上一个 block 未 blockEnd 就来了新的 blockStart
                // （如发送方崩溃/错误路径），隐式按现状终结旧 block，
                // 避免两个 block 的流式状态互相覆盖。
                completedRange = streamingRange
                streamingRange = nil
                markdownEngine.reset()
                append("")
            }
            let start = lines.count
            streamingRange = start..<start
            activeBlockID = id
            markdownEngine.reset()

        case .blockUpdate(let id, let newLines):
            if let activeID = activeBlockID {
                // id 失配的 update 属于误用（或迟到事件），忽略。
                guard id == activeID else { break }
            } else {
                // 无 blockStart 直接 update 的旧式用法：隐式开始并收养该 id。
                activeBlockID = id
            }
            replaceStreaming(with: renderMarkdown(lines: newLines, isFinal: false))

        case .blockEnd(let id, let newLines, let footer):
            if let activeID = activeBlockID {
                guard id == activeID else { break }
            }
            replaceStreaming(with: renderMarkdown(lines: newLines, isFinal: true))
            completedRange = streamingRange
            streamingRange = nil
            activeBlockID = nil
            markdownEngine.reset()
            append("")

            if let footer, !footer.isEmpty {
                let trimmed = footer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    append("[error] \(trimmed)")
                    append("")
                }
            }

        case .blockCancel(let id):
            if let activeID = activeBlockID {
                guard id == activeID else { break }
            }
            // 丢弃进行中的流式内容，仅保留取消标记，清理所有 streaming 状态。
            replaceStreaming(with: ["[cancelled]"])
            streamingRange = nil
            completedRange = nil
            activeBlockID = nil
            markdownEngine.reset()
            append("")

        case .thinking(let content, let isFinal):
            let thinkingLines = content.isEmpty
                ? []
                : content.split(separator: "\n", omittingEmptySubsequences: false).map { "💭 \($0)" }
            if let range = thinkingRange {
                let delta = thinkingLines.count - range.count
                lines.replace(range: range, with: thinkingLines)
                if delta != 0 {
                    shiftIndices(after: range.upperBound - 1, by: delta)
                }
                thinkingRange = range.lowerBound..<(range.lowerBound + thinkingLines.count)
            } else {
                let start = lines.count
                lines.append(contentsOf: thinkingLines)
                thinkingRange = start..<(start + thinkingLines.count)
            }
            if isFinal {
                thinkingRange = nil
                append("")
            }

        case .operationStart(let id, let header, let status):
            guard !pendingTools.contains(where: { $0.id == id }) else { break }
            append(header)
            append(status)
            pendingTools.append((id: id, lineIndex: lines.count - 1))

        case .operationEnd(let id, let isError, let result):
            guard let slotIndex = pendingTools.firstIndex(where: { $0.id == id }) else { break }
            let lineIndex = pendingTools[slotIndex].lineIndex
            pendingTools.remove(at: slotIndex)
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
        var previewLines = Array(allLines.prefix(options.maxSummaryLines))

        if allLines.count > options.maxSummaryLines {
            previewLines.append("...")
        }

        return previewLines.map { line in
            if line.count > options.maxSummaryChars {
                let endIndex = line.index(line.startIndex, offsetBy: options.maxSummaryChars)
                return String(line[..<endIndex]) + "..."
            }
            return line
        }
    }

    private func appendNotification(_ line: String) {
        lines.append(line)
        notificationLines.append(lines.count - 1)

        while notificationLines.count > options.maxNotificationLines {
            let oldIndex = notificationLines.removeFirst()
            lines.replace(range: oldIndex..<(oldIndex + 1), with: [])
            shiftIndices(after: oldIndex - 1, by: -1)
        }
    }

    private func shiftIndices(after threshold: Int, by delta: Int) {
        for index in pendingTools.indices {
            if pendingTools[index].lineIndex > threshold {
                pendingTools[index].lineIndex += delta
            }
        }
        for index in notificationLines.indices {
            if notificationLines[index] > threshold {
                notificationLines[index] += delta
            }
        }
        // range 以 lowerBound 整体判定：排在编辑点之后的 range 两个边界一起偏移。
        // 独立比较 upperBound 会把"恰好结束于编辑点"的相邻 range（如 thinking 紧跟
        // streaming 插入点、中间无空行）错误地撑大。
        if let range = streamingRange, range.lowerBound > threshold {
            streamingRange = (range.lowerBound + delta)..<(range.upperBound + delta)
        }
        if let range = completedRange, range.lowerBound > threshold {
            completedRange = (range.lowerBound + delta)..<(range.upperBound + delta)
        }
        if let range = thinkingRange, range.lowerBound > threshold {
            thinkingRange = (range.lowerBound + delta)..<(range.upperBound + delta)
        }
    }

    private func replaceStreaming(with newLines: [String]) {
        let range = streamingRange ?? (lines.count..<lines.count)
        let delta = newLines.count - range.count
        lines.replace(range: range, with: newLines)
        if delta != 0 {
            shiftIndices(after: range.upperBound - 1, by: delta)
        }
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

    func append(contentsOf lines: [String]) {
        all.append(contentsOf: lines)
    }

    func replace(range: Range<Int>, with lines: [String]) {
        let lower = max(0, min(range.lowerBound, all.count))
        let upper = max(lower, min(range.upperBound, all.count))
        all.replaceSubrange(lower..<upper, with: lines)
    }
}
