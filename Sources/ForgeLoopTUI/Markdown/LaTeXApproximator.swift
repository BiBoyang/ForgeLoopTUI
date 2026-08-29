import Foundation

/// Approximates common LaTeX math to readable Unicode text.
///
/// Pure functions over data-driven mapping tables — no state, no environment
/// probing. Unknown macros pass through raw (nothing is swallowed), and
/// `\begin{…}` environments are left to the caller to keep entirely raw.
///
/// Handled forms (scope per plan TASK-26):
/// - Greek letters and the operators `\int \infty \pm \geq \leq \neq \cdot \times`.
/// - `\sqrt{…}` → `√(…)`, `\frac{a}{b}` → `(a)/(b)`.
/// - Sub/superscripts: single character (`x_1` → `x₁`, `x^2` → `x²`) and
///   braced runs. Braced content is recursively approximated first, then each
///   character is mapped through the sub/sup tables; characters without a
///   Unicode counterpart stay literal and the braces drop — this covers the
///   common shapes `e^{i\pi}` → `eⁱπ`, `e^{-x^2}` → `e⁻ˣ²`,
///   `\int_{-\infty}^{\infty}` → `∫₋∞∞`.
enum LaTeXApproximator {
    // MARK: - Mapping tables

    /// Macro name (without backslash) → replacement.
    private static let symbols: [String: String] = [
        // Greek lowercase (+ varphi variant).
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω",
        // Greek uppercase.
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ",
        "Omega": "Ω",
        // Operators.
        "int": "∫", "infty": "∞", "pm": "±", "geq": "≥", "leq": "≤",
        "neq": "≠", "cdot": "·", "times": "×",
    ]

