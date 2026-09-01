import XCTest
@testable import ForgeLoopTUI

/// TASK-37 回归：流式宽表在真实终端语义下，预览内容不得被 full-redraw
/// 回退路径推进 scrollback。
///
/// 场景钉自 dsh-tui 的真实终端症状（终端 118×12）：5 列宽表流式渲染时，
/// boxed 表格（20+ 物理行）+ status/input 超出终端高度，每个 chunk 触发
/// 一次 full-redraw 回退；旧实现（ESC[2J + 从 home 整帧重写）的超屏写入
/// 本身触发终端滚动，把预览帧内容逐 chunk 推进 scrollback —— raw 管道行
/// 与 boxed 表格头在 scrollback 里各重复十几份。
///
/// 帧模式与 MinimalAIApp / dsh-tui 逐语句同构（consume delta → 空渲染擦除
/// → appendFrame → committed 预览区重绘）。预言机 ScrollbackTerminal
/// （真实终端语义：底部滚动推入 scrollback）。断言三件套：
/// 1. 流式期间（未发生任何 settle）scrollback 必须保持为空——预览内容
///    一行都不许进卷轴；
/// 2. 终态视觉历史（scrollback + 屏幕）中 raw 管道行 `| --- |` 零出现；
/// 3. 唯一 sentinel "Kubernetes"（全表仅第 3 数据行首列一处）恰好一次。
final class StreamingTableScrollbackTests: XCTestCase {

    private let table = """
    | Tool | Category | Scope | Config File | Typical Use |
    | --- | --- | --- | --- | --- |
    | Docker | container runtime engine for images | single host or virtual machine | Dockerfile with layered build steps | build and run containers locally |
    | Docker Compose | multi-container orchestration command line tool | single host development machine | docker-compose.yml with services | local multi-service dev stacks |
    | Kubernetes | container orchestration platform for production | production grade multi node cluster | YAML manifests and Helm charts | production workload scheduling at scale |
    | kind | local k8s cluster running inside Docker containers | single machine integration testing | kind cluster config yaml file | CI pipelines and local cluster testing |
    | minikube | local single node cluster for development | single machine learning environment | minikube start command parameters | learning container orchestration basics |
    """

