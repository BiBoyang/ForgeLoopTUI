import Foundation

public protocol MarkdownEngine: AnyObject {
    func reset()
    func render(text: String, isFinal: Bool) -> [String]

    /// Number of leading lines of the most recent `render` output that are
    /// guaranteed immutable: as long as later `render` calls only append text
    /// to the buffer, those lines reappear unchanged (same content, same
    /// positions) at the start of every future output. Append-only consumers
    /// (e.g. `StreamingTranscriptAppendState`) may commit exactly this prefix
    /// to scrollback; anything past it may still be re-rendered.
    ///
    /// The count must never rewind while the buffer only grows. After a
    /// `reset()` it restarts from zero for the next buffer.
    var stableRenderedLineCount: Int { get }
}

extension MarkdownEngine {
    /// Default for engines that do not track a stable prefix: nothing is
    /// certified immutable, so append-only consumers defer to the final
    /// (non-streaming) flush. Rendering itself is unaffected.
    public var stableRenderedLineCount: Int { 0 }
}

public final class PlainTextMarkdownEngine: MarkdownEngine {
    private var lastStableLineCount = 0

    public init() {}

    public func reset() {
        lastStableLineCount = 0
    }

    public func render(text: String, isFinal: Bool) -> [String] {
        guard !text.isEmpty else {
            lastStableLineCount = 0
            return []
        }
        // Every `\n`-terminated line is immutable; only the trailing partial
        // line (or the empty next-line prefix after a trailing newline) may
        // still change.
        lastStableLineCount = text.reduce(into: 0) { $0 += $1 == "\n" ? 1 : 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public var stableRenderedLineCount: Int { lastStableLineCount }
}

public final class StreamingMarkdownEngine: MarkdownEngine {
    private var stableSource = ""
    private var stableRendered: [String] = []
    /// 稳定渲染当前是否缺少尾边界空行（见 render 内的 drop/补回逻辑）。
    private var stableTrailingBlankDropped = false
    private let thematicBreak = String(repeating: "─", count: 24)
    public let options: MarkdownRenderOptions

    /// 稳定前缀缓存上限（字符数）。超出后触发 reset，丢弃旧缓存以避免长会话
    /// 中 stableSource/stableRendered 无界增长。reset 后内容仍正确渲染，
    /// 仅丢失稳定前缀的增量优化（下一次渲染会重建缓存）。
    private let maxStableSourceChars = 65_536

    public init(options: MarkdownRenderOptions = .init()) {
        self.options = options
    }

    private var theme: MarkdownTheme { options.theme }

    /// Lines rendered from `stableSource` are final by construction: the
    /// stable prefix only advances at source line boundaries, and constructs
    /// that would re-render earlier lines as they grow (streaming tables,
    /// unclosed code fences) are held back in the unstable region by the
    /// retreat logic in `stableAdvance`.
    public var stableRenderedLineCount: Int { stableRendered.count }

    public func reset() {
        stableSource = ""
        stableRendered = []
        stableTrailingBlankDropped = false
    }

    public func render(text: String, isFinal: Bool) -> [String] {
        guard !text.isEmpty else {
            reset()
            return []
        }

        if !stableSource.isEmpty, !text.hasPrefix(stableSource) {
            reset()
        }

        // Cap stable prefix growth — reset if exceeded to bound memory in long sessions.
        if stableSource.count > maxStableSourceChars {
            reset()
        }

        let suffix = String(text.dropFirst(stableSource.count))
        let advance = stableAdvance(in: suffix, isFinal: isFinal)
        if advance > 0 {
            let stableDelta = String(suffix.prefix(advance))
            stableSource += stableDelta
            var deltaRendered = renderFully(text: stableDelta, isFinal: true)
            // stableSource 恒以行边界（\n）结尾；renderFully 拆行产生的尾随
            // "" 是「边界之后的下一行前缀」，属于 unstable 区而非稳定内容。
            // 无条件丢弃，维持不变量：
            //   stableRendered ≡ renderFully(stableSource) − 尾边界 ""
            // 此前仅在 unstable 非空时丢弃：快照恰好停在行边界（unstable 为
            // 空）时尾 "" 被永久固化，每个被晋升的行边界多出一条空行。
            // fence 内的尾行渲染为 "│"（last != ""），不触发丢弃。
            if stableDelta.hasSuffix("\n"), deltaRendered.last == "" {
                deltaRendered.removeLast()
                stableTrailingBlankDropped = true
            } else {
                stableTrailingBlankDropped = false
            }
            stableRendered += deltaRendered
        }

        let unstable = String(text.dropFirst(stableSource.count))
        let unstableRendered = renderFully(text: unstable, isFinal: isFinal)
        var result = stableRendered + unstableRendered
        // isFinal 时补回全文尾边界的空行，使流式终态与一次性静态渲染逐行
        // 一致（静态路径走同一 drop/补回逻辑，两条路径保持对称）。
        // 标志为持久状态：终帧可能无新晋升（advance == 0，快照在终帧前已
        // 停在尾边界），此时尾界 "" 是此前帧丢弃的，仍需补回。
        if isFinal, stableTrailingBlankDropped, unstable.isEmpty {
            result.append("")
        }
        return result
    }

    private func stableAdvance(in text: String, isFinal: Bool) -> Int {
        guard !text.isEmpty else { return 0 }
        if isFinal { return text.count }
        guard let lastNewline = text.lastIndex(of: "\n") else { return 0 }
        let candidateEnd = text.index(after: lastNewline)
        let candidateText = String(text[..<candidateEnd])
        let remainder = String(text[candidateEnd...])

        let lines = candidateText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // fence retreat 必须先于表格 retreat：未闭合 fence 之后的所有行按
        // renderFully 的语义都是 fence 内容，其中的表格状行不是真正的表格。
        if let retreat = retreatToAvoidSplittingUnclosedCodeFence(lines: lines) {
            return retreat
        }

        if let retreat = retreatToAvoidSplittingUnclosedLatexBlock(lines: lines) {
            return retreat
        }

        if let retreat = retreatToAvoidSplittingUnclosedHTMLTag(lines: lines) {
            return retreat
        }

        if let retreat = retreatToAvoidSplittingTrailingStreamingTable(lines: lines, remainder: remainder) {
            return retreat
        }

        if lines.count >= 3 {
            let trailingEmpty = lines.last == ""
            let dividerIndex = trailingEmpty ? lines.count - 2 : lines.count - 1
            let headerIndex = dividerIndex - 1
            if headerIndex >= 0,
               parseTableCells(lines[headerIndex]) != nil,
               parseDividerCells(lines[dividerIndex]) != nil
            {
                let prefixLines = lines.prefix(headerIndex)
                let prefixText = prefixLines.joined(separator: "\n")
                var retreat = prefixText.count
                if headerIndex > 0 {
                    retreat += 1
                }
                return retreat
            }
        }

        // 表头前瞻（E2-a）：candidate 以 \n 结尾故 lines.last 恒为 ""，最后
        // 一个实际行是倒数第二行。若该行呈表头形状（有未转义管道），回退到
        // 它之前不晋升——表头与 divider 必须同时进入稳定前缀才能整体按表格
        // 渲染；只晋升表头会被 renderFully 按普通文本永久冻结，随后到达的
        // divider 再也无法与之成表（终态整表降级为裸管道文本）。
        // fence 内的管道行不会到达这里：fence retreat 已在前面拦截。
        // 误伤面：普通文本行含管道时保守回退一行，瞬态多渲染一次，正确性
        // 无损；isFinal 时本函数直接返回全文，不受影响。
        if lines.count >= 2, parseTableCells(lines[lines.count - 2]) != nil {
            let headerIndex = lines.count - 2
            let prefixLines = lines.prefix(headerIndex)
            let prefixText = prefixLines.joined(separator: "\n")
            var retreat = prefixText.count
            if headerIndex > 0 {
                retreat += 1
            }
            return retreat
        }

        return text.distance(from: text.startIndex, to: candidateEnd)
    }

    private func retreatToAvoidSplittingTrailingStreamingTable(
        lines: [String],
        remainder: String
    ) -> Int? {
        // 快照停在行边界（remainder 为空）时同样参与检测：数据行陆续到达
        // 期间，candidate 尾部是「header + divider + 已到数据行」的表格
        // 前缀，任何中段都不得晋升——renderFully 对没有数据行的表头段
        // 会降级为普通文本，一旦晋升整表无法再成。此前 remainder 为空
        // 直接返回 nil，快照停在数据行边界时表头段被晋升（终态降级）。
        // remainder 非空时维持原约束：流正处于表格行（| 开头）中才 retreat。
        if !remainder.isEmpty {
            let trimmedRemainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRemainder.isEmpty, trimmedRemainder.hasPrefix("|") else { return nil }
        }

        let trailingEmpty = lines.last == ""
        let end = trailingEmpty ? lines.count - 2 : lines.count - 1
        guard end >= 2 else { return nil }

        for start in stride(from: end - 2, through: 0, by: -1) {
            guard let headerCells = parseTableCells(lines[start]),
                  let divider = parseDividerCells(lines[start + 1]),
                  divider.count == headerCells.count else {
                continue
            }

            var allRowsMatch = true
            for rowIndex in (start + 2)...end {
                guard let rowCells = parseTableCells(lines[rowIndex]),
                      rowCells.count == headerCells.count else {
                    allRowsMatch = false
                    break
                }
            }

            if allRowsMatch {
                let prefixLines = lines.prefix(start)
                let prefixText = prefixLines.joined(separator: "\n")
                var retreat = prefixText.count
                if start > 0 {
                    retreat += 1
                }
                return retreat
            }
        }

        return nil
    }

    /// 与表格 retreat 同构的代码块防御：若 candidate 前缀以未闭合的 code fence
    /// 结尾（fence 分隔符出现奇数次），回退到该 fence 起始行之前——宁可稳定前缀
    /// 更短、多渲染，也不把稳定边界切在未闭合代码块中间。fence 判定复用
    /// `isCodeFenceDelimiter`，与 `renderFully` 的 inCodeFence 切换语义保持一致
    /// （不检查开/闭合 fence 的长度匹配）。
    private func retreatToAvoidSplittingUnclosedCodeFence(lines: [String]) -> Int? {
        var inCodeFence = false
        var openingFenceIndex: Int?
        for (index, line) in lines.enumerated() where isCodeFenceDelimiter(line) {
            inCodeFence.toggle()
            openingFenceIndex = inCodeFence ? index : nil
        }
        guard inCodeFence, let fenceStart = openingFenceIndex else { return nil }

        let prefixLines = lines.prefix(fenceStart)
        let prefixText = prefixLines.joined(separator: "\n")
        var retreat = prefixText.count
        if fenceStart > 0 {
            retreat += 1
        }
        return retreat
    }

    /// 与 fence retreat 同构的 `$$` 显示公式块防御：candidate 前缀若终止在
    /// 未闭合的 display-math 块内，回退到块起始行（开 `$$`）之前——块必须
    /// 整体进入同一次渲染才能整体近似（或整体 raw），fence 内的 `$$` 是
    /// fence 内容，不参与判定（fence retreat 已先行拦截）。
    private func retreatToAvoidSplittingUnclosedLatexBlock(lines: [String]) -> Int? {
        var inCodeFence = false
        var inLatexBlock = false
        var openingLineIndex: Int?
        for (index, line) in lines.enumerated() {
            if isCodeFenceDelimiter(line) {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { continue }
            if inLatexBlock {
                if line.trimmingCharacters(in: .whitespaces) == "$$" {
                    inLatexBlock = false
                    openingLineIndex = nil
                }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "$$" {
                inLatexBlock = true
                openingLineIndex = index
            }
        }
        guard inLatexBlock, let openingLine = openingLineIndex else { return nil }

        let prefixLines = lines.prefix(openingLine)
        let prefixText = prefixLines.joined(separator: "\n")
        var retreat = prefixText.count
        if openingLine > 0 {
            retreat += 1
        }
        return retreat
    }

    /// 与 fence retreat 同构的多行 HTML 标签防御：candidate 前缀若终止在
    /// 一个已打开未闭合的 HTML 标签内（属性串跨行，如多行 `<img … />`），
    /// 回退到该标签起始行之前——多行标签必须整体进入同一次渲染，属性串
    /// 才不会泄漏。fence 内的行不参与判定（fence retreat 已先行拦截）。
    private func retreatToAvoidSplittingUnclosedHTMLTag(lines: [String]) -> Int? {
        var inCodeFence = false
        var pendingTag = false
        var openingLineIndex: Int?
        for (index, line) in lines.enumerated() {
            if pendingTag {
                if line.contains(">") {
                    pendingTag = false
                    openingLineIndex = nil
                    // 同一行闭合后可能又开启新的未闭合标签（`… /> <div`）。
                    if HTMLDegrader.endsInsideUnclosedTag(line) {
                        pendingTag = true
                        openingLineIndex = index
                    }
                }
                continue
            }
            if isCodeFenceDelimiter(line) {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { continue }
            if HTMLDegrader.endsInsideUnclosedTag(line) {
                pendingTag = true
                openingLineIndex = index
            }
        }
        guard pendingTag, let openingLine = openingLineIndex else { return nil }

        let prefixLines = lines.prefix(openingLine)
        let prefixText = prefixLines.joined(separator: "\n")
        var retreat = prefixText.count
        if openingLine > 0 {
            retreat += 1
        }
        return retreat
    }

    private func renderFully(text: String, isFinal: Bool) -> [String] {
        guard !text.isEmpty else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let endsWithNewline = text.hasSuffix("\n")
        var rendered: [String] = []
        var index = 0
        var inCodeFence = false
        // 当前 fence 的高亮器：fence 开始按 info string 创建、闭合时释放。
        // stableAdvance 的 fence retreat 保证 fence 永不跨 render 批次被切开
        // （未闭合 fence 整体留在 unstable 区、每趟从其首行重渲），因此跨行
        // 高亮状态只是本趟渲染的局部变量，渲染仍是输入文本的确定函数。
        var fenceHighlighter: FenceHighlighter?
        // Multi-line HTML tag state: lines between an unclosed `<tag …` and
        // its closing `>` are attribute text (dropped). `stableAdvance`
        // retreats so a multi-line tag always renders within one pass; if it
        // never closes inside this pass, the raw lines are flushed unchanged
        // (no data loss).
        var continuingUnclosedTag = false
        var pendingRawLines: [String] = []
        var pendingSegments: [String] = []
        // `$$` display-math block state: lines between the delimiters are
        // approximated (or kept raw for `\begin{…}` environments).
        // `stableAdvance` retreats while a block is unclosed; a block that
        // never closes inside this pass flushes its raw lines (no loss).
        var inLatexBlock = false
        var latexBlockLines: [String] = []
        while index < lines.count {
            if inLatexBlock {
                if lines[index].trimmingCharacters(in: .whitespaces) == "$$" {
                    inLatexBlock = false
                    latexBlockLines.append("$$")
                    rendered.append(contentsOf: renderedLatexBlock(latexBlockLines))
                    latexBlockLines = []
                } else {
                    latexBlockLines.append(lines[index])
                }
                index += 1
                continue
            }

            if !continuingUnclosedTag {
                if isCodeFenceDelimiter(lines[index]) {
                    if inCodeFence {
                        inCodeFence = false
                        fenceHighlighter = nil
                        rendered.append(renderCodeFenceEnd())
                    } else {
                        inCodeFence = true
                        rendered.append(renderCodeFenceStart(lines[index]))
                        fenceHighlighter = FenceHighlighter(
                            infoString: codeFenceLanguage(lines[index]),
                            styles: theme.code
                        )
                    }
                    index += 1
                    continue
                }

                if inCodeFence {
                    rendered.append(renderCodeFenceContent(lines[index], highlighter: fenceHighlighter))
                    index += 1
                    continue
                }

                if lines[index].trimmingCharacters(in: .whitespaces) == "$$" {
                    inLatexBlock = true
                    latexBlockLines = ["$$"]
                    index += 1
                    continue
                }

                if let table = parseTable(
                    lines: lines,
                    start: index,
                    isFinal: isFinal,
                    endsWithNewline: endsWithNewline
                ) {
                    rendered.append(contentsOf: table.lines)
                    index += table.consumed
                    continue
                }
            }

            // HTML degrade happens before the inline pipeline (and strictly
            // outside fenced code, which returns earlier in this loop), so
            // each degraded segment gets full inline formatting and
            // LineChrome styling as usual. Tag-free lines pass through
            // byte-identical.
            if continuingUnclosedTag {
                pendingRawLines.append(lines[index])
                let continuation = HTMLDegrader.degradeContinuation(lines[index])
                if continuation.stillPending {
                    index += 1
                    continue
                }
                continuingUnclosedTag = false
                rendered.append(contentsOf: pendingSegments.map { renderInlineMarkdown($0) })
                rendered.append(contentsOf: continuation.segments.map { renderInlineMarkdown($0) })
                pendingSegments = []
                pendingRawLines = []
            } else {
                var opensUnclosedTag = false
                let segments = HTMLDegrader.degrade(lines[index], opensUnclosedTag: &opensUnclosedTag)
                if opensUnclosedTag {
                    continuingUnclosedTag = true
                    pendingRawLines = [lines[index]]
                    pendingSegments = segments
                } else {
                    rendered.append(contentsOf: segments.map { renderInlineMarkdown($0) })
                }
            }
            index += 1
        }
        if continuingUnclosedTag {
            // Tag never closed within this pass: keep the source lines.
            for rawLine in pendingRawLines {
                rendered.append(renderInlineMarkdown(rawLine, approximatingLatex: false))
            }
        }
        if inLatexBlock {
            // Display-math block never closed within this pass: keep the raw
            // delimiter and body lines.
            for rawLine in latexBlockLines {
                rendered.append(renderInlineMarkdown(rawLine, approximatingLatex: false))
            }
        }
        return rendered
    }

    /// Renders a closed `$$` block (`["$$", body…, "$$"]`): `\begin{…}`
    /// environments pass through raw — the identical pre-approximation
    /// pipeline — while plain display math is approximated line by line with
    /// the delimiters dropped.
    private func renderedLatexBlock(_ blockLines: [String]) -> [String] {
        if blockLines.contains(where: LaTeXApproximator.isEnvironment) {
            return blockLines.flatMap { line in
                HTMLDegrader.degrade(line).map {
                    renderInlineMarkdown($0, approximatingLatex: false)
                }
            }
        }
        return blockLines.dropFirst().dropLast().map { LaTeXApproximator.approximate($0) }
    }

    private func parseTable(
        lines: [String],
        start: Int,
        isFinal: Bool,
        endsWithNewline: Bool
    ) -> (lines: [String], consumed: Int)? {
        guard start + 1 < lines.count else { return nil }

        guard let headerCells = parseTableCells(lines[start]) else { return nil }
        guard let divider = parseDividerCells(lines[start + 1]), divider.count == headerCells.count else { return nil }

        var dataRows: [[String]] = []
        var hasMismatchedColumnCount = false
        var cursor = start + 2
        while cursor < lines.count, let cells = parseTableCells(lines[cursor]) {
            if cells.count != headerCells.count {
                hasMismatchedColumnCount = true
            }
            dataRows.append(cells)
            cursor += 1
        }

        guard !dataRows.isEmpty else { return nil }

        if options.tableStreamingBehavior == .strict,
           !isFinal, cursor == lines.count, !endsWithNewline {
            return nil
        }

        if hasMismatchedColumnCount {
            let degraded = Array(lines[start..<cursor])
            return (degraded, cursor - start)
        }

        if let rendered = renderTable(header: headerCells, alignment: divider, rows: dataRows) {
            return (rendered, cursor - start)
        }

        let degraded = Array(lines[start..<cursor])
        return (degraded, cursor - start)
    }

    private func isCodeFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return false }
        let run = trimmed.prefix(while: { $0 == first })
        return run.count >= 3
    }

    private func renderInlineMarkdown(_ line: String, approximatingLatex: Bool = true) -> String {
        guard !line.isEmpty else { return line }
        // LaTeX approximation is a text→text pass at the very top of the
        // pipeline: before structure classification, inline formatting, and
        // LineChrome styling — it never touches SGR output. Raw passthroughs
        // (fence content, \begin{…} environments, unclosed blocks) pass
        // `approximatingLatex: false`.
        let source = approximatingLatex ? LaTeXApproximator.approximatingSpans(in: line) : line
        let structured = renderStructuredLine(source)
        let formatted = applyInlineFormatting(structured?.text ?? source)
        guard let structured else { return formatted }
        switch structured.chrome {
        case .none:
            return formatted
        case .heading(let level):
            return applyBlockStyle(theme.headingStyle(forLevel: level), to: formatted)
        case .blockquote(let indentLength, let depth, let contentEmpty):
            return styledBlockquoteBar(
                in: formatted,
                indentLength: indentLength,
                depth: depth,
                contentEmpty: contentEmpty
            )
        }
    }

    /// Whether OSC 8 hyperlinks are emitted for links and bare URLs: on for
    /// styled themes, off for `.none` so the plain theme keeps the
    /// pre-hyperlink byte stream exactly.
    private var hyperlinksEnabled: Bool { theme != .none }

    /// Wraps already-styled `text` as an OSC 8 hyperlink to `url`
    /// (`ESC ] 8 ;; url ST text ESC ] 8 ;; ST`). Terminals without OSC 8
    /// support absorb the sequences silently, leaving the styled text.
    private func osc8Hyperlink(url: String, text styledText: String) -> String {
        "\u{1B}]8;;\(url)\u{1B}\\\(styledText)\u{1B}]8;;\u{1B}\\"
    }

    /// Trailing characters trimmed from a bare-URL autolink target: closing
    /// brackets, sentence punctuation, and quotes are almost never part of
    /// the URL itself (`(https://example.com)。` keeps `)。` outside).
    private static let bareURLTrailingTrim: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", ">", "\"", "'",
        "。", "，", "；", "！", "？", "）", "】", "」", "』", "、",
    ]

    /// Apply inline formatting: code spans (`` ` ``), bold (`**`), italic (`*`),
    /// strikethrough (`~~`), and links (`[text](url)`). Code spans take priority — no formatting within them.
    private func applyInlineFormatting(_ text: String) -> String {
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "`" {
                // Code span: find matching closing backtick(s)
                let (content, consumed) = parseCodeSpan(from: text, start: i)
                result += "\u{1B}[7m\(content)\u{1B}[0m"
                i = text.index(i, offsetBy: consumed)
                continue
            }
            // Link: [text](url) — requires no space between ](
            var linkParsed = false
            if text[i] == "[", let closeBracket = text[text.index(after: i)...].firstIndex(of: "]") {
                let afterBracket = text.index(after: closeBracket)
                if afterBracket < text.endIndex, text[afterBracket] == "(",
                   let closeParen = text[text.index(after: afterBracket)...].firstIndex(of: ")") {
                    let linkText = String(text[text.index(after: i)..<closeBracket])
                    // An optional quoted title may follow the URL
                    // (`[text](url "title")`): it is display text, not part
                    // of the link target — cut the URL at the first space.
                    let rawURL = String(text[text.index(after: afterBracket)..<closeParen])
                    let url = String(rawURL.prefix(while: { !$0.isWhitespace }))
                    if !linkText.isEmpty, !url.isEmpty {
                        let styledText = "\u{1B}[4m\(linkText)\u{1B}[0m"
                        if hyperlinksEnabled {
                            result += osc8Hyperlink(url: url, text: styledText)
                                + " \u{1B}[2m(\(url))\u{1B}[0m"
                        } else {
                            result += "\(styledText) \u{1B}[2m(\(url))\u{1B}[0m"
                        }
                        i = text.index(after: closeParen)
                        linkParsed = true
                    }
                }
            }
            if linkParsed { continue }
            // Bare URL autolink (http/https only): underlined OSC 8. Runs
            // after code spans and `[text](url)` so neither is re-matched;
            // fence content never reaches inline formatting. Trailing
            // punctuation (ASCII and CJK) is trimmed off the link target.
            var bareURLParsed = false
            if hyperlinksEnabled, text[i] == "h" {
                let rest = text[i...]
                let schemeLength = rest.hasPrefix("https://") ? 8 : (rest.hasPrefix("http://") ? 7 : 0)
                if schemeLength > 0 {
                    let urlStart = text.index(i, offsetBy: schemeLength)
                    var urlEnd = urlStart
                    while urlEnd < text.endIndex, !text[urlEnd].isWhitespace {
                        urlEnd = text.index(after: urlEnd)
                    }
                    while urlEnd > urlStart,
                          Self.bareURLTrailingTrim.contains(text[text.index(before: urlEnd)]) {
                        urlEnd = text.index(before: urlEnd)
                    }
                    if urlEnd > urlStart {
                        let url = String(text[i..<urlEnd])
                        result += osc8Hyperlink(url: url, text: "\u{1B}[4m\(url)\u{1B}[0m")
                        i = urlEnd
                        bareURLParsed = true
                    }
                }
            }
            if bareURLParsed { continue }
            let nextIdx = text.index(after: i)
            if nextIdx < text.endIndex, text[i] == "*", text[nextIdx] == "*" {
                // Bold: **text**
                let afterStars = text.index(i, offsetBy: 2)
                if let end = text[afterStars...].firstRange(of: "**") {
                    let content = String(text[afterStars..<end.lowerBound])
                    if !content.isEmpty {
                        result += "\u{1B}[1m\(applyInlineFormatting(content))\u{1B}[0m"
                        i = end.upperBound
                        continue
                    }
                }
            }
            if text[i] == "*" {
                // Italic: *text* (but not ** which is handled above).
                let afterStar = text.index(after: i)
                if afterStar < text.endIndex, text[afterStar] != " ",
                   let end = text[afterStar...].firstIndex(of: "*"),
                   end != afterStar {
                    let content = String(text[afterStar..<end])
                    if !content.isEmpty {
                        result += "\u{1B}[3m\(applyInlineFormatting(content))\u{1B}[0m"
                        i = text.index(after: end)
                        continue
                    }
                }
            }
            // Strikethrough: ~~text~~
            let nextIdxStrike = text.index(after: i)
            if nextIdxStrike < text.endIndex, text[i] == "~", text[nextIdxStrike] == "~" {
                let afterStrike = text.index(i, offsetBy: 2)
                if let end = text[afterStrike...].firstRange(of: "~~") {
                    let content = String(text[afterStrike..<end.lowerBound])
                    if !content.isEmpty {
                        result += "\u{1B}[9m\(applyInlineFormatting(content))\u{1B}[0m"
                        i = end.upperBound
                        continue
                    }
                }
            }
            result.append(text[i])
            i = text.index(after: i)
        }
        return result
    }

    /// Parse a code span starting at `start` (a backtick). Returns (content, characters consumed).
    private func parseCodeSpan(from text: String, start: String.Index) -> (String, Int) {
        // Count opening backticks
        var openCount = 0
        var i = start
        while i < text.endIndex, text[i] == "`" {
            openCount += 1
            i = text.index(after: i)
        }
        // Find matching closing backticks
        let contentStart = i
        while i < text.endIndex {
            if text[i] == "`" {
                var closeCount = 0
                var j = i
                while j < text.endIndex, text[j] == "`", closeCount < openCount {
                    closeCount += 1
                    j = text.index(after: j)
                }
                if closeCount == openCount {
                    let content = String(text[contentStart..<i])
                    let consumed = text.distance(from: start, to: j)
                    return (content, consumed)
                }
            }
            i = text.index(after: i)
        }
        // No closing backticks found — return the backticks as literal text
        let literal = String(text[start..<contentStart])
        return (literal, openCount)
    }

    /// Block-level chrome classification for a rendered line: which theme
    /// slot (if any) styles it, plus the bookkeeping needed to splice styles
    /// into the already-formatted text. Styling must run *after*
    /// `applyInlineFormatting` — SGR sequences contain `[`, which the inline
    /// link parser would otherwise swallow.
    private enum LineChrome {
        case none
        case heading(level: Int)
        case blockquote(indentLength: Int, depth: Int, contentEmpty: Bool)
    }

    private func renderStructuredLine(_ line: String) -> (text: String, chrome: LineChrome)? {
        let leadingWhitespace = String(line.prefix(while: isIndentationCharacter))
        let trimmed = line.dropFirst(leadingWhitespace.count)
        guard !trimmed.isEmpty else { return nil }

        let (quoteDepth, quoteContent) = parseBlockquotePrefix(trimmed)
        if quoteDepth > 0 {
            let quotePrefix = leadingWhitespace + String(repeating: "│ ", count: quoteDepth)
            let rendered = renderDecoratedContent(
                String(quoteContent),
                indentationLevel: 0,
                rawIndentPrefix: ""
            ) ?? String(quoteContent)
            let chrome = LineChrome.blockquote(
                indentLength: leadingWhitespace.count,
                depth: quoteDepth,
                contentEmpty: rendered.isEmpty
            )
            let text = rendered.isEmpty
                ? quotePrefix.trimmingCharacters(in: .whitespaces)
                : quotePrefix + rendered
            return (text, chrome)
        }

        guard let decorated = renderDecoratedContent(
            String(trimmed),
            indentationLevel: indentationUnits(in: leadingWhitespace),
            rawIndentPrefix: leadingWhitespace
        ) else { return nil }

        let chrome = parseHeadingLevel(String(trimmed)).map { LineChrome.heading(level: $0) } ?? .none
        return (decorated, chrome)
    }

    /// Restyles the `│` bars of an already inline-formatted blockquote line.
    /// The plain bars occupy exactly `indentLength + 2 * depth` leading
    /// characters (whitespace and `│` are never rewritten by inline
    /// formatting), so the styled bars are spliced in front of the content.
    /// Empty-content quotes emit only the bars (indent and trailing space
    /// trimmed), matching the unstyled byte stream shape.
    private func styledBlockquoteBar(
        in formatted: String,
        indentLength: Int,
        depth: Int,
        contentEmpty: Bool
    ) -> String {
        let styledBar = theme.blockquoteLine.applied(to: "│") + " "
        if contentEmpty {
            var bars = ""
            for _ in 0..<depth { bars += styledBar }
            return String(bars.dropLast())
        }
        var prefix = String(formatted.prefix(indentLength))
        for _ in 0..<depth { prefix += styledBar }
        return prefix + formatted.dropFirst(indentLength + 2 * depth)
    }

    /// Applies `style` around the whole already-formatted `text`, re-opening
    /// the style after every inline `ESC[0m` reset inside it so bold/italic
    /// spans within a heading don't wipe the heading style for the rest of
    /// the line. No-op for unstyled styles or empty text, keeping the
    /// `.none`-theme byte stream identical.
    private func applyBlockStyle(_ style: MarkdownStyle, to text: String) -> String {
        let opening = style.sgrOpeningSequence
        guard !opening.isEmpty, !text.isEmpty else { return text }
        let reset = "\u{1B}[0m"
        var content = text.replacingOccurrences(of: reset, with: reset + opening)
        if content.hasSuffix(reset + opening) {
            content.removeLast(opening.count)
        }
        if content.hasSuffix(reset) {
            return opening + content
        }
        return opening + content + reset
    }

    private func renderDecoratedContent(
        _ content: String,
        indentationLevel: Int,
        rawIndentPrefix: String
    ) -> String? {
        let leadingWhitespace = String(content.prefix(while: isIndentationCharacter))
        let trimmed = content.dropFirst(leadingWhitespace.count)
        guard !trimmed.isEmpty else { return nil }

        let totalIndentationLevel = indentationLevel + indentationUnits(in: leadingWhitespace)
        let body = String(trimmed)

        if let heading = renderHeading(body) {
            return rawIndentPrefix + leadingWhitespace + heading
        }
        if let listItem = renderListItem(body, nestingLevel: totalIndentationLevel) {
            // 列表缩进保留源码原始宽度（tab 按 4 折算成空格），不再统一压成
            // 每级两格：有序父条目（"1. " 宽 3）下的嵌套列表按惯例缩进 3 格，
            // 压成 2 格会让子条目比父条目正文还靠左，视觉上不成嵌套。
            // 偶数缩进与旧的归一化结果一致、行为不变；bullet 词汇仍按
            // totalIndentationLevel 选取，不受影响。
            let rawWidth = indentationWidth(in: rawIndentPrefix)
                + indentationWidth(in: leadingWhitespace)
            return String(repeating: " ", count: rawWidth) + listItem
        }
        if isThematicBreak(body) {
            return rawIndentPrefix + leadingWhitespace + thematicBreak
        }
        return nil
    }

    /// Heading level (1...6) when `line` is an ATX heading (`#` … `######`
    /// followed by a space and non-empty title); nil otherwise. Shared by
    /// `renderHeading` (text assembly) and line-chrome classification.
    private func parseHeadingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        let markerCount = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        guard trimmed.count > markerCount else { return nil }

        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: markerCount)
        guard trimmed[markerEnd] == " " else { return nil }

