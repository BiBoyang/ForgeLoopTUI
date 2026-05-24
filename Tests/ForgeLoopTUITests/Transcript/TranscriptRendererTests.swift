import XCTest
@testable import ForgeLoopTUI

@MainActor
final class TranscriptRendererTests: XCTestCase {
    // MARK: - 1) messageUpdate 覆盖：两次更新只保留后者文本

    func testStreamingUpdateReplacesPreviousContent() {
        let renderer = TranscriptRenderer()
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "first version", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "second version", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "second version", thinking: nil, errorMessage: nil)))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("second version"))
        XCTAssertFalse(lines.contains("first version"))
    }

    // MARK: - 2) 更新行数缩短：旧尾行不残留

    func testStreamingUpdateShortensLinesNoResidue() {
        let renderer = TranscriptRenderer()
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "line1\nline2\nline3", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "only one", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "only one", thinking: nil, errorMessage: nil)))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("only one"))
        XCTAssertFalse(lines.contains("line1"))
        XCTAssertFalse(lines.contains("line2"))
        XCTAssertFalse(lines.contains("line3"))
    }

    // MARK: - 3) messageEnd 后分隔空行只出现一次

    func testMessageEndAppendsSingleBlankSeparator() {
        let renderer = TranscriptRenderer()
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "hello", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "hello", thinking: nil, errorMessage: nil)))

        let lines = renderer.transcriptLines
        let blankCount = lines.filter { $0.isEmpty }.count
        XCTAssertEqual(blankCount, 1)
    }

    // MARK: - 4) toolExecutionStart -> End：running... 被替换为 done/failed 占位

    func testToolExecutionReplacesRunningWithDone() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-1", toolName: "read_file", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-1", toolName: "read_file", isError: false, summary: nil))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("● read_file({})"))
        XCTAssertTrue(lines.contains("⎿ done"))
        XCTAssertFalse(lines.contains("⎿ running..."))
    }

    func testToolExecutionReplacesRunningWithFailed() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-2", toolName: "bad_tool", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-2", toolName: "bad_tool", isError: true, summary: nil))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("● bad_tool({})"))
        XCTAssertTrue(lines.contains("⎿ failed"))
        XCTAssertFalse(lines.contains("⎿ running..."))
    }

    // MARK: - 5) 多个 tool 同时 pending，各自独立替换

    func testMultiplePendingToolsReplacedIndependently() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "a", toolName: "toolA", args: "1"))
        renderer.apply(.toolExecutionStart(toolCallId: "b", toolName: "toolB", args: "2"))
        renderer.apply(.toolExecutionEnd(toolCallId: "a", toolName: "toolA", isError: false, summary: nil))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done"))
        XCTAssertTrue(lines.contains("⎿ running..."))
        XCTAssertEqual(lines.filter { $0 == "⎿ done" }.count, 1)
        XCTAssertEqual(lines.filter { $0 == "⎿ running..." }.count, 1)
    }

    // MARK: - 6) 超长 summary 渲染端二次截断

    func testVeryLongSummaryIsTruncatedWithEllipsis() {
        let renderer = TranscriptRenderer()
        let veryLong = String(repeating: "x", count: 200)
        renderer.apply(.toolExecutionStart(toolCallId: "tc-long", toolName: "read", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-long", toolName: "read", isError: false, summary: veryLong))

        let lines = renderer.transcriptLines
        let resultLine = lines.first { $0.hasPrefix("⎿ done:") }
        XCTAssertNotNil(resultLine)
        XCTAssertTrue(resultLine!.hasSuffix("..."), "Truncated summary should end with ...")
        XCTAssertLessThanOrEqual(resultLine!.count, 135, "Result line should be reasonably short after truncation")
    }

    // MARK: - 7) 120 字内 summary 不被截断

    func testShortSummaryNotTruncated() {
        let renderer = TranscriptRenderer()
        let shortSummary = String(repeating: "a", count: 100)
        renderer.apply(.toolExecutionStart(toolCallId: "tc-short", toolName: "read", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-short", toolName: "read", isError: false, summary: shortSummary))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done: \(shortSummary)"))
    }

    // MARK: - 8) pendingToolCount 追踪

    func testPendingToolCountTracksActiveTools() {
        let renderer = TranscriptRenderer()
        XCTAssertEqual(renderer.pendingToolCount, 0)

        renderer.apply(.toolExecutionStart(toolCallId: "a", toolName: "toolA", args: "1"))
        XCTAssertEqual(renderer.pendingToolCount, 1)

        renderer.apply(.toolExecutionStart(toolCallId: "b", toolName: "toolB", args: "2"))
        XCTAssertEqual(renderer.pendingToolCount, 2)

        renderer.apply(.toolExecutionEnd(toolCallId: "a", toolName: "toolA", isError: false, summary: nil))
        XCTAssertEqual(renderer.pendingToolCount, 1)

        renderer.apply(.toolExecutionEnd(toolCallId: "b", toolName: "toolB", isError: false, summary: nil))
        XCTAssertEqual(renderer.pendingToolCount, 0)
    }

    // MARK: - 8a) 重复 toolCallId 的 operationStart 被忽略

    func testDuplicateToolStartIsIgnored() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "a", toolName: "toolA", args: "1"))
        renderer.apply(.toolExecutionStart(toolCallId: "a", toolName: "toolA", args: "2"))

        XCTAssertEqual(renderer.pendingToolCount, 1)
        XCTAssertEqual(renderer.slotOrderedToolIDs, ["a"])

        // 只应有一条 running 行
        let runningCount = renderer.transcriptLines.filter { $0.contains("running...") }.count
        XCTAssertEqual(runningCount, 1)
    }

    // MARK: - 8b) out-of-order completion 保持 slot 顺序

    func testOutOfOrderCompletionPreservesSlotOrder() {
        let renderer = TranscriptRenderer()

        // A, B, C 依次开始
        renderer.apply(.toolExecutionStart(toolCallId: "a", toolName: "toolA", args: "1"))
        renderer.apply(.toolExecutionStart(toolCallId: "b", toolName: "toolB", args: "2"))
        renderer.apply(.toolExecutionStart(toolCallId: "c", toolName: "toolC", args: "3"))

        // slot 顺序应为开始顺序
        XCTAssertEqual(renderer.slotOrderedToolIDs, ["a", "b", "c"])

        // B 先完成（out-of-order）
        renderer.apply(.toolExecutionEnd(toolCallId: "b", toolName: "toolB", isError: false, summary: "B-result"))
        XCTAssertEqual(renderer.slotOrderedToolIDs, ["a", "c"])

        // A 完成
        renderer.apply(.toolExecutionEnd(toolCallId: "a", toolName: "toolA", isError: false, summary: "A-result"))
        XCTAssertEqual(renderer.slotOrderedToolIDs, ["c"])

        // C 完成
        renderer.apply(.toolExecutionEnd(toolCallId: "c", toolName: "toolC", isError: false, summary: "C-result"))
        XCTAssertEqual(renderer.slotOrderedToolIDs, [])

        // 验证最终 transcript 按 slot 顺序排列：A, B, C
        let lines = renderer.transcriptLines
        let aIndex = lines.firstIndex { $0.contains("A-result") }!
        let bIndex = lines.firstIndex { $0.contains("B-result") }!
        let cIndex = lines.firstIndex { $0.contains("C-result") }!
        XCTAssertLessThan(aIndex, bIndex, "A should appear before B in slot order")
        XCTAssertLessThan(bIndex, cIndex, "B should appear before C in slot order")
    }

    // MARK: - 9) 长->短->长 连续更新后只保留最终内容

    func testLongShortLongUpdateFinalContentOnly() {
        let renderer = TranscriptRenderer()
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "alpha\nbeta\ngamma", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "x", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "one\ntwo\nthree\nfour", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "one\ntwo\nthree\nfour", thinking: nil, errorMessage: nil)))

        let lines = renderer.transcriptLines.filter { !$0.isEmpty }
        XCTAssertEqual(lines, ["one", "two", "three", "four"])
    }

    // MARK: - 10) 空文本错误消息应可见

    func testErrorMessageShownWhenAssistantTextEmpty() {
        let renderer = TranscriptRenderer()
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "", thinking: nil, errorMessage: "OpenAI Chat Completions HTTP 404: Not Found")))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("[error] OpenAI Chat Completions HTTP 404: Not Found"))
    }

    func testMultilineUserMessageSplitsIntoLogicalLines() {
        let renderer = TranscriptRenderer()

        renderer.apply(.messageStart(message: .user("line1\nline2\nline3")))

        XCTAssertEqual(renderer.transcriptLines, ["❯ line1", "line2", "line3", ""])
    }

    // MARK: - blockCancel (CoreRenderEvent)

    func testBlockCancelClearsStreamingState() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.blockStart(id: "b1"))
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["streaming content"]))
        XCTAssertNotNil(renderer.activeStreamingRange)

        renderer.applyCore(.blockCancel(id: "b1"))

        // Streaming range is cleared
        XCTAssertNil(renderer.activeStreamingRange)
        // Transcript contains cancellation marker + blank separator
        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("[cancelled]"))
        // Streaming content is discarded
        XCTAssertFalse(lines.contains("streaming content"))
    }

    func testBlockCancelDoesNotAffectOtherContent() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.insert(lines: ["before"]))
        renderer.applyCore(.blockStart(id: "b1"))
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["streaming"]))
        renderer.applyCore(.blockCancel(id: "b1"))
        renderer.applyCore(.insert(lines: ["after"]))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("before"))
        XCTAssertTrue(lines.contains("after"))
        XCTAssertTrue(lines.contains("[cancelled]"))
        XCTAssertFalse(lines.contains("streaming"))
    }

    // MARK: - thinking (CoreRenderEvent)

    func testThinkingRendersWithPrefix() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.thinking(content: "reasoning step 1", isFinal: false))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("💭 reasoning step 1"))
    }

    func testThinkingStreamingReplacesPrevious() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.thinking(content: "old reasoning", isFinal: false))
        renderer.applyCore(.thinking(content: "new reasoning", isFinal: false))

        let lines = renderer.transcriptLines
        // New content replaces old
        XCTAssertFalse(lines.contains("💭 old reasoning"))
        XCTAssertTrue(lines.contains("💭 new reasoning"))
    }

    func testThinkingFinalAddsBlankSeparator() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.thinking(content: "done thinking", isFinal: true))
        renderer.applyCore(.insert(lines: ["assistant response"]))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("💭 done thinking"))
        // Blank separator between thinking and assistant
        let thinkingIdx = lines.firstIndex(of: "💭 done thinking")!
        XCTAssertEqual(lines[thinkingIdx + 1], "")
        XCTAssertEqual(lines[thinkingIdx + 2], "assistant response")
    }
}
