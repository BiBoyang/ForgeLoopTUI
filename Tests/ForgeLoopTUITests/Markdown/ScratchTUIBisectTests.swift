import XCTest
@testable import ForgeLoopTUI

/// TASK-21 回归测试终端模型：真实终端语义（deferred wrap、显示宽度换行、
/// 底部滚动推入 scrollback），覆盖 TUI 输出所用的全部 ANSI 子集：
/// ESC[2J/0J/H, A/B/C/D/G, 2K, nL, nM, \r, \n。
final class ScrollbackTerminal: Terminal, @unchecked Sendable {
    let isTTY: Bool = true
    var capability: TerminalCapability { .truecolor }

    let width: Int
    let height: Int
    private(set) var scrollback: [String] = []
    private var grid: [[Character]]
    private var contMask: [[Bool]]
    private var row = 0
    private var col = 0
    private var pendingWrap = false
    private var parser = ANSIParser()
    /// 每帧 TUI 输出原文（write 调用之间以调用次数分帧不现实，按 ESC[2J 分割
    /// 无意义；直接顺序记录全部 write 文本，由测试按帧边界切片）。
    private(set) var writeLog: [String] = []
    private(set) var writeMarks: [Int] = []

    /// 在每次 TUI render 前调用，标记当前 writeLog 位置为帧边界。
    func markFrame() {
        writeMarks.append(writeLog.count)
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.grid = Array(repeating: Array(repeating: " ", count: width), count: height)
        self.contMask = Array(repeating: Array(repeating: false, count: width), count: height)
    }

    func write(_ text: String) {
        writeLog.append(text)
        for scalar in text.unicodeScalars {
            parser.feed(scalar) { [self] event in
                switch event {
                case .text(let char):
                    writeCharacter(char)
                case .csi(let params, _, let command):
                    handleCSI(params: params, command: command)
                }
            }
        }
    }

    private func writeCharacter(_ char: Character) {
        if char == "\r" {
            row = min(row, height - 1)
            col = 0
            pendingWrap = false
            return
        }
        if char == "\n" {
            pendingWrap = false
            moveDown()
            return
        }
        if pendingWrap {
            pendingWrap = false
            col = 0
            moveDown()
        }
        let w = graphemeClusterWidth(char)
        putCluster(char, width: max(1, w))
    }

    private func putCluster(_ char: Character, width cellWidth: Int) {
        // cluster 宽度 > 1 时占 col 与 col+1（真实终端语义）；占不下的尾格
        // 按终端惯例跳到下一行。continuation cell 打掩码，squeeze 时不输出。
        if col + cellWidth > width {
            col = 0
            moveDown()
        }
        grid[row][col] = char
        contMask[row][col] = false
        for pad in 1..<cellWidth where col + pad < width {
            grid[row][col + pad] = " "
            contMask[row][col + pad] = true
        }
        col += cellWidth
        if col >= width {
            col = width - 1
            pendingWrap = true
        }
    }

    private func moveDown() {
        row += 1
        if row >= height {
            scrollback.append(squeezedRow(0))
            grid.removeFirst()
            contMask.removeFirst()
            grid.append(Array(repeating: " ", count: width))
            contMask.append(Array(repeating: false, count: width))
            row = height - 1
        }
    }

    private func handleCSI(params: [Int], command: Character) {
        let n = params.first ?? 1
        switch command {
        case "J":
            if params.first == 2 {
                for r in 0..<height {
                    grid[r] = Array(repeating: " ", count: width)
                    contMask[r] = Array(repeating: false, count: width)
                }
            } else if params.first == 0 {
                // ESC[0J：光标（含）到屏尾擦除，光标不动，无滚动。
                for c in col..<width {
                    grid[row][c] = " "
                    contMask[row][c] = false
                }
                for r in (row + 1)..<height {
                    grid[r] = Array(repeating: " ", count: width)
                    contMask[r] = Array(repeating: false, count: width)
                }
            }
        case "H":
            row = max(0, min(height - 1, (params.count > 0 ? params[0] : 1) - 1))
            col = max(0, min(width - 1, (params.count > 1 ? params[1] : 1) - 1))
            pendingWrap = false
        case "A":
            row = max(0, row - max(1, n)); pendingWrap = false
        case "B":
            row = min(height - 1, row + max(1, n)); pendingWrap = false
        case "C":
            col = min(width - 1, col + max(1, n)); pendingWrap = false
        case "D":
            col = max(0, col - max(1, n)); pendingWrap = false
        case "G":
            col = max(0, min(width - 1, max(1, n) - 1)); pendingWrap = false
        case "K":
            if params.first == 2 {
                grid[row] = Array(repeating: " ", count: width)
                contMask[row] = Array(repeating: false, count: width)
                pendingWrap = false
            }
        case "L":
            let count = max(1, n)
            for _ in 0..<count {
                grid.removeLast()
                contMask.removeLast()
                grid.insert(Array(repeating: " ", count: width), at: row)
                contMask.insert(Array(repeating: false, count: width), at: row)
            }
        case "M":
            let count = max(1, n)
            for _ in 0..<count {
                grid.remove(at: row)
                contMask.remove(at: row)
                grid.append(Array(repeating: " ", count: width))
                contMask.append(Array(repeating: false, count: width))
            }
        default:
            break
        }
    }

