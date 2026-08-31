import XCTest
@testable import ForgeLoopTUI

/// Regression tests for the operation-slot settle defect (TASK-32): a
/// pending operation's transient status line (`⎿ running...`) was committed
/// to scrollback before `operationEnd` replaced it in the buffer, so
/// append-only consumers leaked the stale status and dropped the first
/// result line; additionally every result line carried its own `⎿ done:`
/// prefix, making one call look like N completions.
///
/// The fix is two-part:
/// 1. `TranscriptRenderer.firstUnsettledLineIndex` marks the first line
///    that may still change in place (earliest pending status line);
///    `StreamingTranscriptAppendState.consume(...:unsettledFrom:)` never
///    commits at or past it.
/// 2. On settle, only the first result line carries the `⎿ done:` /
///    `⎿ failed:` prefix; continuation lines are content-aligned.
@MainActor
final class OperationSlotSettleTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private final class AppendHarness {
        let renderer = TranscriptRenderer()
        var appendState = StreamingTranscriptAppendState()
        private(set) var appended: [String] = []

        func apply(_ event: CoreRenderEvent) {
            renderer.applyCore(event)
            drain()
        }

        func drain() {
            appended += appendState.consume(
                transcript: renderer.transcriptLines,
                activeRange: renderer.activeStreamingRange,
                stableLineCount: renderer.activeStreamingStableLineCount,
                unsettledFrom: renderer.firstUnsettledLineIndex
            )
        }

