import XCTest
@testable import ForgeLoopTUI

/// TASK-27 `preview-anchor-oracle`（二期前置闸门，只写测试不改库）。
///
/// 被测面：`TUI.render(committed: 非空, live: …)`（两区渲染）与帧间
/// `TUI.appendFrame` 的共存——TASK-28 计划把流式不稳定尾部放进 committed
/// 区原地 diff，行稳定后经 appendFrame 落卷轴、下一帧从 committed 区移除。
/// 现有用法全部是 `committed: []`，该组合从未走过。
///
/// 预言机：ScrollbackTerminal（真实终端语义：deferred wrap、宽字符、底部
/// 滚动入 scrollback，覆盖 TUI 输出的全部 ANSI 子集）。每个 TUI API 调用
/// 后，屏幕与 scrollback 必须与「期望内容物理换行后的尾部」逐行一致；
/// 不超屏的 in-place 帧不得引起 scrollback 增长；settled 行在完整视觉
/// 历史中恰好出现一次（无重复、无丢失）。
///
/// 结论口径：S1–S5 绿 = 闸门通过（erase→append→redraw 序列在各组合下
/// 锚定正确，无错位无重复）；S6 钉住直连序列（满帧后直接 appendFrame）
/// 的现状缺陷——错位下移 + 陈旧绘制补位/窗口上移一行——即
/// 「appendFrame 前必须先空渲染擦除 in-place 区」是 TASK-28 的硬约束。
final class CommittedPreviewAnchorTests: XCTestCase {

    // MARK: - Oracle harness

    @MainActor
    private final class OracleHarness {
        let width: Int
        let height: Int
        let vt: ScrollbackTerminal
        let tui: TUI
        /// 已落卷轴的行（appendFrame 累积）。
        private(set) var settled: [String] = []
        /// 位置式终端模型：终端不反滚动，擦除只清格子、追加只从残留区顶部
        /// 写入。terminalRows = settled 物理行 + regionRows（区域内容行，
        /// 含光标悬垂空行）+ residueBelow 空行；屏幕 = 尾部 height 行，
        /// 前缀 = scrollback。
        private var regionRows: [String] = []
        private var residueBelow = 0
        /// 探针模式：verify 只记录失配不断言（直连序列预期不合 oracle，
        /// 由调用侧的钉住断言承载结论）。
        var probing = false
        private(set) var stepCount = 0
        private(set) var mismatchedSteps: [String] = []

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            self.vt = ScrollbackTerminal(width: width, height: height)
            self.tui = TUI(
                isTTY: true,
                terminalWidth: width,
                terminalHeight: height,
                liveBudget: 4,
                liveBudgetMode: .physicalRows,
                cursorPositioningMode: .marker,
                terminal: vt
            )
        }

        private func physical(_ lines: [String]) -> [String] {
            lines.flatMap { Self.wrapToWidth(ansiStripped($0), width: width) }
        }

        /// 首帧前的历史预灌（空白初始终端上直接 appendFrame）。
        func prime(_ history: [String]) {
            guard !history.isEmpty else { return }
            tui.appendFrame(lines: history)
            settled += history
            regionRows = [""] // appendFrame 尾随换行的光标空行
            residueBelow = 0
            verify("prime history (\(history.count) lines)")
        }

        /// 普通 in-place 帧：committed 预览区 + live 区。
        func frame(committed: [String], live: [String], placement: CursorPlacement? = nil) {
            let newRegion = physical(committed + live)
                + (placement != nil || live.isEmpty ? [] : [""]) // 未锚定帧尾随换行悬垂
            residueBelow = max(0, regionRows.count + residueBelow - newRegion.count)
            regionRows = newRegion
            if let placement {
                tui.render(committed: committed, live: live, cursorPlacement: placement)
            } else {
                tui.render(committed: committed, live: live)
            }
            verify("frame committed=\(committed.count) live=\(live.count)")
        }

        /// 稳定沉降序列（MinimalAIApp 的库原生模式）：空渲染擦除 in-place
        /// 区 → appendFrame 落卷轴 → 下一帧重绘剩余预览。
        func settle(
            _ lines: [String],
            thenCommitted committed: [String],
            live: [String],
            placement: CursorPlacement? = nil
        ) {
            // 擦除：区域整体变为残留空行，光标停在区域顶（不占新行）。
            tui.render(committed: [], live: [], cursorOffset: 0)
            residueBelow += regionRows.count
            regionRows = []
            verify("erase before append (\(lines.count) lines)")

            // 追加：行 + 光标空行从残留区顶部消耗。
            tui.appendFrame(lines: lines)
            settled += lines
            let consumed = physical(lines).count + 1
            residueBelow = max(0, residueBelow - consumed)
            regionRows = [""]
            verify("appendFrame (\(lines.count) lines)")

            frame(committed: committed, live: live, placement: placement)
        }