    private func squeezedRow(_ r: Int) -> String {
        var s = ""
        for c in 0..<width where !contMask[r][c] {
            s.append(grid[r][c])
        }
        return s
    }

    /// 当前屏幕文本行（squeeze 宽字符 continuation cell，去尾部空格）。
    var screenLines: [String] {
        (0..<height).map { squeezedRow($0) }.map { trim($0) }
    }

    /// scrollback + 屏幕（视觉历史）。
    var visualHistory: [String] {
        scrollback.map { trim($0) } + screenLines
    }

    private func trim(_ s: String) -> String {
        var s = s
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
}

/// TASK-21 三路二分探针（调查用）：
/// (a) 静态一次性 blockEnd —— 已由 ScratchProbe 覆盖：正确。
/// (b) 流式 + liveBudget 0 vs (c) 流式 + liveBudget 4/.physicalRows/.marker：
///     逐帧走 MinimalAIApp 同构管线（TranscriptRenderer → ScreenLayoutRenderer
///     pinned 裁剪 → TUI.render(committed:live:cursorPlacement:)），
///     逐帧校验屏幕一致性，并比对 (b)/(c) 的 TUI 输出字节流。
final class ScratchTUIBisectTests: XCTestCase {
    @MainActor
    private func runReplay(liveBudget: Int) throws -> (
        committed: [[String]],
        live: [[String]],
        frameBytes: [String],
        mismatches: [Int],
        scrollbackCounts: [Int],
        finalHistory: [String]
    ) {
        let width = 200
        let height = 24
        let vt = ScrollbackTerminal(width: width, height: height)
        let tui = TUI(
            isTTY: true,
            terminalWidth: width,
            terminalHeight: height,
            liveBudget: liveBudget,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker,
            terminal: vt
        )
        let layoutRenderer = ScreenLayoutRenderer()
        let transcript = TranscriptRenderer()

        let statusLines = ["● streaming", "pending tools: 0"]
        let inputLines = ["❯ "]
        let placement = CursorPlacement(up: 0, offset: 0)

        let md = StreamingGarbleFixture.markdown
        let chars = Array(md)
        var committedFrames: [[String]] = []
        var liveFrames: [[String]] = []
        var frameBytes: [String] = []
        var mismatches: [Int] = []
        var scrollbackCounts: [Int] = []

        func renderFrame() {
            let layout = ScreenLayout(
                header: [],
                transcript: transcript.transcriptLines,
                queue: [],
                status: statusLines,
                input: inputLines,
                pinnedTranscriptRange: transcript.preferredPinnedRange
            )
            let config = ScreenLayoutConfig(terminalHeight: height, terminalWidth: width, showHeader: false)
            let frame = layoutRenderer.render(layout: layout, config: config, cursorPlacement: placement)
            vt.markFrame()
            let markIndex = vt.writeMarks.count - 1
            tui.render(frame: frame)

            var physical: [String] = []
            for line in frame.committed + frame.live {
                // 终端按可见列自动换行（ANSI 序列不占格）：oracle 换行前
                // 先剥离转义序列，否则换行位置与真实终端不一致。
                physical.append(contentsOf: wrapToWidth(ansiStripped(line), width: width))
            }
            let expected = physical.suffix(height)
            let actual = vt.screenLines
            // 帧内容从屏幕顶部开始写；不足整屏时其余行补空行。
            let paddedExpected = expected.map { trimTail($0) }
                + Array(repeating: "", count: height - expected.count)
            let trimmedActual = actual.map { trimTail($0) }
            if paddedExpected != trimmedActual {
                mismatches.append(frames_count(committedFrames))
                if mismatches.count <= 3 {
                    print("--- MISMATCH frame #\(frames_count(committedFrames)) ---")
                    for i in 0..<height where paddedExpected[i] != trimmedActual[i] {
                        print("  R[\(i)] E: \(paddedExpected[i])")
                        print("  R[\(i)] A: \(trimmedActual[i])")
                    }
                }
            }
            committedFrames.append(frame.committed)
            liveFrames.append(frame.live)
            let start = vt.writeMarks[markIndex]
            let bytes = vt.writeLog[start...].joined()
            frameBytes.append(bytes)
            scrollbackCounts.append(vt.scrollback.count)
        }

        transcript.applyCore(.insert(lines: ["❯ 我现在在测试 markdown 格式,请你尽量输出多一些复杂的格式带模拟数据, 我主要用来测"]))
        renderFrame()

        transcript.applyCore(.blockStart(id: "assistant"))
        renderFrame()

        var acc = ""
        var i = 0
        while i < chars.count {
            let end = min(i + 1, chars.count)
            acc += String(chars[i..<end])
            transcript.applyCore(.blockUpdate(id: "assistant", lines: [acc]))
            renderFrame()
            i = end
        }

        transcript.applyCore(.blockEnd(id: "assistant", lines: [md], footer: nil))
        renderFrame()

        return (committedFrames, liveFrames, frameBytes, mismatches, scrollbackCounts, vt.visualHistory)
    }

