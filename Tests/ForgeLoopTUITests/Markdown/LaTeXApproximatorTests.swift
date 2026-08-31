import XCTest
@testable import ForgeLoopTUI

/// TASK-26 `latex-approx`: common LaTeX macros approximate to Unicode inside
/// `$…$` / `$$…$$` spans; unknown macros pass through raw; `\begin{…}`
/// environments stay raw; no character is ever swallowed.
final class LaTeXApproximatorTests: XCTestCase {
    private func approx(_ math: String) -> String {
        LaTeXApproximator.approximate(math)
    }

    private func spans(_ line: String) -> String {
        LaTeXApproximator.approximatingSpans(in: line)
    }

    private func render(_ text: String) -> [String] {
        StreamingMarkdownEngine().render(text: text, isFinal: true)
    }

    // MARK: - Macro mappings

    func testGreekLettersAndOperators() {
        XCTAssertEqual(approx(#"\alpha \beta \gamma \pi"#), "α β γ π")
        XCTAssertEqual(approx(#"\Gamma \Delta \Omega"#), "Γ Δ Ω")
        XCTAssertEqual(approx(#"\int \infty \pm \geq \leq \neq \cdot \times"#), "∫ ∞ ± ≥ ≤ ≠ · ×")
    }

    func testSqrtAndFrac() {
        XCTAssertEqual(approx(#"\sqrt{\pi}"#), "√(π)")
        XCTAssertEqual(approx(#"\sqrt{2}"#), "√(2)")
        XCTAssertEqual(approx(#"\frac{a}{b}"#), "(a)/(b)")
        XCTAssertEqual(approx(#"\frac{x^2}{y_1}"#), "(x²)/(y₁)")
        // Unbalanced braces: the structural macro falls back to raw while
        // inner standalone macros still expand (nothing is swallowed).
        XCTAssertEqual(approx(#"\sqrt{\pi"#), "\\sqrt{π")
        XCTAssertEqual(approx(#"\frac{a}"#), #"\frac{a}"#)
    }

    func testSingleCharacterScripts() {
        XCTAssertEqual(approx("x_1"), "x₁")
        XCTAssertEqual(approx("x^2"), "x²")
        XCTAssertEqual(approx(#"x^n"#), "xⁿ")
        // Unknown macro stays raw; the subscript after it still applies.
        XCTAssertEqual(approx(#"\sum_i"#), "\\sumᵢ")
    }

    func testBracedScriptsCoverCommonShapes() {
        XCTAssertEqual(approx(#"e^{i\pi}"#), "eⁱπ")
        XCTAssertEqual(approx(#"e^{-x^2}"#), "e⁻ˣ²")
        XCTAssertEqual(approx(#"\int_{-\infty}^{\infty}"#), "∫₋∞∞")
        XCTAssertEqual(approx(#"x^{10}"#), "x¹⁰")
        // Unbalanced brace: the whole script stays literal.
        XCTAssertEqual(approx(#"x^{2"#), #"x^{2"#)
        // No operand: literal.
        XCTAssertEqual(approx("a ^ b"), "a ^ b")
    }

    func testUnknownMacrosPassThroughRaw() {
        XCTAssertEqual(approx(#"\text{if }"#), #"\text{if }"#)
        XCTAssertEqual(approx(#"\foo"#), #"\foo"#)
        XCTAssertEqual(approx(#"a \\ b"#), #"a \\ b"#)
        XCTAssertEqual(approx(#"x \, y"#), #"x \, y"#)
    }

    func testNoCharacterSwallowing() {
        // Every input character is accounted for in the output (macros
        // expand 1:1 to a replacement, scripts map in place).
        XCTAssertEqual(approx(#"E = mc^2"#), "E = mc²")
        XCTAssertEqual(approx("a+b"), "a+b")
        XCTAssertEqual(approx(""), "")
    }

    // MARK: - Inline span behavior

    func testInlineSpansConvertWithDelimitersDropped() {
        XCTAssertEqual(spans("质能方程 $E = mc^2$，欧拉公式 $e^{i\\pi} + 1 = 0$。"), "质能方程 E = mc²，欧拉公式 eⁱπ + 1 = 0。")
        XCTAssertEqual(spans("$$x^2$$"), "x²")
    }

    func testProseWithDollarAmountsStaysUntouched() {
        let line = "价格 $5，成本 $3，合计 $8"
        XCTAssertEqual(spans(line), line)
        XCTAssertEqual(spans("pay $5"), "pay $5")
        XCTAssertEqual(spans("unclosed $x"), "unclosed $x")
    }

    func testEscapedDollarAndCodeSpanProtection() {
        XCTAssertEqual(spans(#"cost \$5 not math"#), #"cost \$5 not math"#)
        XCTAssertEqual(spans("use `$x^2$` literally"), "use `$x^2$` literally")
    }

    // MARK: - Engine wiring

    func testEngineConvertsInlineMathWithChromeCoexistence() {
        XCTAssertEqual(
            render("> 欧拉公式 $e^{i\\pi} + 1 = 0$"),
            ["\u{1B}[2m│\u{1B}[0m 欧拉公式 eⁱπ + 1 = 0"]
        )
        XCTAssertEqual(
            render("## 质能方程 $E = mc^2$"),
            ["\u{1B}[1;34m▓ 质能方程 E = mc²\u{1B}[0m"]
        )
        // Approximation runs before styling; SGR wraps the converted text
        // and is never split by it.
        XCTAssertEqual(
            render("**$x^2$** bold"),
            ["\u{1B}[1mx²\u{1B}[0m bold"]
        )
    }

    func testEngineApproximatesDisplayMathBlock() {
        XCTAssertEqual(
            render("$$\n\\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx = \\sqrt{\\pi}\n$$"),
            ["∫₋∞∞ e⁻ˣ² \\, dx = √(π)"]
        )
    }

    func testEngineKeepsBeginEnvironmentsRaw() {
        // Environments stay entirely raw — including subscripts and the $$
        // delimiters — byte-identical to the pre-approximation pipeline.
        let sample = "$$\n\\begin{bmatrix}\na_{11} & a_{12} \\\\\n\\end{bmatrix}\n$$"
        XCTAssertEqual(render(sample), [
            "$$",
            #"\begin{bmatrix}"#,
            #"a_{11} & a_{12} \\"#,
            #"\end{bmatrix}"#,
            "$$",
        ])
    }

    func testFencedCodeIsNotApproximated() {
        XCTAssertEqual(
            render("```latex\n$x^2$ and $y_1$\n```"),
            [
                "\u{1B}[2m┌─\u{1B}[0m \u{1B}[2;3mlatex\u{1B}[0m",
                "│ $x^2$ and $y_1$",
                "\u{1B}[2m└─\u{1B}[0m",
            ]
        )
    }

    func testDisplayMathStreamingConvergesToStaticRender() {
        let sample = """
        intro
        $$
        \\int_0^1 x^2 \\, dx = \\frac{1}{3}
        $$
        outro
        """
        let staticRender = render(sample)
        XCTAssertEqual(staticRender, ["intro", "∫₀¹ x² \\, dx = (1)/(3)", "outro"])
        for chunkSize in [1, 2, 3, 5, 11] {
            let streaming = StreamingMarkdownEngine()
            var accumulated = ""
            var last: [String] = []
            for start in stride(from: 0, to: sample.count, by: chunkSize) {
                let end = min(start + chunkSize, sample.count)
                let from = sample.index(sample.startIndex, offsetBy: start)
                let to = sample.index(sample.startIndex, offsetBy: end)
                accumulated += String(sample[from..<to])
                last = streaming.render(text: accumulated, isFinal: false)
            }
            last = streaming.render(text: accumulated, isFinal: true)
            XCTAssertEqual(last, staticRender, "chunk size \(chunkSize)")
        }
    }

    func testUnclosedDisplayMathHoldsBackStablePrefix() {
        let engine = StreamingMarkdownEngine()
        let frame1 = "intro\n$$\n\\int_0^1\n"
        let lines1 = engine.render(text: frame1, isFinal: false)
        // Unclosed block flushes raw within the pass; intro is stable, the
        // block opener is not.
        XCTAssertEqual(lines1, ["intro", "$$", #"\int_0^1"#, ""])
        XCTAssertEqual(engine.stableRenderedLineCount, 1)
    }
}
