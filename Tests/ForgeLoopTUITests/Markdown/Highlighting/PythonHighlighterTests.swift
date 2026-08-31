import XCTest
@testable import ForgeLoopTUI

/// TASK-30 `highlight-python`: the line-level Python tokenizer and its
/// wiring into fence content rendering.
///
/// Tokenizer tests use sentinel styles (bold/italic/faint/underline stand
/// for keyword/string/comment/number) so they never depend on theme colors.
/// Engine tests assert real SGR bytes from `MarkdownTheme.default` and pin
/// the `.none` theme to the pre-highlight byte stream.
final class PythonHighlighterTests: XCTestCase {
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

    private func highlight(_ line: String, continuation: inout PythonHighlighter.Continuation) -> [HighlightSegment] {
        PythonHighlighter.highlight(line: line, continuation: &continuation, styles: styles)
    }

    private func render(_ text: String, options: MarkdownRenderOptions = .init()) -> [String] {
        StreamingMarkdownEngine(options: options).render(text: text, isFinal: true)
    }

    // MARK: - Tokenizer: the four categories

    func testKeywordsStringsCommentsAndNumbers() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("def f(x):", continuation: &continuation),
            [seg("def", keyword), seg(" f(x):", .none)]
        )
        XCTAssertEqual(
            highlight("    return x * 42  # answer", continuation: &continuation),
            [
                seg("    ", .none),
                seg("return", keyword),
                seg(" x * ", .none),
                seg("42", number),
                seg("  ", .none),
                seg("# answer", comment),
            ]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testHashInsideStringIsNotAComment() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("s = \"a # b\"  # real", continuation: &continuation),
            [
                seg("s = ", .none),
                seg("\"a # b\"", string),
                seg("  ", .none),
                seg("# real", comment),
            ]
        )
    }

    func testQuotesInsideCommentAreNotStrings() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("# 他说 \"hi\" 就好", continuation: &continuation),
            [seg("# 他说 \"hi\" 就好", comment)]
        )
        XCTAssertEqual(
            highlight("x = 1  # set \"x\" here", continuation: &continuation),
            [seg("x = ", .none), seg("1", number), seg("  ", .none), seg("# set \"x\" here", comment)]
        )
        XCTAssertEqual(continuation, .none)
    }

    // MARK: - Tokenizer: cross-line triple-quoted strings

    func testTripleQuotedStringAcrossLines() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("s = \"\"\"start", continuation: &continuation),
            [seg("s = ", .none), seg("\"\"\"start", string)]
        )
        XCTAssertEqual(continuation, .inTripleQuotedString(delimiter: "\"\"\""))

        // A `#` inside the continuation is string content, not a comment.
        XCTAssertEqual(
            highlight("middle # not a comment", continuation: &continuation),
            [seg("middle # not a comment", string)]
        )
        // Quotes inside the continuation do not start new strings either.
        XCTAssertEqual(
            highlight("\"quoted\" still string", continuation: &continuation),
            [seg("\"quoted\" still string", string)]
        )
        XCTAssertEqual(continuation, .inTripleQuotedString(delimiter: "\"\"\""))

        XCTAssertEqual(
            highlight("end\"\"\" + \"tail\"", continuation: &continuation),
            [seg("end\"\"\"", string), seg(" + ", .none), seg("\"tail\"", string)]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testSingleQuoteTripleQuotedStringAcrossLines() {
        var continuation = PythonHighlighter.initialContinuation
        _ = highlight("t = '''a", continuation: &continuation)
        XCTAssertEqual(continuation, .inTripleQuotedString(delimiter: "'''"))
        XCTAssertEqual(
            highlight("b'''", continuation: &continuation),
            [seg("b'''", string)]
        )
        XCTAssertEqual(continuation, .none)
    }

    func testSingleLineTripleQuotedStringDoesNotLeakState() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("\"\"\"doc\"\"\"", continuation: &continuation),
            [seg("\"\"\"doc\"\"\"", string)]
        )
        XCTAssertEqual(continuation, .none)
        XCTAssertEqual(
            highlight("x = 1", continuation: &continuation),
            [seg("x = ", .none), seg("1", number)]
        )
    }

    func testUnterminatedSingleQuotedStringEndsAtLineEnd() {
        var continuation = PythonHighlighter.initialContinuation
        // Mid-keystroke streaming state / invalid Python: colors to end of
        // line but must NOT leak cross-line state.
        XCTAssertEqual(
            highlight("s = \"abc", continuation: &continuation),
            [seg("s = ", .none), seg("\"abc", string)]
        )
        XCTAssertEqual(continuation, .none)
        XCTAssertEqual(
            highlight("y = 2", continuation: &continuation),
            [seg("y = ", .none), seg("2", number)]
        )
    }

    func testEscapedQuoteDoesNotCloseString() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("s = \"a\\\"b\" + 'c\\'d'", continuation: &continuation),
            [seg("s = ", .none), seg("\"a\\\"b\"", string), seg(" + ", .none), seg("'c\\'d'", string)]
        )
        XCTAssertEqual(continuation, .none)
    }

    // MARK: - Tokenizer: prefixes, numbers, partition invariant

    func testPrefixedStrings() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("a = r\"raw\\n\" + f\"{x}\" + b\"\\x00\" + RF'y'", continuation: &continuation),
            [
                seg("a = ", .none),
                seg("r\"raw\\n\"", string),
                seg(" + ", .none),
                seg("f\"{x}\"", string),
                seg(" + ", .none),
                seg("b\"\\x00\"", string),
                seg(" + ", .none),
                seg("RF'y'", string),
            ]
        )
    }

    func testNumberForms() {
        var continuation = PythonHighlighter.initialContinuation
        XCTAssertEqual(
            highlight("vals = [0xFF, 1_000, 3.14, 1e-3, 2e8, 10j, .5]", continuation: &continuation),
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
                seg("10j", number),
                seg(", ", .none),
                seg(".5", number),
                seg("]", .none),
            ]
        )
    }

    func testSegmentsAlwaysPartitionTheInputLine() {
        let trickyLines = [
            "",
            "   ",
            "# just a comment",
            "def f(x: int = 0) -> str:",
            "s = \"a # b\"  # real",
            "s = \"\"\"start",
            "middle # inside triple",
            "end\"\"\" + 'tail'",
            "r\"\\\"",  // invalid Python (raw string ending in a backslash) must still partition
            "x = 1e-3 + 0xFF_A0 + .5 + 10j",
            "print(f\"{x:.2f}\")",
            "中文字符 = \"串\"  # 注释",
        ]
        var continuation = PythonHighlighter.initialContinuation
        for line in trickyLines {
            let segments = highlight(line, continuation: &continuation)
            XCTAssertEqual(segments.map(\.text).joined(), line, "segments must partition: \(line)")
        }
    }

    // MARK: - Engine wiring

    func testEngineColorsPythonFenceContentWithDefaultTheme() {
        let text = "```python\ndef f():\n    return \"hi\"  # 42\n```"
        XCTAssertEqual(
            render(text),
            [
                "\(esc)[2m┌─ code\(esc)[0m \(esc)[2;3mpython\(esc)[0m",
                "│ \(esc)[33mdef\(esc)[0m f():",
                "│     \(esc)[33mreturn\(esc)[0m \(esc)[32m\"hi\"\(esc)[0m  \(esc)[2m# 42\(esc)[0m",
                "\(esc)[2m└─ end code\(esc)[0m",
            ]
        )
    }

    func testEngineMatchesPyAliasAndCaseInsensitively() {
        XCTAssertEqual(
            render("```py\nreturn 1\n```"),
            [
                "\(esc)[2m┌─ code\(esc)[0m \(esc)[2;3mpy\(esc)[0m",
                "│ \(esc)[33mreturn\(esc)[0m \(esc)[36m1\(esc)[0m",
                "\(esc)[2m└─ end code\(esc)[0m",
            ]
        )
        XCTAssertEqual(
            render("```Python\nreturn 1\n```")[1],
            "│ \(esc)[33mreturn\(esc)[0m \(esc)[36m1\(esc)[0m"
        )
    }

    func testNoneThemeKeepsPreHighlightByteStream() {
        let text = "```python\ndef f():\n    return \"hi\"  # 42\n```"
        XCTAssertEqual(
            render(text, options: .init(theme: .none)),
            [
                "┌─ code python",
                "│ def f():",
                "│     return \"hi\"  # 42",
                "└─ end code",
            ]
        )
    }

    func testUnrecognizedLanguageFallsBackToPlainText() {
        let text = "```ruby\nputs \"hi\"  # x\n```"
        XCTAssertEqual(
            render(text),
            [
                "\(esc)[2m┌─ code\(esc)[0m \(esc)[2;3mruby\(esc)[0m",
                "│ puts \"hi\"  # x",
                "\(esc)[2m└─ end code\(esc)[0m",
            ]
        )
        // No info string: no highlighter either, even for Python-looking code.
        XCTAssertEqual(
            render("```\nreturn 1\n```"),
            [
                "\(esc)[2m┌─ code\(esc)[0m",
                "│ return 1",
                "\(esc)[2m└─ end code\(esc)[0m",
            ]
        )
    }

    func testStreamingPythonFenceConvergesToStaticRender() {
        // A fence with a cross-line docstring, replayed character by
        // character: the unclosed fence stays in the unstable region and is
        // re-rendered from its first line each pass, so the continuation
        // state must rebuild identically every time.
        let sample = """
        ```python
        class A:
            \"\"\"doc
        spans # lines
            \"\"\"
            def m(self):
                return 1
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