    private func frames_count(_ frames: [[String]]) -> Int { frames.count }

    private func wrapToWidth(_ line: String, width: Int) -> [String] {
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

    private func trimTail(_ s: String) -> String {
        var s = s
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }

    /// (b) vs (c)：关/开 liveBudget 的逐帧 frame 序列是否一致。
    @MainActor
    func testBisectBudgetOnOffFramesIdentical() throws {
        let b = try runReplay(liveBudget: 0)
        let c = try runReplay(liveBudget: 4)
        let bFrames = zip(b.committed, b.live).map { $0 + $1 }
        let cFrames = zip(c.committed, c.live).map { $0 + $1 }
        XCTAssertEqual(bFrames.count, cFrames.count)
        var firstFrameDiff: Int?
        for i in 0..<min(bFrames.count, cFrames.count) where bFrames[i] != cFrames[i] {
            firstFrameDiff = i
            break
        }
        print("=== frames: b=\(bFrames.count) c=\(cFrames.count) firstDiff=\(firstFrameDiff.map(String.init) ?? "none") ===")
        XCTAssertEqual(bFrames, cFrames, "liveBudget on/off 改变了 frame 内容序列")
    }

    /// 字节级分析 + 假设验证：erase 循环最后一个 `\n` 触发终端滚动，
    /// 导致 prefix 行被推入 scrollback（丢行）且 `ESC[prevTailRows A`
    /// 重定位少算一次滚动（重绘整体上移一行）。
    @MainActor
    func testBisectDumpMismatchBytes() throws {
        let r = try runReplay(liveBudget: 0)
        guard let first = r.mismatches.first else {
            print("=== no mismatch — TUI 层自洽 ===")
            return
        }
        print("=== first mismatch frame #\(first) of \(r.frameBytes.count), total mismatched: \(r.mismatches.count) ===")

        // 逐帧 scrollback 增长：本测试内容恰好占满整屏（24 行 × 单物理行），
        // 内容写入本身不触发滚动；任何 scrollback 增长都来自 erase 循环的尾 `\n`。
        var growths: [(frame: Int, delta: Int)] = []
        for f in r.scrollbackCounts.indices {
            let prev = f == 0 ? 0 : r.scrollbackCounts[f - 1]
            if r.scrollbackCounts[f] > prev {
                growths.append((f, r.scrollbackCounts[f] - prev))
            }
        }
        let firstGrowth = growths.first.map { String($0.frame) } ?? "none"
        let lastGrowth = growths.last.map { String($0.frame) } ?? "none"
        print("=== scrollback growth frames: \(growths.count), first at #\(firstGrowth), last at #\(lastGrowth) ===")
        if let g = growths.first {
            print("=== scrollback delta at #\(g.frame): +\(g.delta) (before: \(g.frame == 0 ? 0 : r.scrollbackCounts[g.frame - 1]), after: \(r.scrollbackCounts[g.frame])) ===")
        }

        // 序列计数：确认 frame #first 的 rewind / erase / reposition 数目。
        func countOccurrences(of needle: String, in haystack: String) -> Int {
            var count = 0
            var range = haystack.startIndex..<haystack.endIndex
            while let found = haystack.range(of: needle, range: range) {
                count += 1
                range = found.upperBound..<haystack.endIndex
            }
            return count
        }
        for f in [max(0, first - 1), first] {
            let bytes = r.frameBytes[f]
            let erases = countOccurrences(of: "\u{1B}[2K", in: bytes)
            let ups = bytes.ranges(of: "\u{1B}[").compactMap { rng -> Int? in
                let rest = bytes[rng.upperBound...]
                guard let aIdx = rest.firstIndex(of: "A") else { return nil }
                guard let n = Int(rest[rest.startIndex..<aIdx]) else { return nil }
                // 确认 A 与 [ 之间只有数字
                let between = rest[rest.startIndex..<aIdx]
                if between.allSatisfy(\.isNumber) { return n }
                return nil
            }
            print("=== frame #\(f): erases=\(erases) upMoves=\(ups) scrollback=\(r.scrollbackCounts[f]) ===")
        }
        // 假设断言：失配开始前后 scrollback 必然已在增长（erase 尾 `\n` 滚动）。
        // #90 startLineIndex=0：滚动吃掉的是已擦除的空行，屏幕侥幸正确但
        // scrollback 已被污染；#91 startLineIndex=1：滚动吃掉未重写的 prefix
        // 行 + 重定位少算一次滚动 → 首个可见失配。
        if let g = growths.first {
            XCTAssertLessThanOrEqual(g.frame, first, "首个 scrollback 增长帧应不晚于首个失配帧（erase 循环滚动假设）")
            XCTAssertEqual(r.scrollbackCounts[first], r.scrollbackCounts[first - 1] + 1, "失配帧本身应触发一次滚动")
        }
    }

    /// 最小确定性复现（RC-TUI，脱离 fixture）：两帧渲染即触发
    /// erase 循环滚动 → prefix 行丢失 + 重绘整体上移。
    ///
    /// 条件：帧占满整屏（prevTotalRows == height）且 startLineIndex > 0
    /// （firstDiff >= 2）。6 行终端、committed 4 行 + live 2 行：
    /// 帧 A = a,b,c,d + x,y；帧 B 只改 line 2（c→C）→ firstDiff=2 →
    /// startLineIndex=1 → erase rows 1..5 的尾 `\n` 滚动 → "a" 被推入
    /// scrollback 丢失，帧 B 的 b,C,d,x,y 上移一行绘制。
    @MainActor
    func testMinimalEraseLoopScrollShift() throws {
        let width = 20
        let height = 6
        let vt = ScrollbackTerminal(width: width, height: height)
        let tui = TUI(
            isTTY: true,
            terminalWidth: width,
            terminalHeight: height,
            liveBudget: 0,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker,
            terminal: vt
        )
        let placement = CursorPlacement(up: 0, offset: 0)

        tui.render(committed: ["a", "b", "c", "d"], live: ["x", "y"], cursorPlacement: placement)
        XCTAssertEqual(vt.screenLines, ["a", "b", "c", "d", "x", "y"], "帧 A 应正确占满整屏")
        XCTAssertEqual(vt.scrollback.count, 0, "帧 A 内容写入不应滚动")

        tui.render(committed: ["a", "b", "C", "d"], live: ["x", "y"], cursorPlacement: placement)

        print("=== minimal repro screen after frame B: \(vt.screenLines) ===")
        print("=== minimal repro scrollback: \(vt.scrollback) ===")
        // 失败断言即缺陷证据：正确终态应为 a,b,C,d,x,y 且 scrollback 为空。
        XCTAssertEqual(vt.scrollback, [], "prefix 行 'a' 不应被 erase 循环推入 scrollback")
        XCTAssertEqual(vt.screenLines, ["a", "b", "C", "d", "x", "y"], "帧 B 重绘不应整体上移")
    }
}