        /// 直连探针用：渲染后按当前模型校验（不做 settled 记账）。
        func frameDirect(committed: [String], live: [String]) {
            let newRegion = physical(committed + live) + (live.isEmpty ? [] : [""])
            residueBelow = max(0, regionRows.count + residueBelow - newRegion.count)
            regionRows = newRegion
            tui.render(committed: committed, live: live)
            verify("direct frame committed=\(committed.count)")
        }

        /// 模型推导的完整视觉历史（settled + 区域 + 残留空行）。
        var modeledVisualHistory: [String] {
            physical(settled) + regionRows + Array(repeating: "", count: residueBelow)
        }

        /// 逐行校验：模型终端行尾部 height 行 = 屏幕，前缀 = scrollback。
        private func verify(_ step: String) {
            stepCount += 1
            let modeled = modeledVisualHistory
            let expectedScreen: [String]
            let expectedScrollback: [String]
            if modeled.count > height {
                expectedScrollback = modeled.dropLast(height).map(Self.trimTail)
                expectedScreen = modeled.suffix(height).map(Self.trimTail)
            } else {
                expectedScrollback = []
                expectedScreen = modeled.map(Self.trimTail)
                    + Array(repeating: "", count: height - modeled.count)
            }
            let actualScreen = vt.screenLines.map(Self.trimTail)
            let actualScrollback = vt.scrollback.map(Self.trimTail)

            var mismatch = actualScreen != expectedScreen || actualScrollback != expectedScrollback
            if mismatch {
                let detail = "step #\(stepCount) (\(step))"
                mismatchedSteps.append(detail)
                if mismatchedSteps.count <= 5 {
                    print("--- ORACLE MISMATCH \(detail) ---")
                    for row in 0..<height
                    where row < expectedScreen.count && actualScreen[row] != expectedScreen[row] {
                        print("  R[\(row)] E: \(expectedScreen[row])")
                        print("  R[\(row)] A: \(actualScreen[row])")
                    }
                    if actualScrollback != expectedScrollback {
                        print("  scrollback E(\(expectedScrollback.count)): \(expectedScrollback.suffix(3))")
                        print("  scrollback A(\(actualScrollback.count)): \(actualScrollback.suffix(3))")
                    }
                }
            }
            XCTAssertTrue(!mismatch || probing, "oracle mismatch at \(step)")
        }

        static func wrapToWidth(_ line: String, width: Int) -> [String] {
            var rows: [String] = []
            var current = ""
            var currentWidth = 0
            for char in line {
                let w = graphemeClusterWidth(char)
                if currentWidth + w > width {
                    rows.append(current)
                    current = String(char)
                    currentWidth = w
                } else {
                    current.append(char)
                    currentWidth += w
                }
            }
            rows.append(current)
            return rows
        }

