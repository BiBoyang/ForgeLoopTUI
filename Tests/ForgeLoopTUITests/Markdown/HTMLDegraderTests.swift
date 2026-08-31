import XCTest
@testable import ForgeLoopTUI

/// TASK-25 `html-degrade`: HTML-bearing lines degrade to readable text
/// (tags stripped / attributes dropped / block tags break lines / entities
/// decoded), while tag-free lines — including fenced code — stay
/// byte-identical.
final class HTMLDegraderTests: XCTestCase {
    private func degrade(_ line: String) -> [String] {
        HTMLDegrader.degrade(line)
    }

    private func render(_ text: String, theme: MarkdownTheme = .default) -> [String] {
        StreamingMarkdownEngine(options: MarkdownRenderOptions(theme: theme)).render(text: text, isFinal: true)
    }

    // MARK: - Degrader unit behavior

    func testTagFreeLinePassesThroughByteIdentical() {
        XCTAssertEqual(degrade("plain text"), ["plain text"])
        XCTAssertEqual(degrade(""), [""])
        // Entity without a tag is NOT decoded (non-degraded path unchanged).
        XCTAssertEqual(degrade("AT&amp;T &nbsp; stays"), ["AT&amp;T &nbsp; stays"])
        // Escaped entity never re-parses as a tag.
        XCTAssertEqual(degrade("&lt;div&gt; hello"), ["&lt;div&gt; hello"])
        // '<' that does not start a well-formed tag stays literal.
        XCTAssertEqual(degrade("a < b"), ["a < b"])
        XCTAssertEqual(degrade("unclosed <div"), ["unclosed <div"])
        XCTAssertEqual(degrade("comment <!-- not a tag"), ["comment <!-- not a tag"])
    }

    func testAttributeStringsNeverLeak() {
        let line = #"<div style="border: 1px solid #ddd; border-radius: 8px;" align="center">body</div>"#
        let result = degrade(line)
        XCTAssertEqual(result, ["body"])
        for segment in result {
            XCTAssertFalse(segment.contains("style"))
            XCTAssertFalse(segment.contains("border"))
            XCTAssertFalse(segment.contains("<"))
        }
    }

    func testImgTagWithAttributesIsFullyDropped() {
        let line = #"<img src="https://via.placeholder.com/400x200" alt="图表" width="400" height="200" />"#
        XCTAssertEqual(degrade(line), [])
        XCTAssertFalse(line.contains("placeholder") == false) // sanity: source really had attrs
    }

    func testBlockLevelTagsBreakLines() {
        XCTAssertEqual(degrade("<p>one</p><p>two</p>"), ["one", "two"])
        XCTAssertEqual(degrade("a<br>b"), ["a", "b"])
        XCTAssertEqual(degrade("<h4>title</h4>"), ["title"])
        XCTAssertEqual(degrade("<div>outer</div>"), ["outer"])
        // Tag-only lines vanish; consecutive breaks collapse.
        XCTAssertEqual(degrade("<details>"), [])
        XCTAssertEqual(degrade("<ul><li>x</li><li>y</li></ul>"), ["x", "y"])
        XCTAssertEqual(degrade("</p><p>between</p><p>"), ["between"])
    }

    func testSummaryContentSurvivesAsPrefixLine() {
        XCTAssertEqual(
            degrade("<summary>🔍 查看敏感配置（点击展开）</summary>"),
            ["🔍 查看敏感配置（点击展开）"]
        )
    }

