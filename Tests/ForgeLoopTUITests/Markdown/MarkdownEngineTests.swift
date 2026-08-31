import XCTest
@testable import ForgeLoopTUI

final class MarkdownEngineTests: XCTestCase {
    /// TASK-24: the default theme now styles block chrome (headings, tables,
    /// quote bars, fence borders) with SGR. This suite pins the engine's
    /// plain byte stream and structural behavior, so its engines run under
    /// the `.none` theme; default-theme styling bytes are covered by
    /// `BlockElementStylingTests`.
    private func plainEngine() -> StreamingMarkdownEngine {
        StreamingMarkdownEngine(options: MarkdownRenderOptions(theme: .none))
    }

    func testPlainTextEngineSplitsByNewline() {
        let engine = PlainTextMarkdownEngine()
        let lines = engine.render(text: "alpha\nbeta\n", isFinal: true)
        XCTAssertEqual(lines, ["alpha", "beta", ""])
    }

    func testStreamingEngineRendersCompleteTable() {
        let engine = plainEngine()
        let text = """
        | name | score |
        | --- | ---: |
        | alice | 99 |
        | bob | 7 |
        """
        let lines = engine.render(text: text, isFinal: true)

        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("name") && $0.contains("score") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("alice") && $0.contains("99") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("bob") && $0.contains("7") }))
        XCTAssertTrue(lines.last?.hasPrefix("└") == true)
        XCTAssertFalse(lines.contains("| alice | 99 |"))
    }

    func testStreamingEngineKeepsIncompleteTableAsPlainTextWhenNotFinal() {
        let engine = StreamingMarkdownEngine()
        let text = """
        | name | score |
        | --- | ---: |
        | alice
        """
        let lines = engine.render(text: text, isFinal: false)
        XCTAssertEqual(lines, ["| name | score |", "| --- | ---: |", "| alice"])
    }

    func testStreamingEngineConvergesToTableOnFinalFlush() {
        let engine = plainEngine()
        let partial = """
        | name | score |
        | --- | ---: |
        | alice
        """
        _ = engine.render(text: partial, isFinal: false)

        let completed = """
        | name | score |
        | --- | ---: |
        | alice | 99 |
        """
        let lines = engine.render(text: completed, isFinal: true)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("alice") && $0.contains("99") }))
        XCTAssertFalse(lines.contains("| alice | 99 |"))
    }

    func testStreamingEngineRendersCompleteRowsAsTableWithoutTrailingNewline() {
        let engine = plainEngine()
        let text = """
        | name | score |
        | --- | ---: |
        | alice | 99 |
        | bob | 7 |
        """
        .trimmingCharacters(in: .newlines)

        let lines = engine.render(text: text, isFinal: false)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("alice") && $0.contains("99") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("bob") && $0.contains("7") }))
        XCTAssertFalse(lines.contains("| bob | 7 |"))
    }

    func testStreamingEngineKeepsTableRenderingWhileTrailingRowGrows() {
        let engine = plainEngine()
        let initial = """
        | name | score |
        | --- | --- |
        | alice |
        """
        .trimmingCharacters(in: .newlines)
        let afterFirstCell = """
        | name | score |
        | --- | --- |
        | alice | 9
        """
        .trimmingCharacters(in: .newlines)
        let afterSecondCell = """
        | name | score |
        | --- | --- |
        | alice | 99
        """
        .trimmingCharacters(in: .newlines)

        let step1 = engine.render(text: initial, isFinal: false)
        XCTAssertEqual(step1, ["| name | score |", "| --- | --- |", "| alice |"])

        let step2 = engine.render(text: afterFirstCell, isFinal: false)
        XCTAssertTrue(step2.first?.hasPrefix("┌") == true)
        XCTAssertFalse(step2.contains("| alice | 9"))

        let step3 = engine.render(text: afterSecondCell, isFinal: false)
        XCTAssertTrue(step3.first?.hasPrefix("┌") == true)
        XCTAssertTrue(step3.contains(where: { $0.contains("alice") && $0.contains("99") }))
        XCTAssertFalse(step3.contains("| alice | 99"))
    }

    func testStreamingEngineStrictModeKeepsRawTableUntilTerminated() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .default,
                tableStreamingBehavior: .strict
            )
        )
        let text = """
        | name | score |
        | --- | --- |
        | alice | 99 |
        | bob | 7 |
        """
        .trimmingCharacters(in: .newlines)

        let lines = engine.render(text: text, isFinal: false)
        XCTAssertEqual(lines, [
            "| name | score |",
            "| --- | --- |",
            "| alice | 99 |",
            "| bob | 7 |",
        ])
    }

    func testStreamingEngineRendersCodeFenceWithoutParsingNestedTable() {
        let engine = plainEngine()
        let text = """
        ```markdown
        | a | b |
        | --- | --- |
        | 1 | 2 |
        ```
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "┌─ code markdown",
            "│ | a | b |",
            "│ | --- | --- |",
            "│ | 1 | 2 |",
            "└─ end code",
        ])
        XCTAssertFalse(lines.contains(where: { $0.contains("│ a │") || $0.contains("┌──") }))
    }

    func testFourBacktickCodeFenceIsRecognized() {
        let engine = plainEngine()
        let text = """
        ````swift
        let x = 1
        ````
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "┌─ code swift",
            "│ let x = 1",
            "└─ end code",
        ])
    }

    func testFourTildeCodeFenceIsRecognized() {
        let engine = plainEngine()
        let text = """
        ~~~~
        tilde fence
        ~~~~
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "┌─ code",
            "│ tilde fence",
            "└─ end code",
        ])
    }

    func testStreamingEngineFormatsHeadingsQuotesListsAndCodeBlocks() {
        let engine = plainEngine()
        let text = """
        # Title

        > note
        - bullet
          * nested
        1. first
        ---
        ```swift
        let answer = 42
        ```
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "█ Title",
            "",
            "│ note",
            "• bullet",
            "  ◦ nested",
            "1. first",
            "────────────────────────",
            "┌─ code swift",
            "│ let answer = 42",
            "└─ end code",
        ])
    }

    func testStreamingEngineFormatsNestedBlockquotesAndMixedListHierarchy() {
        let engine = plainEngine()
        let text = """
        > quote
        >> deeper quote
        > - top bullet
        >   - nested bullet
        >     - deep bullet
          - sibling bullet
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "│ quote",
            "│ │ deeper quote",
            "│ • top bullet",
            "│   ◦ nested bullet",
            "│     ▪ deep bullet",
            "  ◦ sibling bullet",
        ])
    }

    func testStreamingEngineParsesEscapedPipeInCells() {
        let engine = StreamingMarkdownEngine()
        let text = """
        | col | raw |
        | --- | --- |
        | a \\| b | ok |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.contains(where: { $0.contains("│") && $0.contains("col") && $0.contains("raw") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("a | b") }))
    }

    func testStreamingEngineCompactsAndTruncatesVeryWideTableByDefault() {
        let engine = plainEngine()
        let wideCell = String(repeating: "x", count: 260)
        let text = """
        | col | detail |
        | --- | --- |
        | ok | \(wideCell) |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("col") && $0.contains("detail") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("…") }))
        XCTAssertTrue(lines.last?.hasPrefix("└") == true)
        XCTAssertFalse(lines.contains(where: { $0.contains(wideCell) }))
    }

    func testStreamingEngineCanDegradeWideTableImmediatelyViaPolicy() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .init(
                    maxRenderedWidth: 80,
                    minColumnWidth: 6,
                    maxColumnWidth: 24,
                    truncationIndicator: "…",
                    overflowBehavior: .degradeImmediately
                )
            )
        )
        let wideCell = String(repeating: "x", count: 260)
        let text = """
        | col | detail |
        | --- | --- |
        | ok | \(wideCell) |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "| col | detail |",
            "| --- | --- |",
            "| ok | \(wideCell) |",
        ])
    }

    func testStreamingEngineDegradesTooManyColumnsToPlainText() {
        let engine = StreamingMarkdownEngine()
        let text = """
        | c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8 | c9 | c10 | c11 | c12 | c13 | c14 | c15 | c16 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | a | b | c | d | e | f | g | h | i | j | k | l | m | n | o | p |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "| c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8 | c9 | c10 | c11 | c12 | c13 | c14 | c15 | c16 |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
            "| a | b | c | d | e | f | g | h | i | j | k | l | m | n | o | p |",
        ])
    }

    func testStreamingEngineKeepsInvalidDividerTableAsPlainText() {
        let engine = StreamingMarkdownEngine()
        let text = """
        | name | score |
        | nope | ---: |
        | alice | 99 |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "| name | score |",
            "| nope | ---: |",
            "| alice | 99 |",
        ])
    }

    func testStreamingEngineKeepsMismatchedBodyRowTableAsPlainText() {
        let engine = StreamingMarkdownEngine()
        let text = """
        | name | score |
        | --- | --- |
        | alice |
        | bob | 7 |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "| name | score |",
            "| --- | --- |",
            "| alice |",
            "| bob | 7 |",
        ])
    }

    func testStreamingEngineRendersCJKTableUsingVisibleWidths() {
        let engine = plainEngine()
        let text = """
        | 名称 | 值 |
        | --- | --- |
        | 测试 | 甲 |
        """

        let lines = engine.render(text: text, isFinal: true)

        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("名称") && $0.contains("值") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("测试") && $0.contains("甲") }))
        XCTAssertTrue(lines.last?.hasPrefix("└") == true)
    }

    // MARK: - WideTableStrategy Tests

    func testAutoReadableDegradesHeavilyTruncatedWideTableToRawMarkdown() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .init(
                    maxRenderedWidth: 80,
                    minColumnWidth: 6,
                    maxColumnWidth: 8,
                    wideTableStrategy: .autoReadable
                )
            )
        )
        let text = """
        | verylongname | anotherlong | yetanother | finalone | onemore |
        | --- | --- | --- | --- | --- |
        | aaaaaaaaaa | bbbbbbbbbb | cccccccccc | dddddddddd | eeeeeeeeee |
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "| verylongname | anotherlong | yetanother | finalone | onemore |",
            "| --- | --- | --- | --- | --- |",
            "| aaaaaaaaaa | bbbbbbbbbb | cccccccccc | dddddddddd | eeeeeeeeee |",
        ])
        XCTAssertFalse(lines.contains(where: { $0.hasPrefix("┌") }))
    }

    func testAutoReadableKeepsBoxDrawingForModerateWidthTable() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .init(wideTableStrategy: .autoReadable),
                theme: .none
            )
        )
        let text = """
        | name | score |
        | --- | ---: |
        | alice | 99 |
        | bob | 7 |
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("name") && $0.contains("score") }))
        XCTAssertTrue(lines.last?.hasPrefix("└") == true)
        XCTAssertFalse(lines.contains(where: { $0.contains("| name | score |") }))
    }

    func testAlwaysBoxRetainsTruncatedBoxDrawingForWideTable() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .init(
                    maxRenderedWidth: 80,
                    minColumnWidth: 6,
                    maxColumnWidth: 8,
                    wideTableStrategy: .alwaysBox
                ),
                theme: .none
            )
        )
        let text = """
        | verylongname | anotherlong | yetanother | finalone | onemore |
        | --- | --- | --- | --- | --- |
        | aaaaaaaaaa | bbbbbbbbbb | cccccccccc | dddddddddd | eeeeeeeeee |
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.contains(where: { $0.contains("…") }))
        XCTAssertTrue(lines.last?.hasPrefix("└") == true)
        XCTAssertFalse(lines.contains(where: { $0.contains("| verylongname |") }))
    }

    func testAutoReadablePreservesMonotonicStreamingSemantics() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .init(wideTableStrategy: .autoReadable),
                tableStreamingBehavior: .monotonic,
                theme: .none
            )
        )
        let partial = """
        | name | score |
        | --- | --- |
        | alice
        """
        .trimmingCharacters(in: .newlines)

        let step1 = engine.render(text: partial, isFinal: false)
        XCTAssertEqual(step1, ["| name | score |", "| --- | --- |", "| alice"])

        let completed = """
        | name | score |
        | --- | --- |
        | alice | 99 |
        """
        .trimmingCharacters(in: .newlines)

        let step2 = engine.render(text: completed, isFinal: false)
        XCTAssertTrue(step2.first?.hasPrefix("┌") == true)
        XCTAssertTrue(step2.contains(where: { $0.contains("alice") && $0.contains("99") }))
        XCTAssertFalse(step2.contains(where: { $0.contains("| alice | 99 |") }))
    }

    // MARK: - Inline formatting

    func testInlineCodeSpanWrapsWithReverseVideo() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "Use `git status` now", isFinal: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].contains("\u{1B}[7mgit status\u{1B}[0m"))
    }

    func testInlineBoldWrapsWithBoldANSI() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "Hello **world** here", isFinal: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].contains("\u{1B}[1mworld\u{1B}[0m"))
    }

    func testInlineItalicWrapsWithItalicANSI() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "This is *important* text", isFinal: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].contains("\u{1B}[3mimportant\u{1B}[0m"))
    }

    func testCodeSpanTakesPriorityOverBoldInside() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "`**not bold**` outside", isFinal: true)
        XCTAssertEqual(result.count, 1)
        // Inside code span, ** should be literal, not bold
        let line = result[0]
        XCTAssertTrue(line.contains("\u{1B}[7m**not bold**\u{1B}[0m"))
        XCTAssertFalse(line.contains("\u{1B}[1m"))
    }

    // MARK: - Link rendering

    func testBasicLinkRendersWithUnderlineAndURL() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "See [the docs](https://example.com) here", isFinal: true)
        XCTAssertEqual(result.count, 1)
        let line = result[0]
        XCTAssertTrue(line.contains("\u{1B}[4mthe docs\u{1B}[0m"))
        XCTAssertTrue(line.contains("\u{1B}[2m(https://example.com)\u{1B}[0m"))
    }

    func testEmptyLinkTextOrURLNotRendered() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "[](). not a link", isFinal: true)
        // Empty bracket/paren → rendered as literal text, not ANSI formatted
        XCTAssertFalse(result[0].contains("\u{1B}[4m"))
    }

    func testLinkInsideCodeSpanNotParsed() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "`[not a link](url)` end", isFinal: true)
        XCTAssertEqual(result.count, 1)
        // Inside code span, link syntax is literal
        XCTAssertTrue(result[0].contains("[not a link](url)"))
    }

    func testInlineFormattingDoesNotBreakHeadings() {
        let engine = plainEngine()
        let result = engine.render(text: "# Hello **world**", isFinal: true)
        XCTAssertEqual(result.count, 1)
        // Heading prefix preserved, bold applied to "world"
        XCTAssertTrue(result[0].hasPrefix("█ Hello "))
        XCTAssertTrue(result[0].contains("\u{1B}[1mworld\u{1B}[0m"))
    }

    // MARK: - Strikethrough

    func testStrikethroughBasic() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "hello ~~world~~", isFinal: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].contains("\u{1B}[9mworld\u{1B}[0m"))
    }

    func testStrikethroughNotInCodeSpan() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "`~~text~~`", isFinal: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].contains("\u{1B}[7m~~text~~\u{1B}[0m"))
        XCTAssertFalse(result[0].contains("\u{1B}[9m"))
    }

    func testStrikethroughEmpty() {
        let engine = StreamingMarkdownEngine()
        // Inline empty strikethrough (no content between markers) should not parse.
        let result = engine.render(text: "a ~~~~ b", isFinal: true)
        XCTAssertEqual(result, ["a ~~~~ b"])
    }

    func testStrikethroughWithBold() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "**bold ~~strike~~ end**", isFinal: true)
        XCTAssertEqual(result.count, 1)
        let line = result[0]
        XCTAssertTrue(line.contains("\u{1B}[1m"))
        XCTAssertTrue(line.contains("\u{1B}[9mstrike\u{1B}[0m"))
    }

    // MARK: - Task list

    func testTaskListUnchecked() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "- [ ] item", isFinal: true)
        XCTAssertEqual(result, ["☐ item"])
    }

    func testTaskListChecked() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "- [x] done", isFinal: true)
        XCTAssertEqual(result, ["☑ done"])
    }

    func testTaskListInBlockquote() {
        let engine = plainEngine()
        let result = engine.render(text: "> - [ ] task", isFinal: true)
        XCTAssertEqual(result, ["│ ☐ task"])
    }

    func testTaskListNoSpaceDegrades() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "- [x]not", isFinal: true)
        XCTAssertEqual(result, ["• [x]not"])
    }

    func testTaskListOnOrderedListDoesNotApply() {
        let engine = StreamingMarkdownEngine()
        let result = engine.render(text: "1. [x] item", isFinal: true)
        XCTAssertEqual(result, ["1. [x] item"])
    }

    // MARK: - Code fence streaming retreat

    /// 稳定边界落在未闭合代码块中间时，分段渲染（stable + live）的最终输出
    /// 必须与一次性 renderFully 全文的输出一致。修复前：闭合 ``` 在 live 片段里
    /// 被误判为新 fence 的开始，出现第二个 "┌─ code"。
    func testStreamingCodeFenceRetreatMatchesOneShotFinalRender() {
        let engine = plainEngine()
        let frame1 = "```swift\nlet x = 1\n"
        let frame2 = frame1 + "let y = 2\n"
        let frame3 = frame2 + "```\nafter\n"

        // 流式中间帧应与全新引擎对同一文本的一次性（非 final）渲染一致。
        XCTAssertEqual(
            engine.render(text: frame1, isFinal: false),
            plainEngine().render(text: frame1, isFinal: false)
        )
        XCTAssertEqual(
            engine.render(text: frame2, isFinal: false),
            plainEngine().render(text: frame2, isFinal: false)
        )

        let finalLines = engine.render(text: frame3, isFinal: true)
        XCTAssertEqual(
            finalLines,
            plainEngine().render(text: frame3, isFinal: true)
        )
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─ code") }.count, 1)
        XCTAssertEqual(finalLines.filter { $0 == "└─ end code" }.count, 1)
        XCTAssertTrue(finalLines.contains("│ let y = 2"))
    }

    /// fence 从输入最开始就未闭合：回退结果为 0，稳定前缀不推进，
    /// 直到 fence 闭合后一次性收敛到与一次性渲染相同的输出。
    func testStreamingCodeFenceUnclosedFromStartRetreatsToZero() {
        let engine = plainEngine()
        let frame1 = "```\nalpha\nbeta\n"
        XCTAssertEqual(
            engine.render(text: frame1, isFinal: false),
            ["┌─ code", "│ alpha", "│ beta", "│"]
        )

        let frame2 = frame1 + "gamma\n```\n"
        let finalLines = engine.render(text: frame2, isFinal: true)
        XCTAssertEqual(
            finalLines,
            plainEngine().render(text: frame2, isFinal: true)
        )
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─ code") }.count, 1)
        XCTAssertTrue(finalLines.contains("│ gamma"))
    }

    /// fence 之前的内容可以正常稳定化，回退点应落在 fence 起始行之前，
    /// 而不是整个输入的起点。
    func testStreamingCodeFenceRetreatPreservesContentBeforeFence() {
        let engine = plainEngine()
        let frame1 = "intro\n```\ncode1\n"
        XCTAssertEqual(
            engine.render(text: frame1, isFinal: false),
            plainEngine().render(text: frame1, isFinal: false)
        )

        let frame2 = frame1 + "code2\n```\noutro\n"
        let finalLines = engine.render(text: frame2, isFinal: true)
        XCTAssertEqual(
            finalLines,
            plainEngine().render(text: frame2, isFinal: true)
        )
        XCTAssertEqual(finalLines.first, "intro")
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─ code") }.count, 1)
        XCTAssertTrue(finalLines.contains("│ code2"))
    }

    /// 已闭合的 fence 不影响判定：只有最后一个仍未闭合的 fence 触发回退。
    func testStreamingCodeFenceRetreatIgnoresClosedFences() {
        let engine = plainEngine()
        let frame1 = "```\na\n```\nmiddle\n```\nb\n"
        _ = engine.render(text: frame1, isFinal: false)

        let frame2 = frame1 + "c\n```\n"
        let finalLines = engine.render(text: frame2, isFinal: true)
        XCTAssertEqual(
            finalLines,
            plainEngine().render(text: frame2, isFinal: true)
        )
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─ code") }.count, 2)
        XCTAssertEqual(finalLines.filter { $0 == "└─ end code" }.count, 2)
        XCTAssertTrue(finalLines.contains("│ c"))
    }

    /// 表格状内容出现在未闭合代码块内时，按 renderFully 的既有语义它是 fence
    /// 内容而非表格——fence retreat 必须先于表格 retreat 生效。
    func testTableLikeLinesInsideUnclosedCodeFenceRetreatToFenceStart() {
        let engine = plainEngine()
        let frame1 = "```markdown\n| a | b |\n| --- | --- |\n"
        _ = engine.render(text: frame1, isFinal: false)

        let frame2 = frame1 + "| 1 | 2 |\n"
        XCTAssertEqual(
            engine.render(text: frame2, isFinal: false),
            plainEngine().render(text: frame2, isFinal: false)
        )

        let frame3 = frame2 + "```\n"
        let finalLines = engine.render(text: frame3, isFinal: true)
        XCTAssertEqual(finalLines, [
            "┌─ code markdown",
            "│ | a | b |",
            "│ | --- | --- |",
            "│ | 1 | 2 |",
            "└─ end code",
            "",
        ])
    }

    /// isFinal = true 路径不受影响：stableAdvance 直接推进全文，
    /// 未闭合 fence 按既有行为渲染为未闭合的代码块。
    func testFinalRenderOfUnclosedCodeFenceIsUnchanged() {
        let engine = plainEngine()
        let lines = engine.render(text: "```swift\nlet x = 1\n", isFinal: true)
        XCTAssertEqual(lines, ["┌─ code swift", "│ let x = 1", "│"])
    }

    // MARK: - Stable prefix cap (C4)

    func testLongStreamingContentDoesNotGrowUnbounded() {
        let engine = StreamingMarkdownEngine()
        // Generate content well beyond the 65KB cap
        let longLine = String(repeating: "abcdefghij", count: 7000) // ~70KB
        let result = engine.render(text: longLine, isFinal: true)
        // Should not crash or produce empty output despite internal reset
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains(where: { $0.contains("abcdefghij") }))
    }
}

