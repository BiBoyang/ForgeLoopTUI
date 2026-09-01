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
            "┌─ markdown",
            "│ | a | b |",
            "│ | --- | --- |",
            "│ | 1 | 2 |",
            "└─",
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
            "┌─ swift",
            "│ let x = 1",
            "└─",
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
            "┌─",
            "│ tilde fence",
            "└─",
        ])
    }

    // MARK: - Code fence chrome labels (TASK-33)

    /// 无语言 fence 的 chrome 是纯边框：开栏 `┌─` 不带兜底 "code" 标签，
    /// 闭栏 `└─` 永远不带 "end …" 字样。
    func testCodeFenceWithoutLanguageRendersBareBorder() {
        let engine = plainEngine()
        let text = """
        ```
        plain text
        ```
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "┌─",
            "│ plain text",
            "└─",
        ])
    }

    /// 有语言 fence 的标签位只放语言本身（`┌─ python`），
    /// 不再拼静态 "code" 字样。
    func testCodeFenceWithLanguageShowsLanguageLabelOnly() {
        let engine = plainEngine()
        let text = """
        ```python
        print("hi")
        ```
        """
        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "┌─ python",
            #"│ print("hi")"#,
            "└─",
        ])
    }

    /// 流式中间态（fence 未闭合）同样不泄漏：无语言首帧起就是裸 `┌─`，
    /// 有语言是 `┌─ <lang>`；任何帧都不出现 "code" 兜底标签或
    /// "end …" 闭栏字样，闭合后收敛为纯边框。
    func testStreamingUnclosedCodeFenceNeverLeaksPlaceholderLabels() {
        let noLanguage = plainEngine()
        let frame1 = "```\nalpha\n"
        XCTAssertEqual(noLanguage.render(text: frame1, isFinal: false), ["┌─", "│ alpha", "│"])
        let frame2 = frame1 + "beta\n```\n"
        XCTAssertEqual(noLanguage.render(text: frame2, isFinal: true), ["┌─", "│ alpha", "│ beta", "└─", ""])

        let withLanguage = plainEngine()
        let partial = "```swift\nlet x = 1\n"
        XCTAssertEqual(withLanguage.render(text: partial, isFinal: false), ["┌─ swift", "│ let x = 1", "│"])
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
            "┌─ swift",
            "│ let answer = 42",
            "└─",
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

    // MARK: - Nested list indentation (TASK-34)

    /// 症状回归：有序条目（"1. " 宽 3）下的嵌套 bullet 曾按每级两格归一化
    /// 压到 2 格，比父条目正文（缩进 3）还靠左。修复后保留源码原始缩进。
    func testNestedListUnderOrderedItemKeepsParentContentIndent() {
        let engine = plainEngine()
        let text = """
        1. 把 query 改成 context vector
           不是只 embed 用户最后一句
           - 当前目标
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "1. 把 query 改成 context vector",
            "   不是只 embed 用户最后一句",
            "   ◦ 当前目标",
        ])
    }

    /// 三级混合嵌套：缩进逐级跟随源码原始宽度（3 → 5），子级不窄于父级
    /// 内容列；bullet 词汇仍按层级选取（◦ → 二级）。
    func testThreeLevelMixedListKeepsRawNestingIndent() {
        let engine = plainEngine()
        let text = """
        1. top
           - second
             1. third
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "1. top",
            "   ◦ second",
            "     1. third",
        ])
    }

    /// 偶数缩进风格（每级 2 格）钉住不变：与归一化结果一致。
    func testTwoSpaceNestingStyleIsPreserved() {
        let engine = plainEngine()
        let text = """
        - outer
          - inner
            - deep
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "• outer",
            "  ◦ inner",
            "    ▪ deep",
        ])
    }

    /// 双位数字有序父条目（"10. " 宽 4）下的嵌套 bullet 对齐内容列 4。
    /// （bullet 词汇按缩进层级选取，4 格 = level 2 → ▪，非本任务改动范围。）
    func testNestedListUnderDoubleDigitOrderedItemAlignsToContentColumn() {
        let engine = plainEngine()
        let text = """
        10. item
            - child
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertEqual(lines, [
            "10. item",
            "    ▪ child",
        ])
    }

    /// 流式逐帧渲染与一次性渲染逐行一致：列表渲染仍是单行纯函数，
    /// stable-prefix 已提交行不因后续帧而改变。
    func testNestedListStreamingFramesMatchOneShotRender() {
        let frames = [
            "1. top\n",
            "1. top\n   - second\n",
            "1. top\n   - second\n     1. third\n",
        ]
        let engine = plainEngine()
        for frame in frames {
            XCTAssertEqual(
                engine.render(text: frame, isFinal: false),
                plainEngine().render(text: frame, isFinal: false)
            )
        }
        let full = frames.last!
        XCTAssertEqual(
            engine.render(text: full, isFinal: true),
            plainEngine().render(text: full, isFinal: true)
        )
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
        // The default truncation indicator is width-deterministic ASCII
        // ("..."), never the East-Asian-Ambiguous "…" (TASK-35).
        XCTAssertTrue(lines.contains(where: { $0.contains("...") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("…") }))
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
        XCTAssertTrue(lines.contains(where: { $0.contains("...") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("…") }))
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
    /// 被误判为新 fence 的开始，出现第二个 "┌─ swift"。
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
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─") }.count, 1)
        XCTAssertEqual(finalLines.filter { $0 == "└─" }.count, 1)
        XCTAssertTrue(finalLines.contains("│ let y = 2"))
    }

    /// fence 从输入最开始就未闭合：回退结果为 0，稳定前缀不推进，
    /// 直到 fence 闭合后一次性收敛到与一次性渲染相同的输出。
    func testStreamingCodeFenceUnclosedFromStartRetreatsToZero() {
        let engine = plainEngine()
        let frame1 = "```\nalpha\nbeta\n"
        XCTAssertEqual(
            engine.render(text: frame1, isFinal: false),
            ["┌─", "│ alpha", "│ beta", "│"]
        )

        let frame2 = frame1 + "gamma\n```\n"
        let finalLines = engine.render(text: frame2, isFinal: true)
        XCTAssertEqual(
            finalLines,
            plainEngine().render(text: frame2, isFinal: true)
        )
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─") }.count, 1)
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
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─") }.count, 1)
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
        XCTAssertEqual(finalLines.filter { $0.hasPrefix("┌─") }.count, 2)
        XCTAssertEqual(finalLines.filter { $0 == "└─" }.count, 2)
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
            "┌─ markdown",
            "│ | a | b |",
            "│ | --- | --- |",
            "│ | 1 | 2 |",
            "└─",
            "",
        ])
    }

    /// isFinal = true 路径不受影响：stableAdvance 直接推进全文，
    /// 未闭合 fence 按既有行为渲染为未闭合的代码块。
    func testFinalRenderOfUnclosedCodeFenceIsUnchanged() {
        let engine = plainEngine()
        let lines = engine.render(text: "```swift\nlet x = 1\n", isFinal: true)
        XCTAssertEqual(lines, ["┌─ swift", "│ let x = 1", "│"])
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

    // MARK: - Table cell wrapping (TASK-36)

    /// 换行表格物理行 → 各列去补白后的可见文本（按 │ 切分；段内补白只
    /// 出现在两端，测试内容均不以空格开头/结尾，trim 不丢内容）。
    private func wrappedRowColumns(_ line: String) -> [String] {
        ansiStripped(line)
            .split(separator: "│", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func testTableCellWrapsLongCJKCellWhenOverBudget() {
        // 预算 40 列、无 maxColumnWidth 钳制：理想宽 82 > 33 预算 → 压缩
        // 最宽列到 29，CJK 单元格按 14/14/11 字符换行成 3 个物理行。
        let policy = TableRenderPolicy(maxRenderedWidth: 40, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let longCell = String(repeating: "这是一段需要换行的中文内容", count: 3)
        let text = """
        | 名称 | 说明 |
        | --- | --- |
        | 配置 | \(longCell) |
        """

        let lines = engine.render(text: text, isFinal: true)

        // 3 条边框 + 1 表头物理行 + 3 数据物理行；边框闭合。
        XCTAssertEqual(lines.count, 7)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertTrue(lines.last?.hasPrefix("└") == true)
        XCTAssertTrue(lines[2].hasPrefix("├"))
        // 所有物理行可见宽度一致（对齐零误差）。
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [40])
        // 无截断标记：内容零丢失。
        XCTAssertFalse(lines.contains(where: { $0.contains("...") }))
        // 同行的其他单元格首段对齐、后续段留空。
        let dataLines = Array(lines[3...5])
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[1] }, ["配置", "", ""])
        // 换行段按序拼回原始单元格文本。
        let reconstructed = dataLines.map { wrappedRowColumns($0)[2] }.joined()
        XCTAssertEqual(reconstructed, longCell)
    }

    func testTableCellWrapKeepsBoldSegmentsSelfContained() {
        let policy = TableRenderPolicy(maxRenderedWidth: 40, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let boldCell = "**" + String(repeating: "x", count: 40) + "**"
        let text = """
        | col | detail |
        | --- | --- |
        | ok | \(boldCell) |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...4])

        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [40])
        for line in dataLines {
            // 段尾必须补 reset：本行打开的 bold 必须在本行内闭合，
            // 样式不泄漏到右侧补白与边框。
            guard let lastOpen = line.range(of: "\u{1B}[1m", options: .backwards),
                  let lastReset = line.range(of: "\u{1B}[0m", options: .backwards) else {
                XCTFail("wrapped bold segment lost its SGR pair: \(line.debugDescription)")
                continue
            }
            XCTAssertTrue(lastOpen.lowerBound < lastReset.lowerBound)
        }
        // 段首重开：第二个物理行同样带完整 bold 包裹。
        XCTAssertTrue(dataLines[1].contains("\u{1B}[1m"))
        let reconstructed = dataLines.map { wrappedRowColumns($0)[2] }.joined()
        XCTAssertEqual(reconstructed, String(repeating: "x", count: 40))
    }

    func testTableCellWrapMultiColumnRowHeightUsesMaxSegmentCount() {
        // 两列同时被压到理想宽之下：col1 换 2 段、col2 换 3 段，
        // 行高取最大值 3，col1 的第三个物理行留空补齐。
        let policy = TableRenderPolicy(maxRenderedWidth: 22, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let cell1 = String(repeating: "c", count: 10)
        let cell2 = String(repeating: "d", count: 20)
        let text = """
        | aa | bb |
        | --- | --- |
        | \(cell1) | \(cell2) |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...5])

        XCTAssertEqual(lines.count, 7)
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [22])
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[1] }.joined(), cell1)
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }.joined(), cell2)
        // 段数不足的列在后续物理行留空。
        XCTAssertEqual(wrappedRowColumns(dataLines[2])[1], "")
        XCTAssertFalse(wrappedRowColumns(dataLines[2])[2].isEmpty)
    }

    func testTableCellWrapStreamingMatchesOneShotAndStablePrefixNeverRewinds() {
        let policy = TableRenderPolicy(maxRenderedWidth: 40, minColumnWidth: 4, maxColumnWidth: nil)
        let text = """
        | 名称 | 说明 |
        | --- | --- |
        | 配置 | \(String(repeating: "这是一段需要换行的中文内容", count: 3)) |
        """
        let expected = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
            .render(text: text, isFinal: true)

        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        var accumulated = ""
        var previousStableCount = 0
        for character in text {
            accumulated.append(character)
            let frame = engine.render(text: accumulated, isFinal: false)
            let stableCount = engine.stableRenderedLineCount
            XCTAssertLessThanOrEqual(stableCount, frame.count)
            XCTAssertGreaterThanOrEqual(stableCount, previousStableCount)
            // 已认证 stable 的行与终态逐行一致，绝不因后续 chunk 改变。
            XCTAssertEqual(Array(frame.prefix(stableCount)), Array(expected.prefix(stableCount)))
            previousStableCount = stableCount
        }
        let finalFrame = engine.render(text: accumulated, isFinal: true)
        XCTAssertEqual(finalFrame, expected)
    }

    func testTableCellWrapBeyondSegmentCapShowsExplicitOmissionMarker() {
        // 450 列宽内容压进 19 列 → 24 段 > 上限 20：保留前 20 段，
        // 追加显式省略标注行 "... (4 more lines)"，不允许静默截断。
        let policy = TableRenderPolicy(maxRenderedWidth: 30, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let text = """
        | a | b |
        | --- | --- |
        | x | \(String(repeating: "y", count: 450)) |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        XCTAssertEqual(dataLines.count, 21)
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [30])
        XCTAssertTrue(dataLines.last?.contains("... (4 more lines)") == true)
        XCTAssertEqual(wrappedRowColumns(dataLines.last!)[1], "")
        // 前 20 段内容完整，无静默丢失。
        let reconstructed = dataLines.prefix(20).map { wrappedRowColumns($0)[2] }.joined()
        XCTAssertEqual(reconstructed, String(repeating: "y", count: 380))
    }

    func testAutoReadableStaysBoxedWhenCellsWrap() {
        // 换行模式下内容零丢失、可读性不受损：autoReadable 不再降级成
        // 原始管道文本（降级判定只适用于截断路径）。
        let policy = TableRenderPolicy(
            maxRenderedWidth: 40,
            minColumnWidth: 4,
            maxColumnWidth: nil,
            wideTableStrategy: .autoReadable
        )
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let longCell = String(repeating: "这是一段需要换行的中文内容", count: 3)
        let text = """
        | 名称 | 说明 |
        | --- | --- |
        | 配置 | \(longCell) |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.first?.hasPrefix("┌") == true)
        XCTAssertFalse(lines.contains("| 配置 | \(longCell) |"))
        let dataLines = Array(lines[3...5])
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }.joined(), longCell)
    }

    func testTableCellWrapKeepsHyperlinkSequencesBalanced() {
        // 默认主题下链接带 OSC 8：换行切断处必须闭合链接（下一段段首
        // 重开），任何物理行内 OSC 8 开闭数量必须相等，否则链接状态
        // 泄漏到边框与后续行。
        let policy = TableRenderPolicy(maxRenderedWidth: 30, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy))
        let text = """
        | col | link |
        | --- | --- |
        | ok | [abcdefghijklmnopqrstuvwxyz](https://example.com) |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [30])
        for line in lines {
            let opens = line.components(separatedBy: "\u{1B}]8;;https://").count - 1
            let closes = line.components(separatedBy: "\u{1B}]8;;\u{1B}\\").count - 1
            XCTAssertEqual(opens, closes, "hyperlink must close within the same physical line")
        }
        // 词边界断行（TASK-38）：链接文本与 "(https://...)" 之间的空格恰为
        // 断点，断点空白按约定丢弃，因此拼回时该位置没有空格。
        let reconstructed = dataLines.map { wrappedRowColumns($0)[2] }.joined()
        XCTAssertEqual(reconstructed, "abcdefghijklmnopqrstuvwxyz(https://example.com)")
    }

    // MARK: - Table cell word-boundary wrapping (TASK-38)

    func testTableCellWrapPrefersWordBoundariesForEnglishWords() {
        // 断行优先取段内最近空白之后：完整词保留，不断出 "Deskto/p"。
        let policy = TableRenderPolicy(maxRenderedWidth: 24, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let text = """
        | tool | status |
        | --- | --- |
        | Docker Desktop | ok |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        // 列宽 13："Docker Desktop"(14) 在词边界断成 "Docker" / "Desktop"。
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[1] }, ["Docker", "Desktop"])
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }.joined(), "ok")
        // 所有物理行对齐同一可见宽度，且各段不超列宽（13）。
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [24])
        for line in dataLines {
            XCTAssertLessThanOrEqual(visibleWidth(wrappedRowColumns(line)[1]), 13)
        }
    }

    func testTableCellWrapDropsOnlyBreakPointWhitespace() {
        // 断点空白丢弃、内容空白保留：多词单元格按词贪心装行，非断点处的
        // 空格原样留在段内。
        let policy = TableRenderPolicy(maxRenderedWidth: 19, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let text = """
        | a | b |
        | --- | --- |
        | x | one two three four |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        // 列宽 8：贪心装词 "one two" / "three" / "four"；断点空格丢弃，
        // 段内空格（"one two" 中间那个）保留。
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }, ["one two", "three", "four"])
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [19])
    }

    func testTableCellWrapHardBreaksWordLongerThanColumn() {
        // 词比列宽还长：无词边界可用，退回按宽度硬断（兜底与旧行为一致）。
        let policy = TableRenderPolicy(maxRenderedWidth: 24, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let word = "supercalifragilistic" // 20 列
        let text = """
        | a | b |
        | --- | --- |
        | x | \(word) |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        // 列宽 13：20 列单词硬断成 13/7 两段，内容零丢失。
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }, ["supercalifrag", "ilistic"])
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }.joined(), word)
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [24])
    }

    func testTableCellWrapMixedCJKEnglishKeepsWordsAndAllowsCJKBreaks() {
        // CJK 混排：英文词不被劈开，CJK 侧仍允许任意位置断（现状）。
        let policy = TableRenderPolicy(maxRenderedWidth: 24, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let text = """
        | a | b |
        | --- | --- |
        | x | 中文 Docker Desktop 混排 |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        // 列宽 13："中文 Docker" 11 列恰好一行（断点空格丢弃）；
        // "Desktop 混排" 12 列一行；词均未从中间劈开。
        XCTAssertEqual(dataLines.map { wrappedRowColumns($0)[2] }, ["中文 Docker", "Desktop 混排"])
        for line in dataLines {
            XCTAssertLessThanOrEqual(visibleWidth(wrappedRowColumns(line)[2]), 13)
        }
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [24])
    }

    func testTableCellWrapWordBoundaryKeepsStyledSegmentsSelfContained() {
        // 样式单元格的词边界断行：每个物理行 SGR 自洽（开在前、闭在后），
        // 样式不泄漏到补白与边框；断点空白丢弃后内容可拼回。
        let policy = TableRenderPolicy(maxRenderedWidth: 26, minColumnWidth: 4, maxColumnWidth: nil)
        let engine = StreamingMarkdownEngine(options: .init(tablePolicy: policy, theme: .none))
        let text = """
        | col | detail |
        | --- | --- |
        | ok | **Docker Desktop Kubernetes** |
        """

        let lines = engine.render(text: text, isFinal: true)
        let dataLines = Array(lines[3...(lines.count - 2)])

        XCTAssertEqual(Set(lines.map { visibleWidth($0) }), [26])
        for line in dataLines {
            guard let lastOpen = line.range(of: "\u{1B}[1m", options: .backwards),
                  let lastReset = line.range(of: "\u{1B}[0m", options: .backwards) else {
                XCTFail("wrapped bold segment lost its SGR pair: \(line.debugDescription)")
                continue
            }
            XCTAssertTrue(lastOpen.lowerBound < lastReset.lowerBound)
        }
        // 词边界断行：列宽 15，"Docker Desktop"(14) 整词组保留在第一段，
        // 断点取在第二个空格处（丢弃），第二段为完整词 "Kubernetes"。
        let segments = dataLines.map { wrappedRowColumns($0)[2] }
        XCTAssertEqual(segments, ["Docker Desktop", "Kubernetes"])
        for segment in segments {
            XCTAssertFalse(segment.hasPrefix(" "), "段首不保留断点空白")
            XCTAssertFalse(segment.hasSuffix(" "), "段尾不保留断点空白")
        }
        XCTAssertEqual(segments.joined(), "Docker DesktopKubernetes")
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
        XCTAssertTrue(lines.contains(where: { $0.contains("...") }))
        let rowLines = lines.filter { $0.contains("│") }
        XCTAssertEqual(Set(rowLines.map { visibleWidth($0) }).count, 1)
        if let cut = rowLines.first(where: { $0.contains("...") && $0.contains("\u{1B}[1m") }) {
            XCTAssertTrue(cut.contains("\u{1B}[0m"), "a cut bold span must be closed with a reset")
        }
    }

    // MARK: - Ambiguous-width truncation indicator (TASK-35)

    /// The truncation indicator sits flush against a column's right border,
    /// so it must occupy exactly the budgeted width in every terminal:
    /// East-Asian-Ambiguous glyphs like "…" render double-width in some
    /// terminal/font configurations, which would push that row's border one
    /// cell out. The default indicator is therefore width-deterministic
    /// ASCII; terminals known to be ambiguous=1 can still opt back into "…".
    func testTableTruncationIndicatorDefaultsToWidthStableASCII() {
        XCTAssertEqual(TableRenderPolicy.default.truncationIndicator, "...")
        XCTAssertEqual(TableRenderPolicy().truncationIndicator, "...")
        // The empty-string fallback must not reintroduce an ambiguous glyph.
        XCTAssertEqual(TableRenderPolicy(truncationIndicator: "").truncationIndicator, "...")
    }

    func testStreamingEngineTruncatedTableStaysBorderAlignedWithDefaultIndicator() {
        let engine = StreamingMarkdownEngine(options: MarkdownRenderOptions(theme: .none))
        let wideCell = String(repeating: "x", count: 120)
        let text = """
        | name | detail |
        | --- | --- |
        | ok | \(wideCell) |
        """

        let lines = engine.render(text: text, isFinal: true)
        // Border lines and every content row occupy one identical width.
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }).count, 1)
        // The truncated cell carries the width-stable indicator…
        XCTAssertTrue(lines.contains(where: { $0.contains("...") }))
        // …and no East-Asian-Ambiguous ellipsis leaks into bordered output.
        XCTAssertFalse(lines.contains(where: { $0.contains("…") }))
    }

    func testStreamingEngineHonorsExplicitAmbiguousTruncationIndicator() {
        let engine = StreamingMarkdownEngine(
            options: .init(
                tablePolicy: .init(truncationIndicator: "…"),
                theme: .none
            )
        )
        let wideCell = String(repeating: "x", count: 120)
        let text = """
        | name | detail |
        | --- | --- |
        | ok | \(wideCell) |
        """

        let lines = engine.render(text: text, isFinal: true)
        XCTAssertTrue(lines.contains(where: { $0.contains("…") }))
        XCTAssertEqual(Set(lines.map { visibleWidth($0) }).count, 1)
    }
}