    @MainActor
    func testStreamingWideTableNeverDuplicatesIntoScrollback() {
        let width = 118
        let height = 12
        let vt = ScrollbackTerminal(width: width, height: height)
        let tui = TUI(
            isTTY: true,
            terminalWidth: width,
            terminalHeight: height,
            liveBudget: 4,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker,
            terminal: vt
        )
        let transcript = TranscriptRenderer()
        var appendState = StreamingTranscriptAppendState()
        let statusLines = ["● streaming"]
        let inputLines = ["❯ "]
        let placement = CursorPlacement(up: 0, offset: 0)
        /// 流式期间 scrollback 首次非空的 chunk 序号（nil = 从未污染）。
        var firstPollutedChunk: Int?

        // 与 MinimalAIApp.render() 逐语句同构：先沉降 newly-stable 行，
        // 再把 active block 内稳定前缀之外的未稳定尾部放进 committed 预览区。
        func renderFrame() {
            let delta = appendState.consume(
                transcript: transcript.transcriptLines,
                activeRange: transcript.activeStreamingRange,
                stableLineCount: transcript.activeStreamingStableLineCount,
                unsettledFrom: transcript.firstUnsettledLineIndex
            )
            if !delta.isEmpty {
                tui.render(committed: [], live: [], cursorOffset: 0)
                tui.appendFrame(lines: delta)
            }

            let preview: [String]
            if let range = transcript.activeStreamingRange {
                let lines = transcript.transcriptLines
                let unstableStart = min(
                    range.lowerBound + transcript.activeStreamingStableLineCount,
                    range.upperBound
                )
                preview = Array(lines[unstableStart..<range.upperBound])
            } else {
                preview = []
            }

            tui.render(
                committed: preview,
                live: statusLines + inputLines,
                cursorPlacement: placement
            )
        }

        transcript.applyCore(.blockStart(id: "assistant"))
        renderFrame()

        // 逐 7 字符流式喂入；期间 consume 不会吐出任何行（表格未稳定），
        // 因此任何 scrollback 增长都来自预览帧的滚动——即回退路径的污染。
        let chars = Array(table)
        var acc = ""
        var index = 0
        var chunk = 0
        while index < chars.count {
            let end = min(index + 7, chars.count)
            acc += String(chars[index..<end])
            transcript.applyCore(.blockUpdate(id: "assistant", lines: [acc]))
            renderFrame()
            if firstPollutedChunk == nil, !vt.scrollback.isEmpty {
                firstPollutedChunk = chunk
            }
            index = end
            chunk += 1
        }

        XCTAssertNil(
            firstPollutedChunk,
            "流式期间 scrollback 必须保持为空，首个污染 chunk: \(firstPollutedChunk.map(String.init) ?? "-")；"
                + "污染内容开头: \(vt.scrollback.prefix(3).joined(separator: " ⏎ "))"
        )

        transcript.applyCore(.blockEnd(id: "assistant", lines: [table], footer: nil))
        renderFrame()

        let history = vt.visualHistory
        // raw 管道行零出现：预览内容（无论 raw 还是 boxed）不得进 scrollback。
        XCTAssertFalse(
            history.contains(where: { $0.contains("| --- |") }),
            "raw 表格行不得进入 scrollback/屏幕终态；实际历史：\n\(history.joined(separator: "\n"))"
        )
        // 唯一 sentinel 恰好一次：换行段可能把词切到相邻物理行，先剥掉
        // 一切非 ASCII 字母再计数（同单元格的段在视觉历史中必然相邻）。
        let lettersOnly = history.joined().filter(\.isASCII).filter(\.isLetter)
        let occurrences = lettersOnly.components(separatedBy: "Kubernetes").count - 1
        XCTAssertEqual(
            occurrences, 1,
            "\"Kubernetes\" 在 scrollback+屏幕中应恰好出现一次，实际 \(occurrences) 次；"
                + "scrollback 行数 \(vt.scrollback.count)"
        )
    }

    /// erase→append→redraw 协议的角落形态：redraw 帧仍然超屏时，
    /// 尾窗回退必须从 appendFrame 刚写下的历史行之下开画——历史行留在
    /// 屏幕上（之上），不被覆盖、不重复、不进 scrollback（旧实现 ED2 清屏
    /// 把它们从屏幕抹掉，随后整帧重写把预览头部滚进 scrollback）。
    func testSettleWhilePreviewStillOversizedKeepsAppendedLines() {
        let width = 40
        let height = 8
        let vt = ScrollbackTerminal(width: width, height: height)
        let tui = TUI(
            isTTY: true,
            terminalWidth: width,
            terminalHeight: height,
            liveBudget: 4,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker,
            terminal: vt
        )
        let placement = CursorPlacement(up: 0, offset: 0)
        let preview = (1...10).map { "preview \($0)" }

        // 超屏预览帧（10 + 2 > 8）。
        tui.render(committed: preview, live: ["status", "❯ "], cursorPlacement: placement)

        // settle：擦除 → 追加 2 行历史 → 重绘仍超屏的预览。
        tui.render(committed: [], live: [], cursorOffset: 0)
        tui.appendFrame(lines: ["settled-1", "settled-2"])
        tui.render(committed: preview, live: ["status", "❯ "], cursorPlacement: placement)

        // 无滚动发生：scrollback 为空；追加的历史行占据屏幕顶部。
        XCTAssertEqual(vt.scrollback, [], "redraw 超屏也不得滚动：\(vt.scrollback)")
        let screen = vt.screenLines
        XCTAssertEqual(screen[0], "settled-1")
        XCTAssertEqual(screen[1], "settled-2")
        // 尾窗画在追加区之下：窗口底部是 live 区。
        XCTAssertEqual(screen[height - 2], "status")
        XCTAssertEqual(screen[height - 1].hasPrefix("❯"), true)
        // 历史行在完整视觉历史中恰好一次。
        let history = vt.visualHistory
        XCTAssertEqual(history.filter { $0 == "settled-1" }.count, 1)
        XCTAssertEqual(history.filter { $0 == "settled-2" }.count, 1)
    }
}
