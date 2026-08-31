/// One run of fenced-code text sharing a single theme-resolved style.
///
/// Segments of a highlighted line always partition the input line: their
/// concatenated `text` reproduces the line byte-for-byte. With an empty
/// (`MarkdownStyle.none`) style set the rendered output is therefore
/// byte-identical to unhighlighted output.
struct HighlightSegment: Sendable, Equatable {
    /// The covered source text.
    var text: String
    /// The concrete style, already resolved from a `MarkdownTheme.CodeHighlightStyles` slot.
    var style: MarkdownStyle
}

/// A line-level syntax highlighter for fenced code blocks.
///
/// Highlighters are deterministic pure functions of `(line, continuation,
/// styles)`: they hold no hidden state. Cross-line lexer state (e.g. an
/// unterminated triple-quoted string) is threaded explicitly by the caller
/// through `continuation`, so re-rendering the same fence from its first
/// line always reproduces the same highlighting (the stable-prefix commit
/// contract — rendering stays a pure function of the input text).
///
/// This is a deliberately small tokenizer protocol, not a full grammar:
/// implementations classify each line into the four
/// `MarkdownTheme.CodeHighlightStyles` categories and nothing more.
protocol SyntaxHighlighter: Sendable {
    /// Cross-line tokenizer state, owned and threaded by the caller.
    associatedtype Continuation: Sendable, Equatable
    /// The state at the first content line of a fence.
    static var initialContinuation: Continuation { get }
    /// Highlights one logical line, updating `continuation` for the next.
    static func highlight(
        line: String,
        continuation: inout Continuation,
        styles: MarkdownTheme.CodeHighlightStyles
    ) -> [HighlightSegment]
}

/// A type-erased highlighter bound to one fence: holds the highlighter's
/// continuation state and the theme's code styles for the fence's lifetime.
///
/// The engine creates one instance per fence at the opening delimiter and
/// drops it at the closing delimiter. Because the stable-prefix advance
/// never cuts a fence across render passes (an unclosed fence stays in the
/// unstable region and is re-rendered from its first line), the captured
/// state never leaks across renders — it is recreated deterministically on
/// every pass. Reference semantics are intentional: the continuation must be
/// shared, never copied.
final class FenceHighlighter {
    private let highlightLine: (String) -> [HighlightSegment]

    private init<H: SyntaxHighlighter>(_ type: H.Type, styles: MarkdownTheme.CodeHighlightStyles) {
        var continuation = H.initialContinuation
        highlightLine = { line in
            H.highlight(line: line, continuation: &continuation, styles: styles)
        }
    }

    /// Selects a highlighter for a fence info string (the text after the
    /// opening backticks). Matching is on the first whitespace-separated
    /// token, lowercased; unrecognized languages return `nil` and the fence
    /// content renders as plain text.
    convenience init?(infoString: String, styles: MarkdownTheme.CodeHighlightStyles) {
        let token = infoString
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first
            .map { String($0).lowercased() } ?? ""
        switch token {
        case "python", "py":
            self.init(PythonHighlighter.self, styles: styles)
        case "javascript", "js":
            self.init(JavaScriptHighlighter.self, styles: styles)
        default:
            return nil
        }
    }

    /// Highlights one fence content line, advancing the cross-line state.
    func highlight(line: String) -> [HighlightSegment] {
        highlightLine(line)
    }
}