    /// Superscript counterparts (characters without one stay literal).
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "(": "⁽", ")": "⁾", "=": "⁼",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ",
        "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ", "k": "ᵏ", "l": "ˡ",
        "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ",
        "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "x": "ˣ",
    ]

    /// Subscript counterparts (characters without one stay literal).
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "(": "₍", ")": "₎", "=": "₌",
        "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "h": "ₕ", "i": "ᵢ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "p": "ₚ", "r": "ᵣ",
        "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ",
    ]

    // MARK: - Inline spans

    /// Replaces `$…$` / `$$…$$` spans in a single line with their Unicode
    /// approximation. Spans whose content carries no math indicator
    /// (`\`, `^`, `_`, `{`) stay untouched — prose with dollar amounts keeps
    /// its delimiters. Backtick code spans are protected; `\$` is literal.
    static func approximatingSpans(in line: String) -> String {
        guard line.contains("$") else { return line }

        var result = ""
        var inCodeSpan = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if character == "`" {
                inCodeSpan.toggle()
                result.append(character)
                index = line.index(after: index)
                continue
            }

            if character == "\\", line.index(after: index) < line.endIndex,
               line[line.index(after: index)] == "$" {
                // Escaped dollar: literal, never a delimiter.
                result.append(character)
                result.append("$")
                index = line.index(after: line.index(after: index))
                continue
            }

            if character == "$", !inCodeSpan {
                // Prefer the longer $$ delimiter.
                let afterDollar = line.index(after: index)
                let delimiter: String
                var contentStart: String.Index
                if afterDollar < line.endIndex, line[afterDollar] == "$" {
                    delimiter = "$$"
                    contentStart = line.index(after: afterDollar)
                } else {
                    delimiter = "$"
                    contentStart = afterDollar
                }

                if let closing = findClosing(delimiter: delimiter, from: contentStart, in: line) {
                    let content = String(line[contentStart..<closing])
                    if looksLikeMath(content) {
                        result += approximate(content)
                        index = line.index(closing, offsetBy: delimiter.count)
                        continue
                    }
                }
                // No closing delimiter or not math: keep the text as-is.
                result += delimiter
                index = contentStart
                continue
            }

            result.append(character)
            index = line.index(after: index)
        }

        return result
    }

    /// True when `text` contains a LaTeX environment opener — the engine
    /// keeps such blocks entirely raw.
    static func isEnvironment(_ text: String) -> Bool {
        text.contains("\\begin{")
    }

    // MARK: - Core approximation

    /// Approximates a math string: macro expansion, `\sqrt`/`\frac`, and
    /// sub/superscripts. Unknown macros pass through raw; no character is
    /// ever dropped.
    static func approximate(_ math: String) -> String {
        var result = ""
        var index = math.startIndex

        while index < math.endIndex {
            let character = math[index]

            if character == "\\" {
                index = appendMacro(at: index, in: math, to: &result)
                continue
            }

            if character == "^" || character == "_" {
                if let (converted, next) = convertScript(at: index, in: math) {
                    result += converted
                    index = next
                    continue
                }
                // No operand: literal.
                result.append(character)
                index = math.index(after: index)
                continue
            }

            result.append(character)
            index = math.index(after: index)
        }

        return result
    }

    // MARK: - Internals

    /// A span is converted only when it carries a math indicator; otherwise
    /// prose like `$5 and $10` keeps its delimiters verbatim.
    private static func looksLikeMath(_ content: String) -> Bool {
        content.contains("\\") || content.contains("^")
            || content.contains("_") || content.contains("{")
    }

    private static func findClosing(
        delimiter: String,
        from start: String.Index,
        in line: String
    ) -> String.Index? {
        let searchRange = line[start...]
        return searchRange.range(of: delimiter)?.lowerBound
    }

    /// Parses a macro at `start` (the backslash) and appends its expansion to
    /// `result`. Returns the index after the consumed macro (and arguments).
    private static func appendMacro(
        at start: String.Index,
        in math: String,
        to result: inout String
    ) -> String.Index {
        var index = math.index(after: start)
        let nameStart = index
        while index < math.endIndex, math[index].isLetter {
            index = math.index(after: index)
        }
        let name = String(math[nameStart..<index])

        // Structural macros consume braced arguments.
        if name == "sqrt" {
            if let (argument, after) = readBracedGroup(after: index, in: math) {
                result += "√(" + approximate(argument) + ")"
                return after
            }
        }
        if name == "frac" {
            if let (numerator, afterNumerator) = readBracedGroup(after: index, in: math),
               let (denominator, afterDenominator) = readBracedGroup(after: afterNumerator, in: math) {
                result += "(" + approximate(numerator) + ")/(" + approximate(denominator) + ")"
                return afterDenominator
            }
        }

        if let replacement = symbols[name] {
            result += replacement
            return index
        }

        // Unknown macro (including bare `\\` and `\,`): raw passthrough.
        if name.isEmpty {
            result.append(math[start])
            return nameStart
        }
        result += math[start..<index]
        return index
    }

    /// Converts the operand of `^`/`_` at `start`: a braced group is
    /// recursively approximated then mapped character by character; a single
    /// character is mapped directly. Returns nil when there is no operand.
    private static func convertScript(
        at start: String.Index,
        in math: String
    ) -> (converted: String, next: String.Index)? {
        let table = math[start] == "^" ? superscripts : subscripts
        var index = math.index(after: start)
        guard index < math.endIndex else { return nil }

        if math[index] == "{" {
            guard let (inner, after) = readBracedGroup(after: index, in: math) else { return nil }
            let expanded = approximate(inner)
            let mapped = expanded.map { String(table[$0] ?? $0) }.joined()
            return (mapped, after)
        }

        let operand = math[index]
        guard operand != " " else { return nil }
        index = math.index(after: index)
        return (String(table[operand] ?? operand), index)
    }

    /// Reads a balanced `{…}` group starting at `after` (which must point at
    /// the opening `{`). Returns nil when the group is missing or unbalanced —
    /// callers then fall back to raw passthrough.
    private static func readBracedGroup(
        after: String.Index,
        in math: String
    ) -> (content: String, afterGroup: String.Index)? {
        guard after < math.endIndex, math[after] == "{" else { return nil }
        var depth = 0
        var index = after
        while index < math.endIndex {
            if math[index] == "{" {
                depth += 1
            } else if math[index] == "}" {
                depth -= 1
                if depth == 0 {
                    let content = String(math[math.index(after: after)..<index])
                    return (content, math.index(after: index))
                }
            }
            index = math.index(after: index)
        }
        return nil
    }
}
