import Foundation

/// Degrades HTML-bearing markdown lines to readable plain text.
///
/// Pure functions over a data-driven tag table — no state, no environment
/// probing, so rendering stays a deterministic function of the input. Lines
/// without HTML tags pass through byte-identical (no entity decoding either),
/// keeping the non-degraded paths of the engine unchanged.
///
/// Behavior:
/// - Block-level tags (`div`, `table`, `tr`, `p`, `ul`, `li`, `details`,
///   `summary`, `h1`–`h6`, `br`) become line breaks; consecutive breaks
///   collapse (empty segments are dropped).
/// - Table cell tags (`td`, `th`, opening and closing) degrade to a single
///   separating space, so adjacent cells stay readable
///   (`DB_HOST 192.168.1.53` instead of `DB_HOST192.168.1.53`); runs of
///   whitespace collapse and segment ends trim in `postProcess`.
/// - Every other well-formed tag (e.g. `span`, `kbd`, `img`) is removed
///   together with its attribute string — attributes never leak.
/// - `<summary>` content survives on its own line because `summary` is a
///   break tag around it (details/summary prefix line).
/// - Named entities (`&amp; &lt; &gt; &quot; &#39; &nbsp;`) decode after tag
///   stripping, so `&lt;div&gt;` never re-parses as a tag. Decoding only
///   runs on lines that actually contained a tag.
/// - Content inside backtick code spans is never degraded.
/// - A `<` that does not start a well-formed tag (`a < b`, comment `<!`)
///   stays literal.
///
/// Multi-line tags: when a tag opens but does not close before end-of-line
/// (attributes wrapped onto following lines, e.g. a multi-line `<img … />`),
/// the engine holds the construct with `opensUnclosedTag` /
/// `degradeContinuation` and `stableAdvance` retreats so the whole tag
/// renders within one pass. Approximation: everything between the unclosed
/// `<tag` and the next `>` is treated as attribute text.
enum HTMLDegrader {
    /// Tags that translate to line breaks. Everything else well-formed is
    /// stripped inline (text kept).
    private static let blockLevelTags: Set<String> = [
        "div", "table", "tr", "p", "ul", "li", "details", "summary",
        "h1", "h2", "h3", "h4", "h5", "h6", "br",
    ]

    /// Table cell tags degrade to a separating space (opening and closing
    /// alike) so adjacent cells never concatenate. `tr` stays a line break,
    /// so rows still split onto their own lines.
    private static let cellSeparatorTags: Set<String> = ["td", "th"]

