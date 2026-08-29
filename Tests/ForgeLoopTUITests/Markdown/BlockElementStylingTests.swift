import XCTest
@testable import ForgeLoopTUI

/// TASK-24 `block-element-styling`: the default theme now styles block chrome
/// (headings, table header/borders, quote bars, fence borders + language
/// labels) with SGR, while `.none` keeps the pre-theme byte stream.
///
/// Review red line under test: styling only ever wraps whole lines / whole
/// (already padded + truncated) cells — truncation must never cut through an
/// SGR sequence, or the style leaks into subsequent output.
final class BlockElementStylingTests: XCTestCase {
    private let esc = "\u{1B}"

    private func render(_ text: String, options: MarkdownRenderOptions = .init()) -> [String] {
        StreamingMarkdownEngine(options: options).render(text: text, isFinal: true)
    }

    // MARK: - Headings

    func testDefaultThemeHeadingBytesPerLevel() {
        XCTAssertEqual(render("# One"), ["\(esc)[1;94m█ One\(esc)[0m"])
        XCTAssertEqual(render("## Two"), ["\(esc)[1;34m▓ Two\(esc)[0m"])
        XCTAssertEqual(render("### Three"), ["\(esc)[1;36m▶ Three\(esc)[0m"])
        XCTAssertEqual(render("#### Four"), ["\(esc)[1m▹ Four\(esc)[0m"])
        XCTAssertEqual(render("##### Five"), ["\(esc)[1;90m• Five\(esc)[0m"])
        XCTAssertEqual(render("###### Six"), ["\(esc)[90m· Six\(esc)[0m"])
    }

    func testHeadingStyleSurvivesInlineSpans() {
        // Bold span inside a heading resets all attributes at its ESC[0m;
        // the heading style must be re-opened so the rest of the title keeps
        // the heading color.
        XCTAssertEqual(
            render("# Hello **world** tail"),
            ["\(esc)[1;94m█ Hello \(esc)[1mworld\(esc)[0m\(esc)[1;94m tail\(esc)[0m"]
        )
    }

    // MARK: - Blockquote bars

    func testDefaultThemeStylesQuoteBarsOnly() {
        XCTAssertEqual(render("> note"), ["\(esc)[2m│\(esc)[0m note"])
        XCTAssertEqual(render(">> deep"), ["\(esc)[2m│\(esc)[0m \(esc)[2m│\(esc)[0m deep"])
        // Indented quote keeps its plain indentation; empty quote emits only bars.
        XCTAssertEqual(render("  > indented"), ["  \(esc)[2m│\(esc)[0m indented"])
        XCTAssertEqual(render(">"), ["\(esc)[2m│\(esc)[0m"])
    }

    func testQuoteWithLinkContentIsNotCorruptedByChromeStyling() {
        // Styling runs after inline parsing: the `[` inside `ESC[2m` must not
        // be mistaken for link syntax (regression guard for the styling order).
        XCTAssertEqual(
            render("> see [docs](https://x.example) here"),
            ["\(esc)[2m│\(esc)[0m see \(esc)[4mdocs\(esc)[0m \(esc)[2m(https://x.example)\(esc)[0m here"]
        )
    }

    // MARK: - Code fences

    func testDefaultThemeStylesFenceBorderAndLanguageLabel() {
        XCTAssertEqual(
            render("```swift\nlet x = 1\n```"),
            [
                "\(esc)[2m┌─ code\(esc)[0m \(esc)[2;3mswift\(esc)[0m",
                "│ let x = 1",
                "\(esc)[2m└─ end code\(esc)[0m",
            ]
        )
        // No language label: border only.
        XCTAssertEqual(
            render("```\ntilde\n```"),
            [
                "\(esc)[2m┌─ code\(esc)[0m",
                "│ tilde",
                "\(esc)[2m└─ end code\(esc)[0m",
            ]
        )
    }

    // MARK: - Tables

    func testDefaultThemeTableGoldenBytes() {
        XCTAssertEqual(
            render("| a | b |\n| --- | --- |\n| 1 | 2 |"),
            [
                "\(esc)[2m┌────────┬────────┐\(esc)[0m",
                "\(esc)[2m│\(esc)[0m \(esc)[1ma     \(esc)[0m \(esc)[2m│\(esc)[0m \(esc)[1mb     \(esc)[0m \(esc)[2m│\(esc)[0m",
                "\(esc)[2m├────────┼────────┤\(esc)[0m",
                "\(esc)[2m│\(esc)[0m 1      \(esc)[2m│\(esc)[0m 2      \(esc)[2m│\(esc)[0m",
                "\(esc)[2m└────────┴────────┘\(esc)[0m",
            ]
        )
    }

