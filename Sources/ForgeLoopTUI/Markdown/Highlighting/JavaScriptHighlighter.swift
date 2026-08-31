/// Line-level JavaScript highlighter: keywords, strings, comments, numbers.
///
/// Deliberately a small tokenizer, not a grammar — each line is classified
/// into the four `CodeHighlightStyles` categories and nothing more.
/// Documented approximations (accepted scope limits, not bugs):
/// - template-literal interpolation is not parsed: the whole literal —
///   `${…}` expressions included — is one string segment;
/// - regex literals are not recognized: `/` starts a comment only when
///   doubled (`//`) or starred (`/*`), so a regex containing `//` mis-splits;
/// - the literals `true`/`false`/`null`/`undefined` color as keywords,
///   matching common editor convention;
/// - globals (`console`, `Math`, …) are not keywords and stay plain.
enum JavaScriptHighlighter: SyntaxHighlighter {
    enum Continuation: Sendable, Equatable {
        /// Not inside a comment or template literal.
        case none
        /// Inside an unterminated `/* … */` block comment.
        case inBlockComment
        /// Inside an unterminated template literal (backtick); the closing
        /// backtick ends it, escapes honored, `${…}` not parsed.
        case inTemplateLiteral
    }

    static let initialContinuation: Continuation = .none

    /// ECMAScript reserved words plus the literal keywords. `let`/`const`/
    /// `async`/`await`/`static`/`of`/`from` are included although some are
    /// context-dependent in the grammar — the tokenizer has no context.
    private static let keywords: Set<String> = [
        "await", "async", "break", "case", "catch", "class", "const",
        "continue", "debugger", "default", "delete", "do", "else", "export",
        "extends", "finally", "for", "from", "function", "if", "import",
        "in", "instanceof", "let", "new", "of", "return", "static", "super",
        "switch", "this", "throw", "try", "typeof", "var", "void", "while",
        "with", "yield",
        "true", "false", "null", "undefined",
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

        /// Appends one string segment for the single- or double-quoted
        /// literal whose quote sits at `start`. Unterminated literals color
        /// to end of line without leaking cross-line state (invalid JS
        /// renders harmlessly; a mid-keystroke streaming line is re-rendered
        /// whole once more characters arrive).
        func scanQuotedString(start: Int) {
            let quote = chars[start]
            var scan = start + 1
            while scan < count {
                if chars[scan] == "\\" {
                    scan += 2
                    continue
                }
                if chars[scan] == quote {
                    segments.append(HighlightSegment(text: String(chars[start...scan]), style: styles.string))
                    index = scan + 1
                    return
                }
                scan += 1
            }
            segments.append(HighlightSegment(text: String(chars[start...]), style: styles.string))
            index = count
        }

        /// Appends one string segment for the template literal whose opening
        /// backtick sits at `start`. An unterminated literal carries the
        /// cross-line continuation; `${…}` interpolations stay part of the
        /// string (not parsed).
        func scanTemplateLiteral(start: Int) {
            var scan = start + 1
            while scan < count {
                if chars[scan] == "\\" {
                    scan += 2
                    continue
                }
                if chars[scan] == "`" {
                    segments.append(HighlightSegment(text: String(chars[start...scan]), style: styles.string))
                    index = scan + 1
                    return
                }
                scan += 1
            }
            segments.append(HighlightSegment(text: String(chars[start...]), style: styles.string))
            index = count
            continuation = .inTemplateLiteral
        }

        /// Appends one comment segment for the block comment whose `/*`
        /// starts at `start`. An unterminated comment carries the cross-line
        /// continuation.
        func scanBlockComment(start: Int) {
            var scan = start + 2
            while scan + 1 < count {
                if chars[scan] == "*", chars[scan + 1] == "/" {
                    segments.append(HighlightSegment(text: String(chars[start...scan + 1]), style: styles.comment))
                    index = scan + 2
                    return
                }
                scan += 1
            }
            segments.append(HighlightSegment(text: String(chars[start...]), style: styles.comment))
            index = count
            continuation = .inBlockComment
        }

        /// Scans a numeric literal starting at `start` (a digit, or `.`
        /// followed by a digit) and returns the index one past it. Covers
        /// `_` separators, floats, exponents, `0x`/`0o`/`0b`, and the `n`
        /// bigint suffix — an approximation, not the full grammar.
        func scanNumber(from start: Int) -> Int {
            var scan = start
            if chars[scan] == "0", scan + 1 < count, "xXoObB".contains(chars[scan + 1]) {
                scan += 2
                while scan < count, chars[scan].isHexDigit || chars[scan] == "_" { scan += 1 }
                if scan < count, chars[scan] == "n" { scan += 1 }
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
                if ch == "n" {
                    return scan + 1
                }
                break
            }
            return scan
        }

        // Resume inside an unterminated block comment: the line is comment
        // up to the closing `*/` (or in full when absent).
        if continuation == .inBlockComment {
            var scan = 0
            var closingEnd: Int?
            while scan + 1 < count {
                if chars[scan] == "*", chars[scan + 1] == "/" {
                    closingEnd = scan + 2
                    break
                }
                scan += 1
            }
            if let closingEnd {
                segments.append(HighlightSegment(text: String(chars[..<closingEnd]), style: styles.comment))
                index = closingEnd
                continuation = .none
            } else {
                segments.append(HighlightSegment(text: line, style: styles.comment))
                return merged(segments)
            }
        }

        // Resume inside an unterminated template literal: the line is string
        // up to the closing backtick (or in full when absent).
        if continuation == .inTemplateLiteral {
            var scan = 0
            var closingEnd: Int?
            while scan < count {
                if chars[scan] == "\\" {
                    scan += 2
                    continue
                }
                if chars[scan] == "`" {
                    closingEnd = scan + 1
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
            // A `/` only ever starts a comment (`//` line, `/*` block);
            // regex literals are not recognized (documented approximation).
            if character == "/", index + 1 < count, chars[index + 1] == "/" {
                flushPlain()
                segments.append(HighlightSegment(text: String(chars[index...]), style: styles.comment))
                index = count
                continue
            }
            if character == "/", index + 1 < count, chars[index + 1] == "*" {
                flushPlain()
                scanBlockComment(start: index)
                continue
            }
            if character == "\"" || character == "'" {
                flushPlain()
                scanQuotedString(start: index)
                continue
            }
            if character == "`" {
                flushPlain()
                scanTemplateLiteral(start: index)
                continue
            }
            if character == "_" || character == "$" || character.isLetter {
                var end = index + 1
                while end < count, chars[end] == "_" || chars[end] == "$" || chars[end].isLetter || chars[end].isNumber {
                    end += 1
                }
                let word = String(chars[index..<end])
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