@MainActor
final class TranscriptRendererMarkdownTests: XCTestCase {
    func testTranscriptRendererRendersTableInFinalOutput() {
        let renderer = TranscriptRenderer(markdownOptions: .init(theme: .none))

        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageUpdate(message: .assistant(
            text: """
            | a | b |
            | --- | --- |
            | 1 | 2 |
            """,
            thinking: nil,
            errorMessage: nil
        )))
        renderer.apply(.messageEnd(message: .assistant(
            text: """
            | a | b |
            | --- | --- |
            | 1 | 2 |
            """,
            thinking: nil,
            errorMessage: nil
        )))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("┌") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("a") && $0.contains("b") && $0.contains("│") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("1") && $0.contains("2") && $0.contains("│") }))
    }

    func testTranscriptRendererSupportsCustomMarkdownOptions() {
        let renderer = TranscriptRenderer(
            markdownOptions: .init(
                tablePolicy: .init(
                    maxRenderedWidth: 80,
                    minColumnWidth: 4,
                    maxColumnWidth: 8,
                    truncationIndicator: "...",
                    overflowBehavior: .compactThenTruncateThenDegrade
                )
            )
        )

        renderer.apply(.messageStart(message: .assistant(text: "", thinking: nil, errorMessage: nil)))
        renderer.apply(.messageEnd(message: .assistant(
            text: """
            | option | description |
            | --- | --- |
            | data | path to data files to supply the data that will be passed into templates |
            """,
            thinking: nil,
            errorMessage: nil
        )))

        let lines = renderer.transcriptLines
        XCTAssertTrue(lines.contains(where: { $0.contains("...") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("path to data files to supply the data that will be passed into templates") }))
    }

    // MARK: Table cells inline formatting

    func testStreamingEngineAppliesInlineFormattingInsideTableCells() {
        let engine = StreamingMarkdownEngine(options: MarkdownRenderOptions(theme: .none))
        let text = """
        | 服务 | 低谷时段 |
        | --- | --- |
        | **DeepSeek** | 00:30 – 08:30 |
        | `Kimi` | 23:00 – 09:00 |
        """

        let lines = engine.render(text: text, isFinal: true)
        let rowLines = lines.filter { $0.contains("│") }
        XCTAssertFalse(rowLines.isEmpty)
        // Markers are consumed, never rendered literally.
        XCTAssertFalse(rowLines.contains(where: { $0.contains("**") || $0.contains("`") }))
        // Bold SGR wraps exactly the cell text.
        XCTAssertTrue(lines.contains(where: { $0.contains("\u{1B}[1mDeepSeek\u{1B}[0m") }))
        // Width math used the visible text: every row renders at one width.
        XCTAssertEqual(Set(rowLines.map { visibleWidth($0) }).count, 1)
    }

    func testStreamingEngineTruncatesStyledTableCellWithoutSplittingEscapeSequences() {
        let engine = StreamingMarkdownEngine(options: MarkdownRenderOptions(theme: .none))
        let wideBold = "**" + String(repeating: "x", count: 300) + "**"
        let text = """
        | col | detail |
        | --- | --- |
        | ok | \(wideBold) |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.contains(where: { $0.contains("…") }))
        let rowLines = lines.filter { $0.contains("│") }
        XCTAssertEqual(Set(rowLines.map { visibleWidth($0) }).count, 1)
        if let cut = rowLines.first(where: { $0.contains("…") && $0.contains("\u{1B}[1m") }) {
            XCTAssertTrue(cut.contains("\u{1B}[0m"), "a cut bold span must be closed with a reset")
        }
    }
}
