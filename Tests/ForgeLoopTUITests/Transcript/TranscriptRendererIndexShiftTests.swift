import XCTest
@testable import ForgeLoopTUI

/// 回归测试：原地替换（thinking / streaming）改变总行数时，
/// 排在其后的 pendingTools / streamingRange / thinkingRange 索引必须同步偏移。
@MainActor
final class TranscriptRendererIndexShiftTests: XCTestCase {
    // MARK: - thinking 替换改变行数 → 后续 pendingTools 偏移

    func testThinkingReplacementShiftsPendingToolIndex() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.thinking(content: "first", isFinal: false))
        renderer.applyCore(.operationStart(id: "t1", header: "● tool(1)", status: "⎿ running..."))
        // thinking 由 1 行增长为 3 行，tool 行被向后推 2 行
        renderer.applyCore(.thinking(content: "a\nb\nc", isFinal: false))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "ok"))

        XCTAssertEqual(renderer.transcriptLines, [
            "💭 a",
            "💭 b",
            "💭 c",
            "● tool(1)",
            "⎿ done: ok",
        ])
    }

    // MARK: - thinking 替换改变行数 → 后续 streamingRange 偏移

    func testThinkingReplacementShiftsStreamingRange() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.thinking(content: "t", isFinal: false))
        renderer.applyCore(.blockStart(id: "b1"))
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["hello"]))
        XCTAssertEqual(renderer.activeStreamingRange, 1..<2)

        // thinking 由 1 行增长为 3 行，streaming 块被向后推 2 行
        renderer.applyCore(.thinking(content: "t1\nt2\nt3", isFinal: false))
        XCTAssertEqual(renderer.activeStreamingRange, 3..<4)

        renderer.applyCore(.blockEnd(id: "b1", lines: ["hello"], footer: nil))
        XCTAssertEqual(renderer.transcriptLines, [
            "💭 t1",
            "💭 t2",
            "💭 t3",
            "hello",
            "",
        ])
    }

    // MARK: - streaming 替换改变行数 → 后续 thinkingRange 偏移

    func testStreamingReplacementShiftsThinkingRange() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.blockStart(id: "b1"))
        renderer.applyCore(.thinking(content: "t", isFinal: false))
        // 在空 streamingRange 处插入 1 行，thinking 行被向后推 1 行
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["hello"]))
        renderer.applyCore(.thinking(content: "t2", isFinal: true))

        XCTAssertEqual(renderer.transcriptLines, [
            "hello",
            "💭 t2",
            "",
        ])
    }

    // MARK: - streaming 替换改变行数 → 后续 pendingTools 偏移

    func testStreamingReplacementShiftsPendingToolIndex() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.blockStart(id: "b1"))
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["one"]))
        renderer.applyCore(.operationStart(id: "t1", header: "● tool(1)", status: "⎿ running..."))
        // streaming 由 1 行增长为 2 行，tool 行被向后推 1 行
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["one", "two"]))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: nil))

        XCTAssertEqual(renderer.transcriptLines, [
            "one",
            "two",
            "● tool(1)",
            "⎿ done",
        ])
    }
}
