import XCTest
@testable import ForgeLoopTUI

@MainActor
final class TranscriptRendererToolResultTests: XCTestCase {

    // MARK: - 1) Tool success with summary renders "done: <summary>"

    func testToolSuccessWithSummary() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-1", toolName: "read", args: "{\"path\":\"file.txt\"}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-1", toolName: "read", isError: false, summary: "hello world"))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("● read({\"path\":\"file.txt\"})"))
        XCTAssertTrue(lines.contains("⎿ done: hello world"))
        XCTAssertFalse(lines.contains("⎿ running..."))
    }

    // MARK: - 2) Tool failure with summary renders "failed: <summary>"

    func testToolFailureWithSummary() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-2", toolName: "read", args: "{\"path\":\"missing\"}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-2", toolName: "read", isError: true, summary: "File not found"))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ failed: File not found"))
        XCTAssertFalse(lines.contains("⎿ running..."))
    }

    // MARK: - 3) Tool with nil summary falls back to plain "done"/"failed"

    func testToolWithNilSummary() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-3", toolName: "write", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-3", toolName: "write", isError: false, summary: nil))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done"))
        XCTAssertFalse(lines.contains("⎿ done: \"\""))
    }

    // MARK: - 4) Empty output summary renders "(no output)"

    func testToolEmptyOutputSummary() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-4", toolName: "bash", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-4", toolName: "bash", isError: false, summary: "(no output)"))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done: (no output)"))
    }

    // MARK: - 5) Long summary is already truncated by AgentLoop (<= 80 + "...")

    func testToolLongSummaryRendering() {
        let renderer = TranscriptRenderer()
        let longSummary = String(repeating: "a", count: 80) + "..."
        renderer.apply(.toolExecutionStart(toolCallId: "tc-5", toolName: "read", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-5", toolName: "read", isError: false, summary: longSummary))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done: \(longSummary)"))
    }

    // MARK: - 6) Multiple tools with mixed summaries, each replaced independently

    func testMultipleToolsWithMixedSummaries() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "a", toolName: "read", args: "1"))
        renderer.apply(.toolExecutionStart(toolCallId: "b", toolName: "write", args: "2"))
        renderer.apply(.toolExecutionStart(toolCallId: "c", toolName: "bash", args: "3"))

        renderer.apply(.toolExecutionEnd(toolCallId: "a", toolName: "read", isError: false, summary: "file content"))
        renderer.apply(.toolExecutionEnd(toolCallId: "b", toolName: "write", isError: true, summary: "permission denied"))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done: file content"))
        XCTAssertTrue(lines.contains("⎿ failed: permission denied"))
        XCTAssertTrue(lines.contains("⎿ running..."))
        XCTAssertEqual(lines.filter { $0 == "⎿ running..." }.count, 1)
    }

    // MARK: - 7) Tool result between assistant streaming messages doesn't corrupt transcript

    func testToolResultBetweenAssistantMessages() {
        let renderer = TranscriptRenderer()

        // First assistant message
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "Here is the result:", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "Here is the result:", thinking: nil, errorMessage: nil)))

        // Tool execution
        renderer.apply(.toolExecutionStart(toolCallId: "tc-7", toolName: "read", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-7", toolName: "read", isError: false, summary: "data"))

        // Second assistant message
        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(text: "Done", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(text: "Done", thinking: nil, errorMessage: nil)))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("Here is the result:"))
        XCTAssertTrue(lines.contains("⎿ done: data"))
        XCTAssertTrue(lines.contains("Done"))

        // Verify streamingRange was cleared after first messageEnd
        // (by checking no duplicate content from previous streaming)
        let assistantLineCount = lines.filter { $0 == "Here is the result:" }.count
        XCTAssertEqual(assistantLineCount, 1)
    }

    // MARK: - 8) Tool summary with newline only uses first line

    func testToolSummaryFirstLineOnly() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-8", toolName: "bash", args: "{}"))
        // AgentLoop should only send first line, but renderer should handle gracefully
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-8", toolName: "bash", isError: false, summary: "first line"))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done: first line"))
    }

    func testToolMultilineSummarySplitsAcrossLogicalLines() {
        let renderer = TranscriptRenderer()
        renderer.apply(.toolExecutionStart(toolCallId: "tc-9", toolName: "bash", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-9", toolName: "bash", isError: false, summary: "line1\nline2"))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains("⎿ done: line1"))
        XCTAssertTrue(lines.contains("⎿ done: line2"))
    }

    // MARK: - Configurable options

    func testCustomSummaryLinesThreshold() {
        let options = TranscriptRenderOptions(maxSummaryChars: 200, maxSummaryLines: 1)
        let renderer = TranscriptRenderer(options: options)
        renderer.apply(.toolExecutionStart(toolCallId: "tc-opt", toolName: "cat", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-opt", toolName: "cat", isError: false, summary: "line1\nline2\nline3"))

        let lines = renderer.transcriptLines
        // Only 1 line kept, rest truncated
        XCTAssertTrue(lines.contains("⎿ done: line1"))
        XCTAssertFalse(lines.contains("⎿ done: line2"))
        XCTAssertFalse(lines.contains("⎿ done: line3"))
        // Ellipsis indicator present
        XCTAssertTrue(lines.contains("⎿ done: ..."))
    }

    func testCustomSummaryCharsThreshold() {
        let options = TranscriptRenderOptions(maxSummaryChars: 5, maxSummaryLines: 3)
        let renderer = TranscriptRenderer(options: options)
        renderer.apply(.toolExecutionStart(toolCallId: "tc-chars", toolName: "echo", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-chars", toolName: "echo", isError: false, summary: "1234567890"))

        let lines = renderer.transcriptLines
        // Truncated at 5 chars + "..."
        XCTAssertTrue(lines.contains("⎿ done: 12345..."))
    }

    func testNegativeOptionsAreClampedToMinimum() {
        let opts = TranscriptRenderOptions(maxSummaryChars: -5, maxSummaryLines: -1, maxNotificationLines: 0)
        XCTAssertEqual(opts.maxSummaryChars, 1)
        XCTAssertEqual(opts.maxSummaryLines, 1)
        XCTAssertEqual(opts.maxNotificationLines, 1)

        // Should not crash with clamped values
        let renderer = TranscriptRenderer(options: opts)
        renderer.applyCore(.operationStart(id: "t1", header: "h", status: "s"))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "line1\nline2"))
        _ = renderer.transcriptLines
    }

    func testDefaultOptionsAreBackwardCompatible() {
        let renderer = TranscriptRenderer() // default options
        renderer.apply(.toolExecutionStart(toolCallId: "tc-def", toolName: "bash", args: "{}"))
        renderer.apply(.toolExecutionEnd(toolCallId: "tc-def", toolName: "bash", isError: false, summary: String(repeating: "x", count: 130)))

        let lines = renderer.transcriptLines
        // Default maxSummaryChars = 120, so line should be truncated
        let summaryLine = lines.first { $0.contains("⎿ done:") }!
        XCTAssertTrue(summaryLine.hasSuffix("..."))
        XCTAssertEqual(summaryLine.count, "⎿ done: ".count + 120 + 3)
    }
}
