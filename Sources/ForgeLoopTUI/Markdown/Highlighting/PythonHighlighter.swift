/// Line-level Python highlighter: keywords, strings, comments, numbers.
///
/// Deliberately a small tokenizer, not a grammar — each line is classified
/// into the four `CodeHighlightStyles` categories and nothing more.
/// Documented approximations (accepted scope limits, not bugs):
/// - backslash escapes are honored uniformly, including inside raw strings
///   (an invalid raw string ending in a backslash, e.g. `r"\"`, stays
///   "in string" where Python would error);
/// - f-string interpolation is not parsed: the whole literal is one string;
/// - builtins (`print`, `len`, …) are not keywords and stay plain;
/// - soft keywords (`match`, `case`) are not colored, since they are also
///   valid identifiers.
enum PythonHighlighter: SyntaxHighlighter {
    enum Continuation: Sendable, Equatable {
        /// Not inside a string literal.
        case none
        /// Inside an unterminated triple-quoted string; carries the closing
        /// delimiter (`'''` or `"""`).
        case inTripleQuotedString(delimiter: String)
    }

    static let initialContinuation: Continuation = .none

    /// `keyword.kwlist` (Python 3). Soft keywords are intentionally absent.
    private static let keywords: Set<String> = [
        "False", "None", "True",
        "and", "as", "assert", "async", "await",
        "break", "class", "continue", "def", "del",
        "elif", "else", "except", "finally", "for", "from", "global",
        "if", "import", "in", "is", "lambda", "nonlocal", "not", "or",
        "pass", "raise", "return", "try", "while", "with", "yield",
    ]

    static func highlight(
        line: String,
        continuation: inout Continuation,
        styles: MarkdownTheme.CodeHighlightStyles
    ) -> [HighlightSegment] {
        let chars = Array(line)
        let count = chars.count
        var segments: [HighlightSegment] = []
        var index = 0
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(HighlightSegment(text: plain, style: .none))
            plain = ""
        }

        func isStringPrefix(_ word: String) -> Bool {
            switch word.lowercased() {
            case "r", "b", "u", "f", "br", "rb", "fr", "rf": return true
            default: return false
            }
        }

        /// Appends one string segment for the literal whose quote character
        /// sits at `quoteIndex`; `start` includes any prefix (`f` in `f"…"`).
        /// An unterminated triple quote sets the cross-line continuation.
        func scanString(start: Int, quoteIndex: Int) {
            let quote = chars[quoteIndex]
            let isTriple = quoteIndex + 2 < count
                && chars[quoteIndex + 1] == quote
                && chars[quoteIndex + 2] == quote
            var scan = quoteIndex + (isTriple ? 3 : 1)
            while scan < count {
                if chars[scan] == "\\" {
                    scan += 2
                    continue
                }
                if chars[scan] == quote {
                    if isTriple {
                        guard scan + 2 < count,
                              chars[scan + 1] == quote,
                              chars[scan + 2] == quote
                        else {
                            scan += 1
                            continue
                        }
                        segments.append(HighlightSegment(text: String(chars[start..<(scan + 3)]), style: styles.string))
                        index = scan + 3
                        return
                    }
                    segments.append(HighlightSegment(text: String(chars[start..<(scan + 1)]), style: styles.string))
                    index = scan + 1
                    return
                }
                scan += 1
            }
            // Unterminated: color to end of line. Triple quotes carry state
            // across lines; single-quoted strings just end (invalid Python
            // renders harmlessly as string, and a mid-keystroke streaming
            // line is re-rendered whole once more characters arrive).
            segments.append(HighlightSegment(text: String(chars[start...]), style: styles.string))
            index = count
            if isTriple {
                continuation = .inTripleQuotedString(delimiter: String(repeating: quote, count: 3))
            }
        }

