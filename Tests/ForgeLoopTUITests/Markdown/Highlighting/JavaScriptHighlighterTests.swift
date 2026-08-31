import XCTest
@testable import ForgeLoopTUI

/// TASK-31 `highlight-javascript`: the line-level JavaScript tokenizer and
/// its wiring into fence content rendering.
///
/// Tokenizer tests use sentinel styles (bold/italic/faint/underline stand
/// for keyword/string/comment/number) so they never depend on theme colors.
/// Engine tests assert real SGR bytes from `MarkdownTheme.default` and pin
/// the `.none` theme to the pre-highlight byte stream.
final class JavaScriptHighlighterTests: XCTestCase {
    private let esc = "\u{1B}"

    // Sentinel slot styles: keyword/string/comment/number.
    private let keyword = MarkdownStyle([.bold])
    private let string = MarkdownStyle([.italic])
    private let comment = MarkdownStyle([.faint])
    private let number = MarkdownStyle([.underline])
    private let plain = MarkdownStyle.none

    private var styles: MarkdownTheme.CodeHighlightStyles {
        MarkdownTheme.CodeHighlightStyles(keyword: keyword, string: string, comment: comment, number: number)
    }

    private func seg(_ text: String, _ style: MarkdownStyle) -> HighlightSegment {
        HighlightSegment(text: text, style: style)
    }

    private func highlight(_ line: String, continuation: inout JavaScriptHighlighter.Continuation) -> [HighlightSegment] {
        JavaScriptHighlighter.highlight(line: line, continuation: &continuation, styles: styles)
    }

    private func render(_ text: String, options: MarkdownRenderOptions = .init()) -> [String] {
        StreamingMarkdownEngine(options: options).render(text: text, isFinal: true)
    }

    // MARK: - Tokenizer: the four categories