        let title = trimmed[trimmed.index(after: markerEnd)...].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : markerCount
    }

    private func renderHeading(_ line: String) -> String? {
        guard let markerCount = parseHeadingLevel(line) else { return nil }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: markerCount)
        let title = trimmed[trimmed.index(after: markerEnd)...].trimmingCharacters(in: .whitespaces)

        let prefix: String
        switch markerCount {
        case 1: prefix = "█ "
        case 2: prefix = "▓ "
        case 3: prefix = "▶ "
        case 4: prefix = "▹ "
        case 5: prefix = "• "
        default: prefix = "· "
        }
        return prefix + title
    }

    private func parseBlockquotePrefix(_ content: Substring) -> (depth: Int, remainder: Substring) {
        guard content.first == ">" else { return (0, content) }

        var index = content.startIndex
        var depth = 0
        while index < content.endIndex, content[index] == ">" {
            depth += 1
            index = content.index(after: index)
            if index < content.endIndex, content[index] == " " {
                index = content.index(after: index)
            }
        }
        return (depth, content[index...])
    }

    private func renderListItem(_ line: String, nestingLevel: Int) -> String? {
        let trimmed = line[...]
        guard !trimmed.isEmpty else { return nil }

        if let marker = trimmed.first, (marker == "-" || marker == "+" || marker == "*") {
            let nextIndex = trimmed.index(after: trimmed.startIndex)
            guard nextIndex < trimmed.endIndex, trimmed[nextIndex] == " " else { return nil }
            let afterSpace = trimmed.index(after: nextIndex)
            let rest = String(trimmed[afterSpace...])
            if rest.hasPrefix("[ ] ") {
                return "☐ \(rest.dropFirst(4))"
            }
            if rest.hasPrefix("[x] ") {
                return "☑ \(rest.dropFirst(4))"
            }
            return "\(unorderedListBullet(for: nestingLevel)) \(rest)"
        }

        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        guard digits.endIndex < trimmed.endIndex else { return nil }
        let separator = trimmed[digits.endIndex]
        guard separator == "." || separator == ")" else { return nil }
        let contentStart = trimmed.index(after: digits.endIndex)
        guard contentStart < trimmed.endIndex, trimmed[contentStart] == " " else { return nil }
        let content = String(trimmed[trimmed.index(after: contentStart)...])
        return "\(digits). \(content)"
    }

    private func unorderedListBullet(for nestingLevel: Int) -> String {
        let bullets = ["•", "◦", "▪", "▫"]
        let index = max(0, nestingLevel) % bullets.count
        return bullets[index]
    }

    /// 缩进空白串的显示宽度（tab 按 4 列计）。
    private func indentationWidth(in whitespace: String) -> Int {
        whitespace.reduce(into: 0) { partialResult, character in
            partialResult += character == "\t" ? 4 : 1
        }
    }

    private func indentationUnits(in whitespace: String) -> Int {
        max(0, indentationWidth(in: whitespace) / 2)
    }

    private func isIndentationCharacter(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let uniqueCharacters = Set(trimmed)
        guard uniqueCharacters.count == 1, let character = uniqueCharacters.first else { return false }
        return character == "-" || character == "*" || character == "_"
    }

    /// The fence info string: the delimiter line minus its backtick/tilde
    /// run, trimmed. Shared by the border label and highlighter selection.
    private func codeFenceLanguage(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return String(trimmed.drop(while: { $0 == "`" || $0 == "~" })).trimmingCharacters(in: .whitespaces)
    }

    private func renderCodeFenceStart(_ line: String) -> String {
        let language = codeFenceLanguage(line)
        let border = theme.fenceBorder.applied(to: "┌─ code")
        guard !language.isEmpty else { return border }
        return border + " " + theme.fenceLanguageLabel.applied(to: language)
    }

    private func renderCodeFenceEnd() -> String {
        theme.fenceBorder.applied(to: "└─ end code")
    }

    /// Renders one fence content line. The `│` gutter stays unstyled; with a
    /// recognized language the body is syntax-highlighted from `theme.code`,
    /// otherwise it passes through as plain text. Highlighting only wraps
    /// whole segments in complete SGR sequences and segments partition the
    /// line, so a `.none` theme emits the pre-highlight byte stream exactly.
    private func renderCodeFenceContent(_ line: String, highlighter: FenceHighlighter?) -> String {
        guard !line.isEmpty else { return "│" }
        guard let highlighter else { return "│ \(line)" }
        let body = highlighter.highlight(line: line)
            .map { $0.style.applied(to: $0.text) }
            .joined()
        return "│ \(body)"
    }

    private func splitRowCells(_ body: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var inCodeSpan = false

        for character in body {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "`" {
                inCodeSpan.toggle()
                current.append(character)
                continue
            }

            if character == "|", !inCodeSpan {
                cells.append(current)
                current.removeAll(keepingCapacity: true)
                continue
            }

            current.append(character)
        }

        if isEscaped {
            current.append("\\")
        }

        cells.append(current)
        return cells
    }

    private func hasUnescapedPipe(_ text: String) -> Bool {
        var isEscaped = false
        var inCodeSpan = false

        for character in text {
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "`" {
                inCodeSpan.toggle()
                continue
            }
            if character == "|", !inCodeSpan {
                return true
            }
        }
        return false
    }

    private func resolvedColumnWidths(
        idealWidths: [Int],
        columnCount: Int,
        policy: TableRenderPolicy
    ) -> [Int]? {
        guard !idealWidths.isEmpty, idealWidths.count == columnCount else { return nil }

        switch policy.overflowBehavior {
        case .degradeImmediately:
            return shouldDegradeWideTable(widths: idealWidths, maxRenderedWidth: policy.maxRenderedWidth)
                ? nil
                : idealWidths
        case .compactThenTruncateThenDegrade:
            let minimumWidth = max(1, policy.minColumnWidth)
            let maxContentWidth = policy.maxRenderedWidth - tableChromeWidth(for: columnCount)
            guard maxContentWidth >= minimumWidth * columnCount else { return nil }

            var widths = idealWidths.map { width in
                let clamped = max(minimumWidth, width)
                if let maxColumnWidth = policy.maxColumnWidth {
                    return min(clamped, max(maxColumnWidth, minimumWidth))
                }
                return clamped
            }

            var totalWidth = widths.reduce(0, +)
            while totalWidth > maxContentWidth {
                guard let widestIndex = widestShrinkableColumn(in: widths, minimumWidth: minimumWidth) else {
                    return nil
                }
                widths[widestIndex] -= 1
                totalWidth -= 1
            }

            return widths
        }
    }

    private func widestShrinkableColumn(in widths: [Int], minimumWidth: Int) -> Int? {
        var widestIndex: Int?
        var widestValue = minimumWidth

        for (index, width) in widths.enumerated() where width > widestValue {
            widestValue = width
            widestIndex = index
        }

        return widestIndex
    }

    private func tableChromeWidth(for columnCount: Int) -> Int {
        columnCount * 3 + 1
    }

    private func shouldDegradeWideTable(widths: [Int], maxRenderedWidth: Int) -> Bool {
        let renderedWidth = visibleWidth(borderLine(left: "┌", middle: "┬", right: "┐", widths: widths))
        return renderedWidth > maxRenderedWidth
    }

    private func parseTableCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard hasUnescapedPipe(trimmed), !trimmed.isEmpty else { return nil }

        var body = trimmed
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }

        let cells = splitRowCells(body)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return cells.count >= 2 ? cells : nil
    }

    private func parseDividerCells(_ line: String) -> [CellAlign]? {
        guard let cells = parseTableCells(line), !cells.isEmpty else { return nil }
        var aligns: [CellAlign] = []
        for cell in cells {
            let value = cell.trimmingCharacters(in: .whitespaces)
            let core = value.replacingOccurrences(of: ":", with: "")
            guard core.count >= 3, core.allSatisfy({ $0 == "-" }) else { return nil }

            if value.hasPrefix(":"), value.hasSuffix(":") {
                aligns.append(.center)
            } else if value.hasSuffix(":") {
                aligns.append(.right)
            } else {
                aligns.append(.left)
            }
        }
        return aligns
    }

    private func renderTable(header: [String], alignment: [CellAlign], rows: [[String]]) -> [String]? {
        let normalizedRows = rows.map { normalize(cells: $0, count: header.count) }
        // Cells carry inline markdown (`**bold**`, `` `code` ``, links): format
        // before any width math so `visibleWidth` (ANSI/OSC-aware) measures the
        // visible text and the markers never reach the terminal literally.
        let formattedHeader = header.map { applyInlineFormatting($0) }
        let formattedRows = normalizedRows.map { $0.map { applyInlineFormatting($0) } }
        var widths = Array(repeating: 0, count: header.count)

        for col in 0..<header.count {
            widths[col] = max(widths[col], visibleWidth(formattedHeader[col]))
            for row in formattedRows {
                widths[col] = max(widths[col], visibleWidth(row[col]))
            }
            widths[col] = max(widths[col], 1)
        }

        guard let resolvedWidths = resolvedColumnWidths(
            idealWidths: widths,
            columnCount: header.count,
            policy: options.tablePolicy
        ) else {
            return nil
        }

        if options.tablePolicy.wideTableStrategy == .autoReadable,
           shouldDegradeForReadability(
               idealWidths: widths,
               resolvedWidths: resolvedWidths,
               header: formattedHeader,
               rows: formattedRows,
               policy: options.tablePolicy
           ) {
            return nil
        }

        var output: [String] = []
        let border = theme.tableBorder
        output.append(border.applied(to: borderLine(left: "┌", middle: "┬", right: "┐", widths: resolvedWidths)))
        output.append(tableRow(
            cells: formattedHeader,
            aligns: alignment,
            widths: resolvedWidths,
            policy: options.tablePolicy,
            cellStyle: theme.tableHeader
        ))
        output.append(border.applied(to: borderLine(left: "├", middle: "┼", right: "┤", widths: resolvedWidths)))
        for row in formattedRows {
            output.append(tableRow(cells: row, aligns: alignment, widths: resolvedWidths, policy: options.tablePolicy))
        }
        output.append(border.applied(to: borderLine(left: "└", middle: "┴", right: "┘", widths: resolvedWidths)))
        return output
    }

    private func shouldDegradeForReadability(
        idealWidths: [Int],
        resolvedWidths: [Int],
        header: [String],
        rows: [[String]],
        policy: TableRenderPolicy
    ) -> Bool {
        guard policy.wideTableStrategy == .autoReadable else { return false }

        let truncatedCellThreshold = max(0.0, min(1.0, policy.autoReadableTruncatedCellThreshold))
        let trimmedWidthThreshold = max(0.0, min(1.0, policy.autoReadableTrimmedWidthThreshold))

        let totalCells = (rows.count + 1) * header.count
        guard totalCells > 0 else { return false }

        var truncatedCellCount = 0
        var totalTrimmedWidth = 0
        var totalIdealWidth = 0

        for col in 0..<header.count {
            let resolved = resolvedWidths[col]
            totalIdealWidth += idealWidths[col]
            totalTrimmedWidth += max(0, idealWidths[col] - resolved)

            if visibleWidth(header[col]) > resolved {
                truncatedCellCount += 1
            }
            for row in rows {
                if visibleWidth(row[col]) > resolved {
                    truncatedCellCount += 1
                }
            }
        }

        let truncatedCellRatio = Double(truncatedCellCount) / Double(totalCells)
        let trimmedWidthRatio = totalIdealWidth > 0 ? Double(totalTrimmedWidth) / Double(totalIdealWidth) : 0

        return truncatedCellRatio > truncatedCellThreshold
            || trimmedWidthRatio > trimmedWidthThreshold
    }

    private enum CellAlign {
        case left
        case center
        case right
    }

    private func normalize(cells: [String], count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func borderLine(left: String, middle: String, right: String, widths: [Int]) -> String {
        let segments = widths.map { String(repeating: "─", count: $0 + 2) }
        return left + segments.joined(separator: middle) + right
    }

    private func tableRow(
        cells: [String],
        aligns: [CellAlign],
        widths: [Int],
        policy: TableRenderPolicy,
        cellStyle: MarkdownStyle = .none
    ) -> String {
        var parts: [String] = []
        for index in 0..<cells.count {
            // Style wraps the finished (padded + truncated) cell as a whole —
            // never inside padded()/truncate(), where a cut would split an
            // SGR sequence and leak the style into subsequent output.
            parts.append(cellStyle.applied(to: padded(cells[index], width: widths[index], align: aligns[index], policy: policy)))
        }
        let bar = theme.tableBorder.applied(to: "│")
        return bar + " " + parts.joined(separator: " " + bar + " ") + " " + bar
    }

    private func padded(_ value: String, width: Int, align: CellAlign, policy: TableRenderPolicy) -> String {
        let fittedValue = truncate(value, toFit: width, indicator: policy.truncationIndicator)
        let textWidth = visibleWidth(fittedValue)
        let gap = max(0, width - textWidth)

        switch align {
        case .left:
            return fittedValue + String(repeating: " ", count: gap)
        case .right:
            return String(repeating: " ", count: gap) + fittedValue
        case .center:
            let left = gap / 2
            let right = gap - left
            return String(repeating: " ", count: left) + fittedValue + String(repeating: " ", count: right)
        }
    }

    private func truncate(_ value: String, toFit maxWidth: Int, indicator: String) -> String {
        guard maxWidth > 0 else { return "" }
        guard visibleWidth(value) > maxWidth else { return value }

        let indicatorWidth = min(maxWidth, visibleWidth(indicator))
        if indicatorWidth >= maxWidth {
            return fittingPrefix(of: indicator, maxWidth: maxWidth)
        }

        let prefixWidth = maxWidth - indicatorWidth
        let prefix = fittingPrefix(of: value, maxWidth: prefixWidth)
        // A cut styled span loses its closing SGR: append a reset so the
        // indicator and following cells don't inherit the leaked style.
        if prefix.contains("\u{1B}") {
            return prefix + "\u{1B}[0m" + indicator
        }
        return prefix + indicator
    }

    private func fittingPrefix(of value: String, maxWidth: Int) -> String {
        guard maxWidth > 0 else { return "" }
        var result = ""
        var currentWidth = 0
        var index = value.startIndex

        while index < value.endIndex {
            // Copy ANSI escape sequences whole and uncounted — cutting one
            // would garble output or leak styling (cell text reaches here
            // already inline-formatted).
            if value[index] == "\u{1B}" {
                let sequenceEnd = escapeSequenceEnd(in: value, at: index)
                result.append(contentsOf: value[index..<sequenceEnd])
                index = sequenceEnd
                continue
            }
            let character = value[index]
            let characterWidth = visibleWidth(String(character))
            if currentWidth + characterWidth > maxWidth {
                break
            }
            result.append(character)
            currentWidth += characterWidth
            index = value.index(after: index)
        }
        return result
    }

    /// End index of the ANSI escape sequence starting at `start` (which must
    /// point at ESC): CSI runs to its final byte (0x40–0x7E), OSC to BEL or
    /// ST, anything else is treated as a two-character sequence.
    private func escapeSequenceEnd(in text: String, at start: String.Index) -> String.Index {
        var index = text.index(after: start)
        guard index < text.endIndex else { return index }
        switch text[index] {
        case "[":
            index = text.index(after: index)
            while index < text.endIndex {
                let ch = text[index]
                index = text.index(after: index)
                if let ascii = ch.asciiValue, (0x40...0x7E).contains(ascii) { return index }
            }
            return index
        case "]":
            index = text.index(after: index)
            while index < text.endIndex {
                let ch = text[index]
                if ch == "\u{7}" { return text.index(after: index) }
                if ch == "\u{1B}" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\\" { return text.index(after: next) }
                }
                index = text.index(after: index)
            }
            return index
        default:
            return text.index(after: index)
        }
    }
}

private extension MarkdownStyle {
    /// The raw `ESC[…m` opening sequence for this style ("" when unstyled).
    /// Engine-side helper for re-opening a block style after inline resets.
    var sgrOpeningSequence: String {
        guard !attributes.isEmpty else { return "" }
        let parameters = attributes.flatMap(\.parameters).map(String.init).joined(separator: ";")
        return "\u{1B}[\(parameters)m"
    }
}