        /// Scans a numeric literal starting at `start` (a digit, or `.`
        /// followed by a digit) and returns the index one past it. Covers
        /// `_` separators, floats, exponents, `0x`/`0o`/`0b`, and the `j`
        /// imaginary suffix — an approximation, not the full grammar.
        func scanNumber(from start: Int) -> Int {
            var scan = start
            if chars[scan] == "0", scan + 1 < count, "xXoObB".contains(chars[scan + 1]) {
                scan += 2
                while scan < count, chars[scan].isHexDigit || chars[scan] == "_" { scan += 1 }
                return scan
            }
            var seenDot = false
            while scan < count {
                let ch = chars[scan]
                if ch.isNumber || ch == "_" {
                    scan += 1
                    continue
                }
                if ch == ".", !seenDot, scan + 1 < count, chars[scan + 1].isNumber {
                    seenDot = true
                    scan += 1
                    continue
                }
                if ch == "e" || ch == "E", scan + 1 < count {
                    let next = chars[scan + 1]
                    if next.isNumber {
                        scan += 1
                        continue
                    }
                    if (next == "+" || next == "-"), scan + 2 < count, chars[scan + 2].isNumber {
                        scan += 2
                        continue
                    }
                }
                if ch == "j" || ch == "J" {
                    return scan + 1
                }
                break
            }
            return scan
        }

        // Resume inside an unterminated triple-quoted string: the line is
        // string up to the closing delimiter (or in full when absent).
        if case .inTripleQuotedString(let delimiter) = continuation {
            let quote = delimiter[delimiter.startIndex]
            var scan = 0
            var closingEnd: Int?
            while scan < count {
                if chars[scan] == "\\" {
                    scan += 2
                    continue
                }
                if chars[scan] == quote, scan + 2 < count,
                   chars[scan + 1] == quote, chars[scan + 2] == quote
                {
                    closingEnd = scan + 3
                    break
                }
                scan += 1
            }
            if let closingEnd {
                segments.append(HighlightSegment(text: String(chars[..<closingEnd]), style: styles.string))
                index = closingEnd
                continuation = .none
            } else {
                segments.append(HighlightSegment(text: line, style: styles.string))
                return merged(segments)
            }
        }

        while index < count {
            let character = chars[index]
            if character == " " || character == "\t" {
                plain.append(character)
                index += 1
                continue
            }
            // A `#` outside any string starts a comment to end of line; a `#`
            // inside a string was already consumed by the string scanner.
            if character == "#" {
                flushPlain()
                segments.append(HighlightSegment(text: String(chars[index...]), style: styles.comment))
                index = count
                continue
            }
            if character == "\"" || character == "'" {
                flushPlain()
                scanString(start: index, quoteIndex: index)
                continue
            }
            if character == "_" || character.isLetter {
                var end = index + 1
                while end < count, chars[end] == "_" || chars[end].isLetter || chars[end].isNumber {
                    end += 1
                }
                let word = String(chars[index..<end])
                if end < count, (chars[end] == "\"" || chars[end] == "'"), isStringPrefix(word) {
                    flushPlain()
                    scanString(start: index, quoteIndex: end)
                    continue
                }
                if keywords.contains(word) {
                    flushPlain()
                    segments.append(HighlightSegment(text: word, style: styles.keyword))
                } else {
                    plain.append(word)
                }
                index = end
                continue
            }
            if character.isNumber || (character == "." && index + 1 < count && chars[index + 1].isNumber) {
                flushPlain()
                let end = scanNumber(from: index)
                segments.append(HighlightSegment(text: String(chars[index..<end]), style: styles.number))
                index = end
                continue
            }
            plain.append(character)
            index += 1
        }
        flushPlain()
        return merged(segments)
    }

    /// Coalesces adjacent same-style segments and drops empty ones, so the
    /// emitted byte stream is deterministic and minimal. Concatenating the
    /// result's texts always reproduces the input line exactly.
    private static func merged(_ segments: [HighlightSegment]) -> [HighlightSegment] {
        var result: [HighlightSegment] = []
        for segment in segments where !segment.text.isEmpty {
            if let last = result.last, last.style == segment.style {
                result[result.count - 1].text += segment.text
            } else {
                result.append(segment)
            }
        }
        return result
    }
}
