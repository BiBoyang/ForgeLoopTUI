import XCTest
@testable import ForgeLoopTUI

final class MarkdownEngineTests: XCTestCase {
    func testPlainTextEngineSplitsByNewline() {
        let engine = PlainTextMarkdownEngine()
        let lines = engine.render(text: "alpha\nbeta\n", isFinal: true)
        XCTAssertEqual(lines, ["alpha", "beta", ""])
    }

    func testStreamingEngineRendersCompleteTable() {
        let engine = StreamingMarkdownEngine()
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
        let engine = StreamingMarkdownEngine()
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

    func testStreamingEngineRendersCodeFenceWithoutParsingNestedTable() {
        let engine = StreamingMarkdownEngine()
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

    func testStreamingEngineFormatsHeadingsQuotesListsAndCodeBlocks() {
        let engine = StreamingMarkdownEngine()
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
        let engine = StreamingMarkdownEngine()
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
        let engine = StreamingMarkdownEngine()
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
        let engine = StreamingMarkdownEngine()
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
}

@MainActor
final class TranscriptRendererMarkdownTests: XCTestCase {
    func testTranscriptRendererRendersTableInFinalOutput() {
        let renderer = TranscriptRenderer()

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
}