        static func trimTail(_ s: String) -> String {
            var s = s
            while s.hasSuffix(" ") { s.removeLast() }
            return s
        }
    }

    // MARK: - S1: preview content mutation holds anchor (no appendFrame)

    @MainActor
    func testPreviewContentMutationHoldsAnchor() {
        let h = OracleHarness(width: 30, height: 12)
        h.prime(["h1", "h2"])

        let live = ["● streaming", "❯ _"]
        h.frame(committed: ["preview one", "preview two"], live: live)
        h.frame(committed: ["Preview ONE", "preview two"], live: live)               // 首行变
        h.frame(committed: ["Preview ONE", "preview TWO"], live: live)               // 尾行变
        h.frame(committed: ["Preview ONE", "middle edit", "preview TWO"], live: live) // 行数增
        h.frame(committed: ["Preview ONE", "middle EDIT", "preview TWO"], live: live) // 中行变
        h.frame(committed: ["Preview ONE", "middle EDIT"], live: live)               // 行数减
        h.frame(committed: ["Preview ONE", "middle EDIT"], live: ["● idle", "❯ _"])  // live 变
        h.frame(committed: ["Preview ONE", "middle EDIT"], live: ["● idle", "❯ _"])  // 无变化帧
        XCTAssertEqual(h.mismatchedSteps, [])
    }

    // MARK: - S2: preview row count grows and shrinks with live changes

    @MainActor
    func testPreviewRowCountGrowsAndShrinks() {
        let h = OracleHarness(width: 40, height: 14)
        h.prime(["intro line"])

        let live = ["status: ok", "❯ "]
        h.frame(committed: ["p1"], live: live)
        h.frame(committed: ["p1", "p2"], live: live)
        h.frame(committed: ["p1", "p2", "p3"], live: live)
        h.frame(committed: ["p1", "p2", "p3", "p4", "p5"], live: live)   // 跳增
        h.frame(committed: ["p1", "p2", "p3"], live: live)               // 跳减
        h.frame(committed: ["p1*"], live: live)                          // 内容变 + 减行
        h.frame(committed: ["p1*", "p2", "p3", "p4"], live: ["status: busy", "❯ "]) // 增行 + live 变
        h.frame(committed: [], live: ["status: busy", "❯ "])             // 预览区清空
        XCTAssertEqual(h.mismatchedSteps, [])
    }

    // MARK: - S3: exactly-full-screen in-place frames (TASK-21 hazard zone)

    @MainActor
    func testPreviewChangesOnExactlyFullScreenNeverScroll() {
        let height = 10
        let h = OracleHarness(width: 20, height: height)
        // 5 历史 + committed ≤ 3 + live 2 = 恰好 10 行占满整屏且不溢出。
        // 用锚定帧（cursorPlacement）消除尾随换行的合法滚动干扰，
        // 使「in-place 帧不得滚动」成为可断言的强不变量。
        h.prime((1...5).map { "hist \($0)" })
        let live = ["status", "❯ "]
        let placement = CursorPlacement(up: 0, offset: 0)
        h.frame(committed: ["c1", "c2"], live: live, placement: placement)
        let scrollbackBefore = h.vt.scrollback.count

        // 整屏帧上改 committed 首/尾行与行数——erase/重绘路径不得滚动。
        h.frame(committed: ["C1", "c2"], live: live, placement: placement)
        h.frame(committed: ["C1", "C2"], live: live, placement: placement)
        h.frame(committed: ["C1"], live: live, placement: placement)
        h.frame(committed: ["C1", "C1b", "C2"], live: live, placement: placement)
        h.frame(committed: ["C1", "C1b*", "C2"], live: live, placement: placement)

        XCTAssertEqual(
            h.vt.scrollback.count, scrollbackBefore,
            "不超屏的 in-place 帧不得把前缀行推入 scrollback"
        )
        XCTAssertEqual(h.mismatchedSteps, [])
    }

    // MARK: - S4: intermittent appendFrame (erase → append → redraw)

    @MainActor
    func testSettleSequenceKeepsAnchorAndNeverDuplicates() {
        let h = OracleHarness(width: 30, height: 10)
        // 历史 ≥ 屏高：擦除步的「屏幕 = 内容尾部」公式与 TASK-28 真实形态
        // （恒有满屏历史）一致。
        h.prime((1...12).map { "history \($0)" })
        let placement = CursorPlacement(up: 0, offset: 0)

        let live = ["● streaming", "❯ "]
        h.frame(committed: ["stable A", "stable B", "preview C"], live: live, placement: placement)
        h.frame(committed: ["stable A", "stable B", "preview C!"], live: live, placement: placement)

        // 稳定 A、B：空渲染 → appendFrame → 剩余预览重绘。
        h.settle(["stable A", "stable B"], thenCommitted: ["preview C!"], live: live, placement: placement)
        h.frame(committed: ["preview C!"], live: live, placement: placement)
        h.frame(committed: ["preview C!!"], live: live, placement: placement)

        // 稳定 C，预览区清空。
        h.settle(["preview C!!"], thenCommitted: [], live: ["● idle", "❯ "], placement: placement)

        // 终态视觉历史 = 12 历史 + 3 settled + 2 live（末帧锚定无悬垂、
        // 无残留）：settled 行恰好各一次，无重复无丢失。
        XCTAssertEqual(
            h.vt.visualHistory,
            ((1...12).map { "history \($0)" }
                + ["stable A", "stable B", "preview C!!", "● idle", "❯ "]).map(OracleHarness.trimTail)
        )
        XCTAssertEqual(h.mismatchedSteps, [])
    }

    // MARK: - S5: full streaming scenario (TASK-28 shape, placement included)

    @MainActor
    func testStreamingScenarioWithIntermittentSettlesAndPlacement() {
        let h = OracleHarness(width: 24, height: 10)
        h.prime((1...12).map { "prefill \($0)" }) // 超屏历史，scrollback 从 2 行起

        // 预览区逐帧增长/变化；每 6 帧稳定一次（除末行外全部 appendFrame）；
        // live 带 marker 光标定位（up>0 跨行时含 undo 与 appendFrame 的交互）。
        var preview = ["line 1"]
        var settledCount = 0
        for tick in 0..<24 {
            let live: [String]
            let placement: CursorPlacement
            if tick % 3 == 0 {
                live = ["● streaming", "❯ ", "second input row", "❯ "]
                placement = CursorPlacement(up: 1, offset: 0)
            } else {
                live = ["● streaming", "❯ "]
                placement = CursorPlacement(up: 0, offset: 0)
            }

            if tick % 6 == 5, preview.count > 1 {
                let toSettle = Array(preview.dropLast())
                preview = Array(preview.suffix(1))
                h.settle(toSettle, thenCommitted: preview, live: live, placement: placement)
                settledCount += toSettle.count
                continue
            }

            preview.append("partial \(tick)")
            if tick % 4 == 0 {
                preview[preview.count - 1] = "partial \(tick) rev"
            }
            h.frame(committed: preview, live: live, placement: placement)
        }

        XCTAssertGreaterThan(settledCount, 0, "场景自检：应有行被稳定沉降")
        XCTAssertEqual(h.mismatchedSteps, [])
        // 逐帧 oracle 已覆盖屏幕/scrollback；此处抽查 settled 行唯一性。
        let history = h.vt.visualHistory
        for line in history where line.hasPrefix("partial 4") {
            XCTAssertEqual(history.filter { $0 == line }.count, 1, "settled 行应恰好出现一次: \(line)")
        }
        XCTAssertEqual(
            history.map(OracleHarness.trimTail),
            h.modeledVisualHistory.map(OracleHarness.trimTail).suffix(history.count)
        )
    }

    // MARK: - S6: sequencing probe — appendFrame directly after a full frame

    /// 直连序列探针（TASK-28 若省略空渲染擦除就会走这条路）：满帧渲染后
    /// 光标在上一帧锚点，appendFrame 把行写在 live 之下且不改写 runtime
    /// retained 状态，下一帧 diff 的 rewind 数学假设光标仍在锚点。
    ///
    /// 闸门结论（2026-08-29，本探针实测钉住）：直连序列**不满足**严格
    /// oracle——
    /// · 小屏（不滚动）：下一帧重绘整体下移追加行数，追加行本身被擦除，
    ///   屏幕顶部由 committed 区的陈旧绘制"恰好"补位：视觉内容凑巧正确，
    ///   但机制是错位 + 巧合，settled 行不在 scrollback。
    /// · 满屏（追加触发滚动）：屏幕窗口比 oracle 期望整体上移一行（追加
    ///   尾随换行的合法滚动），settled 行虽不丢不重（恰好一次），但窗口
    ///   偏移永久残留。
    /// 因此「appendFrame 前必须先空渲染擦除 in-place 区」是 TASK-28 的
    /// 硬约束（S4/S5 证明该序列全绿）。以下断言钉住直连序列的**现状
    /// 行为**：若未来库改动使其变化，此测试会报警。
    @MainActor
    func testDirectAppendAfterFullFrameProbe() {
        // 小屏变体：区域未占满屏，追加不触发滚动。
        do {
            let h = OracleHarness(width: 30, height: 12)
            h.probing = true
            let live = ["status", "❯ "]
            h.frameDirect(committed: ["settled X", "preview 1", "preview 2"], live: live)
            h.tui.appendFrame(lines: ["settled X"]) // 中间态瞬态错位，不校验
            h.frameDirect(committed: ["preview 1", "preview 2"], live: live)
            XCTAssertFalse(h.mismatchedSteps.isEmpty, "直连序列应不合 oracle（闸门证据）")
            // 现状钉住：屏幕 = 陈旧补位的 settled X + 下移的重绘区（非 oracle
            // 期望的「settled 进 scrollback、区域顶格」）。
            XCTAssertEqual(
                h.vt.screenLines.map(OracleHarness.trimTail),
                    ["settled X", "preview 1", "preview 2", "status", "❯"]
                        + Array(repeating: "", count: 7)
            )
        }

        // 满屏变体：历史 7 + 区域 5 = 12 > 10，追加触发滚动。
        do {
            let h = OracleHarness(width: 20, height: 10)
            h.probing = true
            let live = ["status", "❯ "]
            h.prime((1...7).map { "hist \($0)" })
            h.frame(committed: ["settled Y", "p1", "p2"], live: live)
            h.tui.appendFrame(lines: ["settled Y"])
            h.frame(committed: ["p1", "p2"], live: live)
            // settled 行不丢不重……
            XCTAssertEqual(h.vt.visualHistory.filter { $0.contains("settled Y") }.count, 1)
            // ……但屏幕窗口比 oracle 期望（"hist 4" 起头）整体上移一行：
            // 追加尾随换行的滚动把 hist 4 也推入了 scrollback（现状钉住）。
            XCTAssertEqual(h.vt.screenLines.map(OracleHarness.trimTail).first, "hist 5")
            XCTAssertEqual(h.vt.scrollback.map(OracleHarness.trimTail), ["hist 1", "hist 2", "hist 3", "hist 4"])
        }
    }
}