    func testKeywordsStringsCommentsAndNumbers() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("const add = (a, b) => {", continuation: &continuation),
            [seg("const", keyword), seg(" add = (a, b) => {", .none)]
        )
        XCTAssertEqual(
            highlight("  return a + 42; // answer", continuation: &continuation),
            [
                seg("  ", .none),
                seg("return", keyword),
                seg(" a + ", .none),
                seg("42", number),
                seg("; ", .none),
                seg("// answer", comment),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testSlashSlashInsideStringIsNotAComment() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("const url = \"https://example.com\"; // real", continuation: &continuation),
            [
                seg("const", keyword),
                seg(" url = ", .none),
                seg("\"https://example.com\"", string),
                seg("; ", .none),
                seg("// real", comment),
            ]
        )
    }

    func testQuotesInsideCommentAreNotStrings() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("// 他说 \"hi\" 就好", continuation: &continuation),
            [seg("// 他说 \"hi\" 就好", comment)]
        )
        XCTAssertEqual(
            highlight("let x = 1; // set \"x\" here", continuation: &continuation),
            [seg("let", keyword), seg(" x = ", .none), seg("1", number), seg("; ", .none), seg("// set \"x\" here", comment)]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testDivisionAndRegexLikeTextStayPlain() {
        var continuation = JavaScriptHighlighter.initialContinuation
        // `/` starts a comment only when doubled or starred; a regex-looking
        // literal is not recognized and simply stays plain (documented
        // approximation), so nothing here may start a comment.
        XCTAssertEqual(
            highlight("const re = /a\\/b/; let q = a / b;", continuation: &continuation),
            [
                seg("const", keyword),
                seg(" re = /a\\/b/; ", .none),
                seg("let", keyword),
                seg(" q = a / b;", .none),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    // MARK: - Tokenizer: cross-line block comments

    func testBlockCommentAcrossLines() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("/* start", continuation: &continuation),
            [seg("/* start", comment)]
        )
        XCTAssertEqual(continuation, .inBlockComment)

        // Quotes and `//` inside the continuation are comment content.
        XCTAssertEqual(
            highlight("middle \"quoted\" // nested", continuation: &continuation),
            [seg("middle \"quoted\" // nested", comment)]
        )
        XCTAssertEqual(continuation, .inBlockComment)

        XCTAssertEqual(
            highlight("end */ const x = 1;", continuation: &continuation),
            [
                seg("end */", comment),
                seg(" ", .none),
                seg("const", keyword),
                seg(" x = ", .none),
                seg("1", number),
                seg(";", .none),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testSingleLineBlockCommentDoesNotLeakState() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("/* ok */ let a = 1;", continuation: &continuation),
            [
                seg("/* ok */", comment),
                seg(" ", .none),
                seg("let", keyword),
                seg(" a = ", .none),
                seg("1", number),
                seg(";", .none),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    // MARK: - Tokenizer: strings and template literals

    func testTemplateLiteralAcrossLines() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("const t = `start", continuation: &continuation),
            [seg("const", keyword), seg(" t = ", .none), seg("`start", string)]
        )
        XCTAssertEqual(continuation, .inTemplateLiteral)

        // A `//` inside the continuation is string content, not a comment.
        XCTAssertEqual(
            highlight("middle // not a comment", continuation: &continuation),
            [seg("middle // not a comment", string)]
        )
        // Quotes inside the continuation do not start new strings either.
        XCTAssertEqual(
            highlight("\"quoted\" still string", continuation: &continuation),
            [seg("\"quoted\" still string", string)]
        )
        XCTAssertEqual(continuation, .inTemplateLiteral)

        XCTAssertEqual(
            highlight("end` + \"tail\"", continuation: &continuation),
            [seg("end`", string), seg(" + ", .none), seg("\"tail\"", string)]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testTemplateInterpolationIsOneStringSegment() {
        // Pinned approximation: `${…}` is not parsed — the whole template
        // literal, interpolation included, is a single string segment.
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("const s = `a ${b + c} d`;", continuation: &continuation),
            [
                seg("const", keyword),
                seg(" s = ", .none),
                seg("`a ${b + c} d`", string),
                seg(";", .none),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testUnterminatedSingleQuotedStringEndsAtLineEnd() {
        var continuation = JavaScriptHighlighter.initialContinuation
        // Mid-keystroke streaming state / invalid JS: colors to end of line
        // but must NOT leak cross-line state.
        XCTAssertEqual(
            highlight("const s = \"abc", continuation: &continuation),
            [seg("const", keyword), seg(" s = ", .none), seg("\"abc", string)]
        )
        XCTAssertEqual(continuation, .none)
        XCTAssertEqual(
            highlight("let y = 2;", continuation: &continuation),
            [seg("let", keyword), seg(" y = ", .none), seg("2", number), seg(";", .none)]
        )
    }

    func testEscapedQuoteDoesNotCloseString() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("const s = \"a\\\"b\" + 'c\\'d' + `e\\`f`;", continuation: &continuation),
            [
                seg("const", keyword),
                seg(" s = ", .none),
                seg("\"a\\\"b\"", string),
                seg(" + ", .none),
                seg("'c\\'d'", string),
                seg(" + ", .none),
                seg("`e\\`f`", string),
                seg(";", .none),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    // MARK: - Tokenizer: numbers, partition invariant

    func testNumberForms() {
        var continuation = JavaScriptHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("vals = [0xFF, 1_000, 3.14, 1e-3, 2e8, 10n, .5, 0b101, 0o17]", continuation: &continuation),
            [
                seg("vals = [", .none),
                seg("0xFF", number),
                seg(", ", .none),
                seg("1_000", number),
                seg(", ", .none),
                seg("3.14", number),
                seg(", ", .none),
                seg("1e-3", number),
                seg(", ", .none),
                seg("2e8", number),
                seg(", ", .none),
                seg("10n", number),
                seg(", ", .none),
                seg(".5", number),
                seg(", ", .none),
                seg("0b101", number),
                seg(", ", .none),
                seg("0o17", number),
                seg("]", .none),
            ]
        )
    }

    func testSegmentsAlwaysPartitionTheInputLine() {
        let trickyLines = [
            "",
            "   ",
            "// just a comment",
            "/* half",
            "still comment */",
            "const re = /a\\/b/;",
            "`${x} // still string`",
            "x = 1e-3 + 0xFF_A0 + .5 + 10n",
            "中文字符 = \"串\" // 注释",
        ]
        var continuation = JavaScriptHighlighter.initialContinuation
        for line in trickyLines {
            let segments = highlight(line, continuation: &continuation)
            XCTAssertEqual(segments.map(\.text).joined(), line, "segments must partition: \(line)")
        }
    }

    // MARK: - Engine wiring

    func testEngineColorsJavaScriptFenceContentWithDefaultTheme() {
        let text = "```javascript\nconst add = (a, b) => {\n  return a + b; // sum\n};\n```"
        XCTAssertEqual(
            render(text),
            [
                "\(esc)[2m┌─\(esc)[0m \(esc)[2;3mjavascript\(esc)[0m",
                "│ \(esc)[33mconst\(esc)[0m add = (a, b) => {",
                "│   \(esc)[33mreturn\(esc)[0m a + b; \(esc)[2m// sum\(esc)[0m",
                "│ };",
                "\(esc)[2m└─\(esc)[0m",
            ]
        )
    }

    func testEngineMatchesJsAliasAndCaseInsensitively() {
        XCTAssertEqual(
            render("```js\nreturn 1\n```"),
            [
                "\(esc)[2m┌─\(esc)[0m \(esc)[2;3mjs\(esc)[0m",
                "│ \(esc)[33mreturn\(esc)[0m \(esc)[36m1\(esc)[0m",
                "\(esc)[2m└─\(esc)[0m",
            ]
        )
        XCTAssertEqual(
            render("```JavaScript\nreturn 1\n```")[1],
            "│ \(esc)[33mreturn\(esc)[0m \(esc)[36m1\(esc)[0m"
        )
    }

    func testNoneThemeKeepsPreHighlightByteStream() {
        let text = "```javascript\nconst add = (a, b) => {\n  return a + b; // sum\n};\n```"
        XCTAssertEqual(
            render(text, options: .init(theme: .none)),
            [
                "┌─ javascript",
                "│ const add = (a, b) => {",
                "│   return a + b; // sum",
                "│ };",
                "└─",
            ]
        )
    }

    func testUnrecognizedLanguageFallsBackToPlainText() {
        // `typescript` is deliberately not aliased: only `javascript`/`js`
        // select the JavaScript highlighter.
        let text = "```typescript\nconst x: number = 1;\n```"
        XCTAssertEqual(
            render(text),
            [
                "\(esc)[2m┌─\(esc)[0m \(esc)[2;3mtypescript\(esc)[0m",
                "│ const x: number = 1;",
                "\(esc)[2m└─\(esc)[0m",
            ]
        )
    }

    func testStreamingJavaScriptFenceConvergesToStaticRender() {
        // A fence with a cross-line block comment and a cross-line template
        // literal, replayed character by character: the unclosed fence stays
        // in the unstable region and is re-rendered from its first line each
        // pass, so the continuation state must rebuild identically every time.
        let sample = """
        ```javascript
        /* header
           banner */
        const t = `line one
        line ${two}`;
        ```
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
}
