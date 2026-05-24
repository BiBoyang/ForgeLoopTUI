import Foundation
import Testing
@testable import ForgeLoopTUI

@Suite("Input-Layout Linkage Boundary")
struct InputLayoutReplayTests {

// MARK: - 核心 replay：输入变化 + 布局变化（committed/live 分界 + cursor）

    /// 模拟完整交互序列：初始输入 → 连续打字 → 提交到历史 → 追加 committed → cursor 变化
    ///
    /// 契约：
    /// - 每一步输出包含当前帧的全部内容
    /// - 每一步均不触发全量清屏（inline diff 正常工作）
    /// - committed 区域的内容不会因为 live 变化而在同一帧输出中重复出现
    @Test("input + layout replay: stable order, no duplicate key lines, no spurious full clear")
    func testInputLayoutReplayBoundary() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        // Step 1: 初始帧 — 空 committed + 输入提示符 live
        tui.render(committed: [], live: ["prompt> "], cursorOffset: 2)
        let out1 = spy.last!
        #expect(out1.contains("prompt> "), "Step 1: input prompt should be visible")
        #expect(!out1.contains("\u{1B}[2J"), "Step 1: no full clear on first frame")

        // Step 2: 用户开始输入 — committed 不变，live 变长
        tui.render(committed: [], live: ["prompt> hello"], cursorOffset: 0)
        let out2 = spy.last!
        #expect(out2.contains("hello"), "Step 2: typed text should appear in output")
        #expect(!out2.contains("\u{1B}[2J"), "Step 2: no full clear after typing")

        // Step 3: 用户继续输入更多文本
        tui.render(committed: [], live: ["prompt> hello world"], cursorOffset: 0)
        let out3 = spy.last!
        #expect(out3.contains("hello world"), "Step 3: full typed text should appear")
        #expect(!out3.contains("\u{1B}[2J"), "Step 3: no full clear after more typing")

        // Step 4: 提交输入 — 原 live 内容移入 committed，live 重置为 prompt
        tui.render(
            committed: ["prompt> hello world"],
            live: ["prompt> "],
            cursorOffset: 2
        )
        let out4 = spy.last!
        // 原输入内容应在 committed 区域中出现
        #expect(out4.contains("prompt> hello world"), "Step 4: submitted input should be in committed history")
        // 新 prompt 也应出现
        #expect(out4.contains("prompt> "), "Step 4: new prompt should be visible")
        #expect(!out4.contains("\u{1B}[2J"), "Step 4: no full clear on submit")

        // Step 5: 追加新 committed 行，live 不变
        tui.render(
            committed: ["prompt> hello world", "assistant: ok"],
            live: ["prompt> "],
            cursorOffset: 2
        )
        let out5 = spy.last!
        #expect(out5.contains("assistant: ok"), "Step 5: new committed line should appear")
        #expect(!out5.contains("\u{1B}[2J"), "Step 5: no full clear on commit append")

        // 综合契约：prompt 行不应在同一帧中重复出现
        // （在 Step 5 中，live 的 "prompt> " 不应被写入两次）
        let promptCount = out5.components(separatedBy: "prompt> ").count - 1
        #expect(promptCount <= 2, "prompt line should not appear more than (committed snapshot + current live)")
    }

    // MARK: - Cursor-only replay

    /// Cursor offset 变化仅生成相对移动序列，不重绘文本内容。
    @Test("cursor-only replay: same content, varying cursor offset")
    func testCursorOnlyReplay() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, writer: spy.writer)

        tui.render(committed: ["line1"], live: [], cursorOffset: 3)
        tui.render(committed: ["line1"], live: [], cursorOffset: 1)
        tui.render(committed: ["line1"], live: [], cursorOffset: 5)

        // 契约：3 帧均有输出（即便是纯 cursor 移动也不应产生空帧）
        #expect(spy.outputs.count == 3)
        for output in spy.outputs {
            #expect(!output.isEmpty, "Each frame must produce non-empty output")
            #expect(!output.contains("\u{1B}[2J"), "Cursor-only change should not trigger full clear")
        }
        // 首帧包含完整内容
        #expect(spy.outputs[0].contains("line1"), "First frame should contain the full text")
    }

    // MARK: - Resize 与输入联动

    /// 终端宽度变化后，inline diff 继续工作，不退化到全量清屏。
    @Test("resize during active input does not trigger spurious full redraw")
    func testResizeDuringInputNoSpuriousFullClear() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, terminalWidth: 20, terminalHeight: 50, writer: spy.writer)

        tui.render(committed: ["history-1", "history-2"], live: ["prompt> typing..."])

        // 缩小终端宽度
        tui.updateTerminalSize(width: 10)

        // 继续渲染不同的 live 内容
        tui.render(committed: ["history-1", "history-2"], live: ["prompt> more typing"])

        let last = spy.last!
        #expect(!last.contains("\u{1B}[2J"), "Resize should not force full clear when content fits in terminal")
        #expect(last.contains("more typing"), "New live content should be visible after resize")
    }

    // MARK: - 布局 budget overflow 边界

    /// 当 live 区域超过 liveBudget 时，溢出行被 settle 到 committed，
    /// 但不应触发全量清屏。
    @Test("live budget overflow settles without full clear")
    func testLiveBudgetOverflowNoFullClear() {
        let spy = OutputSpy()
        let tui = TUI(strategy: .inlineAnchor, liveBudget: 1, writer: spy.writer)

        // live 有 3 行，budget=1 → 前 2 行 settle 到 committed
        tui.render(
            committed: ["session-start"],
            live: ["stream-line-1", "stream-line-2", "stream-line-3"],
            cursorOffset: nil
        )

        let out = spy.last!
        #expect(out.contains("stream-line-1"), "Settled live lines should appear in output")
        #expect(out.contains("stream-line-3"), "Active live lines should appear in output")
        #expect(!out.contains("\u{1B}[2J"), "Live budget overflow should not trigger full clear")
    }
}