        /// Append-only 输出的终极不变量：最终 transcript 的每一行恰好
        /// 被提交一次、按序；transient 内容（running...）从未出现。
        func assertCommittedExactlyFinalTranscript(
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                appended,
                renderer.transcriptLines,
                "every transcript line must be committed exactly once, in order",
                file: file,
                line: line
            )
            XCTAssertFalse(
                appended.contains { $0.contains("running") },
                "transient status line must never reach the scrollback",
                file: file,
                line: line
            )
        }
    }

    // MARK: - 1) 症状回归：start 与 end 之间发生提交，running... 不泄漏

    func testSettleAfterCommitDoesNotLeakRunningStatus() {
        let harness = AppendHarness()
        harness.apply(.insert(lines: ["❯ ls"]))
        harness.apply(.operationStart(id: "t1", header: "● bash(command: ls)", status: "⎿ running..."))
        // 此处 consume 已把 header 提交进 scrollback；status 行必须被拦住。
        harness.apply(.operationEnd(
            id: "t1",
            isError: false,
            result: "total 4520\ndrwxr-x---+ 8 boyang staff 256\n..."
        ))

        harness.assertCommittedExactlyFinalTranscript()
        XCTAssertEqual(harness.renderer.transcriptLines, [
            "❯ ls",
            "● bash(command: ls)",
            "⎿ done: total 4520",
            "        drwxr-x---+ 8 boyang staff 256",
            "        ...",
        ])
    }

    // MARK: - 2) 多行结果聚合：只有第一行带 done: 前缀

    func testMultiLineResultAggregatesUnderSinglePrefix() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.operationStart(id: "t1", header: "h", status: "s"))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "l1\nl2\nl3"))

        let lines = renderer.transcriptLines
        XCTAssertEqual(lines, [
            "h",
            "⎿ done: l1",
            "        l2",
            "        l3",
        ])
        XCTAssertEqual(lines.filter { $0.hasPrefix("⎿ done") }.count, 1)
    }

    func testFailedMultiLineResultAggregatesUnderSinglePrefix() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.operationStart(id: "t1", header: "h", status: "s"))
        renderer.applyCore(.operationEnd(id: "t1", isError: true, result: "e1\ne2"))

        XCTAssertEqual(renderer.transcriptLines, [
            "h",
            "⎿ failed: e1",
            "          e2",
        ])
    }

    func testSingleLineAndEmptyResultsKeepExistingShape() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.operationStart(id: "t1", header: "h1", status: "s"))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "only"))
        renderer.applyCore(.operationStart(id: "t2", header: "h2", status: "s"))
        renderer.applyCore(.operationEnd(id: "t2", isError: false, result: nil))

        XCTAssertEqual(renderer.transcriptLines, [
            "h1",
            "⎿ done: only",
            "h2",
            "⎿ done",
        ])
    }

    // MARK: - 3) operationCancel：同槽位替换语义

    func testOperationCancelReplacesStatusLine() {
        let harness = AppendHarness()
        harness.apply(.operationStart(id: "t1", header: "● bash(command: sleep)", status: "⎿ running..."))
        harness.apply(.operationCancel(id: "t1"))

        harness.assertCommittedExactlyFinalTranscript()
        XCTAssertEqual(harness.renderer.transcriptLines, [
            "● bash(command: sleep)",
            "⎿ cancelled",
        ])
        XCTAssertEqual(harness.renderer.pendingToolCount, 0)
        XCTAssertNil(harness.renderer.firstUnsettledLineIndex)
    }

    // MARK: - 4) 并行 slot：out-of-order settle / cancel 均不泄漏

    func testOutOfOrderSettleAndCancelNeverLeakRunning() {
        let harness = AppendHarness()
        harness.apply(.operationStart(id: "a", header: "● A", status: "⎿ running..."))
        harness.apply(.operationStart(id: "b", header: "● B", status: "⎿ running..."))
        harness.apply(.operationStart(id: "c", header: "● C", status: "⎿ running..."))

        harness.apply(.operationEnd(id: "b", isError: false, result: "rb"))
        harness.apply(.operationEnd(id: "a", isError: false, result: "a1\na2"))
        harness.apply(.operationCancel(id: "c"))

        harness.assertCommittedExactlyFinalTranscript()
        // slot 顺序不变：A, B, C
        XCTAssertEqual(harness.renderer.transcriptLines, [
            "● A",
            "⎿ done: a1",
            "        a2",
            "● B",
            "⎿ done: rb",
            "● C",
            "⎿ cancelled",
        ])
    }

    // MARK: - 5) pending slot 位于 streaming block 之前：block 的 stable
    //    提交不得越过未结算的 status 行

    func testPendingOperationBeforeStreamingBlockHoldsCommitBoundary() {
        let harness = AppendHarness()
        harness.apply(.operationStart(id: "t1", header: "● tool", status: "⎿ running..."))
        harness.apply(.blockStart(id: "b"))
        harness.apply(.blockUpdate(id: "b", lines: ["para1\n\npara2"]))

        // op 未结算：consume 只能提交 header，status 行与 block 内容都必须留住
        XCTAssertEqual(harness.appended, ["● tool"])

        harness.apply(.operationEnd(id: "t1", isError: false, result: "ok"))
        harness.apply(.blockEnd(id: "b", lines: ["para1\n\npara2"], footer: nil))

        harness.assertCommittedExactlyFinalTranscript()
        XCTAssertEqual(harness.renderer.transcriptLines, [
            "● tool",
            "⎿ done: ok",
            "para1",
            "",
            "para2",
            "",
        ])
    }

    // MARK: - 6) 未知 / 已结算 id 的 end 与 cancel 被忽略

    func testUnknownOrSettledIDsAreIgnored() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.operationEnd(id: "nope", isError: false, result: "x"))
        renderer.applyCore(.operationCancel(id: "nope"))
        XCTAssertEqual(renderer.transcriptLines, [])

        renderer.applyCore(.operationStart(id: "t1", header: "h", status: "s"))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "ok"))
        // 已结算后再到 end/cancel：不得二次改写
        renderer.applyCore(.operationEnd(id: "t1", isError: true, result: "late"))
        renderer.applyCore(.operationCancel(id: "t1"))

        XCTAssertEqual(renderer.transcriptLines, ["h", "⎿ done: ok"])
        XCTAssertEqual(renderer.pendingToolCount, 0)
    }

    // MARK: - 7) firstUnsettledLineIndex 的生命周期

    func testFirstUnsettledLineIndexTracksPendingSlots() {
        let renderer = TranscriptRenderer()
        XCTAssertNil(renderer.firstUnsettledLineIndex)

        renderer.applyCore(.insert(lines: ["❯ go"]))
        renderer.applyCore(.operationStart(id: "t1", header: "h1", status: "s1"))
        XCTAssertEqual(renderer.firstUnsettledLineIndex, 2) // status 行，header 可提交

        renderer.applyCore(.operationStart(id: "t2", header: "h2", status: "s2"))
        XCTAssertEqual(renderer.firstUnsettledLineIndex, 2)

        // t1 多行结算撑开 slot，t2 的 status 行随之后移
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "a\nb"))
        XCTAssertEqual(renderer.firstUnsettledLineIndex, 5)

        renderer.applyCore(.operationEnd(id: "t2", isError: false, result: nil))
        XCTAssertNil(renderer.firstUnsettledLineIndex)
    }

    // MARK: - 8) 不传 unsettledFrom 的旧调用保持既有行为（向后兼容）

    func testConsumeWithoutUnsettledFromKeepsLegacyBehavior() {
        var state = StreamingTranscriptAppendState()
        let emitted = state.consume(
            transcript: ["a", "b"],
            activeRange: nil,
            stableLineCount: 0
        )
        XCTAssertEqual(emitted, ["a", "b"])
    }
}