    func testInlineTagsStripKeepingText() {
        XCTAssertEqual(degrade("press <kbd>Ctrl</kbd> + <kbd>C</kbd>"), ["press Ctrl + C"])
        XCTAssertEqual(degrade("<b>bold</b> and <em>italic</em>"), ["bold and italic"])
        XCTAssertEqual(
            degrade(#"<span style="color: orange; font-weight: bold;">网络延迟</span> 后续"#),
            ["网络延迟 后续"]
        )
    }

    // MARK: - TASK-32: cell separator

    func testCellTagsSeparateWithSingleSpace() {
        XCTAssertEqual(
            degrade("<td>DB_HOST</td><td>192.168.1.53</td><td>仅运维</td>"),
            ["DB_HOST 192.168.1.53 仅运维"]
        )
        XCTAssertEqual(degrade("<th>KEY</th><th>VALUE</th>"), ["KEY VALUE"])
        // A closing tag alone also separates.
        XCTAssertEqual(degrade("a</td>b"), ["a b"])
        // Case-insensitive, attributes still dropped.
        XCTAssertEqual(degrade(#"<TD class="x">a</TD><td>b</td>"#), ["a b"])
    }

    func testCellSeparatorNeverProducesExtraSpaces() {
        // Source spacing next to a cell tag collapses into the one separator.
        XCTAssertEqual(degrade("<td>a</td> <td>b</td>"), ["a b"])
        XCTAssertEqual(degrade("<td>a</td>  <td>b</td>"), ["a b"])
        // Lone cell tags at the edges leave no stray spaces after trimming.
        XCTAssertEqual(degrade("<td>a</td>"), ["a"])
        XCTAssertEqual(degrade("<td>only"), ["only"])
    }

    func testInlineTdCombinesWithBlockLevelTr() {
        // td stays inline within the row; tr still breaks rows onto lines.
        XCTAssertEqual(
            degrade("<tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr>"),
            ["a b", "c d"]
        )
        XCTAssertEqual(
            degrade("<table><tr><th>K</th><th>V</th></tr><tr><td>x</td><td>y</td></tr></table>"),
            ["K V", "x y"]
        )
    }

    func testEntitiesDecodeOnDegradedLines() {
        XCTAssertEqual(degrade("<p>a &amp; b</p>"), ["a & b"])
        // Trailing &nbsp; decodes to a space, then segment trimming drops it.
        XCTAssertEqual(degrade("<code>&lt;tag&gt; &quot;q&#39;&nbsp;</code>"), ["<tag> \"q'"])
        // Single pass: &amp;lt; → "&lt;", not "<".
        XCTAssertEqual(degrade("<p>&amp;lt;</p>"), ["&lt;"])
    }

    func testCaseInsensitiveTagNames() {
        XCTAssertEqual(degrade("<DIV>x</DIV>"), ["x"])
        XCTAssertEqual(degrade("<Br />y"), ["y"])
    }

    func testCodeSpanContentIsNotDegraded() {
        XCTAssertEqual(degrade("use `<div>` tags"), ["use `<div>` tags"])
        // Code span protects only its own span; a real tag elsewhere degrades.
        XCTAssertEqual(degrade("`<b>` then <br> break"), ["`<b>` then", "break"])
    }

    // MARK: - Engine wiring

    func testEngineDegradesHtmlBlock() {
        let rendered = render("""
        <div style="padding: 16px;">
          <h4>项目进度总览</h4>
          <p>整体进度: <strong>72%</strong></p>
          <br>
          <p>⏱ 已用时间: 34天 / 预计 47天</p>
        </div>
        """)
        XCTAssertEqual(rendered, [
            "项目进度总览",
            "整体进度: 72%",
            "⏱ 已用时间: 34天 / 预计 47天",
        ])
    }

    func testEngineDegradesDetailsSummaryBlock() {
        let rendered = render("""
        <details>
        <summary>🔍 查看敏感配置（点击展开）</summary>

        <table border="1">
          <tr><th>KEY</th><th>VALUE</th></tr>
          <tr><td>DB_HOST</td><td>192.168.1.53</td></tr>
        </table>

        > ⚠️ 请勿泄露此信息
        </details>
        """)
        XCTAssertEqual(rendered, [
            "🔍 查看敏感配置（点击展开）",
            "", // source blank lines between tags pass through
            "KEY VALUE", // TASK-32: th cells separate with a single space
            "DB_HOST 192.168.1.53",
            "",
            "\u{1B}[2m│\u{1B}[0m ⚠️ 请勿泄露此信息", // inner markdown still renders (quote chrome)
        ])
    }

    func testFencedCodeIsNotDegraded() {
        let rendered = render("""
        ```html
        <div class="raw">&amp; stays</div>
        ```
        """)
        XCTAssertEqual(rendered, [
            "\u{1B}[2m┌─\u{1B}[0m \u{1B}[2;3mhtml\u{1B}[0m",
            "│ <div class=\"raw\">&amp; stays</div>",
            "\u{1B}[2m└─\u{1B}[0m",
        ])
    }

    func testNoneThemeNonDegradedPathsUnchanged() {
        // Tag-free markdown renders byte-identical under .none (and the
        // degrade wiring is invisible on such lines under any theme).
        let text = "# Title\n\n> quote\n\n- item"
        XCTAssertEqual(
            render(text, theme: .none),
            ["█ Title", "", "│ quote", "", "• item"]
        )
    }

    func testDegradedSegmentsStillGetInlineFormattingAndChrome() {
        // Degraded text flows through the full inline + chrome pipeline.
        let rendered = render("<p>bold **works** and `code`</p>\n<br>\n> quoted **after** degrade")
        XCTAssertEqual(rendered, [
            "bold \u{1B}[1mworks\u{1B}[0m and \u{1B}[7mcode\u{1B}[0m",
            "\u{1B}[2m│\u{1B}[0m quoted \u{1B}[1mafter\u{1B}[0m degrade",
        ])
    }

    func testDegradedHtmlStreamingConvergesToStaticRender() {
        let sample = """
        <details>
        <summary>title</summary>
        <table><tr><td>a</td><td>b</td></tr></table>
        </details>
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

    // MARK: - Multi-line tags (attributes wrapped across lines)

    func testMultiLineImgAttributesNeverLeak() {
        let rendered = render("""
        <div align="center">
          <img src="https://via.placeholder.com/400x200?text=图表"
               alt="模拟图表"
               width="400"
               height="200" />
          <br>
          <span style="color:gray;">▲ 图1: 占位</span>
        </div>
        """)
        XCTAssertEqual(rendered, ["▲ 图1: 占位"])
        for line in rendered {
            XCTAssertFalse(line.contains("src"))
            XCTAssertFalse(line.contains("alt"))
            XCTAssertFalse(line.contains("width"))
        }
    }

    func testMultiLineTagStreamingConvergesToStaticRender() {
        // The stable-prefix retreat holds an unclosed multi-line tag back
        // until it closes, so every chunking converges to the one-shot render.
        let sample = """
        intro
        <img src="https://example.com/a.png"
             alt="pic"
             title="t" />
        outro
        """
        let staticRender = render(sample)
        for chunkSize in [1, 2, 3, 5, 11] {
            let streaming = StreamingMarkdownEngine()
            var accumulated = ""
            var last: [String] = []
            for start in stride(from: 0, to: sample.count, by: chunkSize) {
                let end = min(start + chunkSize, sample.count)
                accumulated += String(sample[sample.index(sample.startIndex, offsetBy: start)..<sample.index(sample.startIndex, offsetBy: end)])
                last = streaming.render(text: accumulated, isFinal: false)
            }
            last = streaming.render(text: accumulated, isFinal: true)
            XCTAssertEqual(last, staticRender, "chunk size \(chunkSize)")
        }
    }

    func testNeverClosedTagKeepsRawLines() {
        // No '>' ever arrives: the pass must not swallow the lines.
        let rendered = render("before\n<div class=\"x\"\nstill attrs\nafter-no-close")
        XCTAssertEqual(rendered, [
            "before",
            "<div class=\"x\"",
            "still attrs",
            "after-no-close",
        ])
    }

    func testUnclosedTagHoldsBackStablePrefix() {
        // While the tag is unclosed mid-stream, its opening line must stay in
        // the unstable region (stableRenderedLineCount stops before it).
        let engine = StreamingMarkdownEngine()
        let frame1 = "intro\n<img src=\"https://example.com/a.png\"\n"
        let lines1 = engine.render(text: frame1, isFinal: false)
        // The bare URL inside the raw passthrough line is OSC 8 hyperlinked
        // (default theme); the line itself is otherwise unchanged.
        XCTAssertEqual(lines1, ["intro", "<img src=\"\u{1B}]8;;https://example.com/a.png\u{1B}\\\u{1B}[4mhttps://example.com/a.png\u{1B}[0m\u{1B}]8;;\u{1B}\\\"", ""])
        // intro is stable; the tag opener is not.
        XCTAssertEqual(engine.stableRenderedLineCount, 1)
    }
}