    func testColoredTableRowsStayWidthAligned() {
        // ANSI-aware width: every styled row must measure the same visible
        // width as its plain counterpart (and all rows in a table equal).
        let text = "| 名称 | 值 |\n| --- | --- |\n| 测试 | 甲 |"
        let styled = render(text)
        let plain = render(text, options: .init(theme: .none))
        XCTAssertEqual(styled.count, plain.count)
        var widths: Set<Int> = []
        for (styledLine, plainLine) in zip(styled, plain) {
            XCTAssertEqual(visibleWidth(styledLine), visibleWidth(plainLine))
            widths.insert(visibleWidth(styledLine))
        }
        XCTAssertEqual(widths.count, 1, "table rows must share one visible width")
    }

    func testTruncationNeverCutsSGRSequences() {
        // Red-line test: a header cell that truncates under the styled theme.
        // The `…` indicator must sit INSIDE the bold wrap, and every styled
        // line must strip back to exactly its plain counterpart — a cut SGR
        // sequence would leave escape fragments behind.
        let policy = TableRenderPolicy(
            maxRenderedWidth: 40,
            minColumnWidth: 4,
            maxColumnWidth: 6,
            truncationIndicator: "…",
            overflowBehavior: .compactThenTruncateThenDegrade,
            wideTableStrategy: .alwaysBox
        )
        let text = "| aaaaaaaaaaaa | bbbbbbbbbbbb |\n| --- | --- |\n| ok | fine |"
        let styled = render(text, options: .init(tablePolicy: policy))
        let plain = render(text, options: .init(tablePolicy: policy, theme: .none))

        XCTAssertEqual(
            styled,
            [
                "\(esc)[2m┌────────┬────────┐\(esc)[0m",
                "\(esc)[2m│\(esc)[0m \(esc)[1maaaaa…\(esc)[0m \(esc)[2m│\(esc)[0m \(esc)[1mbbbbb…\(esc)[0m \(esc)[2m│\(esc)[0m",
                "\(esc)[2m├────────┼────────┤\(esc)[0m",
                "\(esc)[2m│\(esc)[0m ok     \(esc)[2m│\(esc)[0m fine   \(esc)[2m│\(esc)[0m",
                "\(esc)[2m└────────┴────────┘\(esc)[0m",
            ]
        )
        // Complete-sequences invariant: stripping ANSI reproduces the plain
        // byte stream line-for-line.
        XCTAssertEqual(styled.count, plain.count)
        for (styledLine, plainLine) in zip(styled, plain) {
            XCTAssertEqual(ansiStripped(styledLine), plainLine)
            XCTAssertEqual(visibleWidth(styledLine), visibleWidth(plainLine))
        }
    }

    // MARK: - Whole-document invariants

    func testStyledDocumentStripsBackToPlainByteStream() {
        // For mixed content (headings, quotes, fences, a truncating wide
        // table, task lists, inline spans), stripping ANSI from the default-
        // theme render must equal the stripped `.none` render: chrome styling
        // adds only complete SGR sequences and never drops or reorders
        // visible text. (`.none` keeps its own inline SGR — bold/links —
        // which is why both sides are stripped before comparing.)
        let wideCell = String(repeating: "x", count: 60)
        let sample = """
        # Title

        > quote with **bold** and [link](https://example.com)

        ```python
        print("hi")
        ```

        | head | data |
        | --- | --- |
        | \(wideCell) | ok |

        - [x] done
        - `code span`
        """
        let styled = render(sample)
        let plain = render(sample, options: .init(theme: .none))
        XCTAssertEqual(styled.count, plain.count)
        for (styledLine, plainLine) in zip(styled, plain) {
            XCTAssertEqual(ansiStripped(styledLine), ansiStripped(plainLine))
            XCTAssertEqual(visibleWidth(styledLine), visibleWidth(plainLine))
        }
    }

    func testStreamingUnderDefaultThemeConvergesToStaticRender() {
        // Theme styling participates in the streaming path deterministically:
        // replaying the document in chunks must converge to the one-shot
        // final render, exactly like the unstyled engine.
        let sample = """
        # Heading

        > quoted

        ```swift
        let x = 1
        ```

        | a | b |
        | --- | --- |
        | 1 | 2 |
        """
        let staticRender = render(sample)
        let streaming = StreamingMarkdownEngine()
        var accumulated = ""
        var last: [String] = []
        for character in sample {
            accumulated.append(character)
            last = streaming.render(text: accumulated, isFinal: false)
        }
        last = streaming.render(text: accumulated, isFinal: true)
        XCTAssertEqual(last, staticRender)
    }

    // MARK: - Out-of-scope chrome stays unstyled

    func testTaskMarkersAndThematicBreakRemainUnstyled() {
        // TASK-24 wires headings/tables/quotes/fence borders only; task-list
        // markers and thematic breaks have theme slots but no wiring yet.
        XCTAssertEqual(render("- [x] done"), ["☑ done"])
        XCTAssertEqual(render("- [ ] todo"), ["☐ todo"])
        XCTAssertEqual(render("---"), [String(repeating: "─", count: 24)])
        XCTAssertEqual(
            render("```swift\ncode\n```").dropFirst().dropLast(),
            ["│ code"]
        )
    }
}