    /// Post-strip entity decoding (single left-to-right pass, no re-parse).
    private static let namedEntities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&#39;": "'",
        "&nbsp;": " ",
    ]

    // MARK: - Single-line degradation

    /// Degrades one source line into zero or more readable text lines.
    /// Self-contained lines only: a tag that opens but does not close before
    /// end-of-line is kept literal. Returns `[line]` unchanged when the line
    /// contains no HTML tag.
    static func degrade(_ line: String) -> [String] {
        var opensUnclosedTag = false
        let result = scan(line, swallowUnclosedTag: false, opensUnclosedTag: &opensUnclosedTag)
        guard result.sawTag else { return [line] }
        return postProcess(result.segments, decodeEntities: true)
    }

    /// Engine variant: when the line ends inside an opened-but-unclosed tag,
    /// drops the tag fragment (and everything after it on the line), returns
    /// the segments before the `<`, and reports `opensUnclosedTag` so the
    /// caller can feed following lines to `degradeContinuation`.
    static func degrade(_ line: String, opensUnclosedTag: inout Bool) -> [String] {
        let result = scan(line, swallowUnclosedTag: true, opensUnclosedTag: &opensUnclosedTag)
        guard result.sawTag else { return [line] }
        return postProcess(result.segments, decodeEntities: true)
    }

    /// Consumes a continuation line of an unclosed tag. Everything up to the
    /// first `>` is attribute text (dropped); the remainder is scanned as a
    /// fresh line. `stillPending` when no `>` arrived yet.
    static func degradeContinuation(_ line: String) -> (segments: [String], stillPending: Bool) {
        guard let close = line.firstIndex(of: ">") else { return ([], true) }
        var reopens = false
        let tail = String(line[line.index(after: close)...])
        let result = scan(tail, swallowUnclosedTag: true, opensUnclosedTag: &reopens)
        // A continuation line is attribute text by definition — a tag was
        // seen even when the post-`>` tail is empty.
        let segments = result.sawTag
            ? postProcess(result.segments, decodeEntities: true)
            : (tail.isEmpty ? [] : postProcess([tail], decodeEntities: true))
        return (segments, reopens)
    }

    /// True when the line opens a tag that does not close before end-of-line
    /// (outside code spans). Backs the engine's stable-prefix retreat so a
    /// multi-line tag always renders within one pass.
    static func endsInsideUnclosedTag(_ line: String) -> Bool {
        guard line.contains("<") else { return false }
        var inCodeSpan = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "`" {
                inCodeSpan.toggle()
                index = line.index(after: index)
                continue
            }
            if character == "<", !inCodeSpan {
                switch scanTag(at: index, in: line) {
                case .notATag:
                    break
                case .closed(_, let endIndex):
                    index = line.index(after: endIndex)
                    continue
                case .unclosed:
                    return true
                }
            }
            index = line.index(after: index)
        }
        return false
    }

    // MARK: - Internals

    /// Scans one line into raw segments (code-span aware). Block tags close
    /// the current segment; other well-formed tags are dropped. With
    /// `swallowUnclosedTag`, an unclosed tag-open ends the scan and reports
    /// through `opensUnclosedTag`; otherwise the fragment stays literal.
    private static func scan(
        _ line: String,
        swallowUnclosedTag: Bool,
        opensUnclosedTag: inout Bool
    ) -> (segments: [String], sawTag: Bool) {
        var segments: [String] = [""]
        var sawTag = false
        var inCodeSpan = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if character == "`" {
                inCodeSpan.toggle()
                segments[segments.count - 1].append(character)
                index = line.index(after: index)
                continue
            }

            if character == "<", !inCodeSpan {
                switch scanTag(at: index, in: line) {
                case .notATag:
                    break
                case .closed(let name, let endIndex):
                    sawTag = true
                    if blockLevelTags.contains(name) {
                        segments.append("")
                    } else if cellSeparatorTags.contains(name) {
                        segments[segments.count - 1].append(" ")
                    }
                    index = line.index(after: endIndex)
                    continue
                case .unclosed:
                    sawTag = true
                    if swallowUnclosedTag {
                        opensUnclosedTag = true
                        return (segments, sawTag)
                    }
                    // Literal: emit '<' and rescan from the next character.
                    segments[segments.count - 1].append(character)
                    index = line.index(after: index)
                    continue
                }
            }

            segments[segments.count - 1].append(character)
            index = line.index(after: index)
        }

        return (segments, sawTag)
    }

    private enum TagScan {
        case notATag
        case closed(name: String, endIndex: String.Index)
        case unclosed(name: String)
    }

    /// Scans a tag starting at `start` (`<`): optional `/`, tag name, anything
    /// up to the closing `>`. `notATag` when the text does not form a tag
    /// (comment `<!`, processing instruction `<?`, missing name);
    /// `unclosed` when the name parsed but no `>` arrived before end-of-line.
    private static func scanTag(at start: String.Index, in line: String) -> TagScan {
        var index = line.index(after: start) // past '<'
        if index < line.endIndex, line[index] == "/" {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index].isLetter else { return .notATag }

        let nameStart = index
        while index < line.endIndex, line[index].isLetter || line[index].isNumber {
            index = line.index(after: index)
        }
        let name = String(line[nameStart..<index]).lowercased()

        // Attributes: scan to the closing '>'.
        while index < line.endIndex {
            if line[index] == ">" {
                return .closed(name: name, endIndex: index)
            }
            index = line.index(after: index)
        }
        return .unclosed(name: name)
    }

    /// Collapses whitespace runs inside each segment (cell-separator spaces
    /// plus any source spacing), trims the ends, and drops empties
    /// (collapsing consecutive tag breaks). Tag-free lines never reach
    /// this — both `degrade` entry points early-return them byte-identical.
    private static func postProcess(_ segments: [String], decodeEntities: Bool) -> [String] {
        segments
            .map { decodeEntities ? Self.decodeEntities(in: $0) : $0 }
            .map { Self.collapseWhitespace(in: $0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Collapses every run of spaces/tabs to a single space. Interior only —
    /// leading/trailing whitespace is left for the trimming step.
    private static func collapseWhitespace(in text: String) -> String {
        guard text.contains("  ") || text.contains("\t") || text.contains(" \t") || text.contains("\t ") else {
            return text
        }
        var result = ""
        var pendingWhitespace = false
        for character in text {
            if character == " " || character == "\t" {
                pendingWhitespace = true
            } else {
                if pendingWhitespace {
                    result.append(" ")
                    pendingWhitespace = false
                }
                result.append(character)
            }
        }
        if pendingWhitespace {
            result.append(" ")
        }
        return result
    }

    /// Single left-to-right pass: `&amp;lt;` becomes `&lt;`, never `<`.
    private static func decodeEntities(in text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&" {
                let remaining = text[index...]
                var matched = false
                for (entity, replacement) in namedEntities where remaining.hasPrefix(entity) {
                    result += replacement
                    index = text.index(index, offsetBy: entity.count)
                    matched = true
                    break
                }
                if matched { continue }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }
}
