import Testing
@testable import ForgeLoopTUI

@Suite("DisplayWidth")
struct DisplayWidthTests {

    // MARK: - ASCII & control characters

    @Test("pure ASCII counts one cell per printable character")
    func testPureASCII() {
        #expect(visibleWidth("") == 0)
        #expect(visibleWidth("hello") == 5)
        #expect(visibleWidth("hello world!") == 12)
    }

    @Test("C0 controls and DEL count as zero cells")
    func testControlCharacters() {
        #expect(visibleWidth("a\u{0}b\u{7}c") == 3)
        #expect(visibleWidth("\u{1B}ab\u{7F}") == 2)
    }

    // MARK: - CJK / wide scalars

    @Test("CJK ideographs count as two cells")
    func testCJKWide() {
        #expect(visibleWidth("中文") == 4)
        #expect(visibleWidth("a中b") == 4)
        #expect(visibleWidth("こんにちは") == 10)
    }

    @Test("plain emoji count as two cells")
    func testPlainEmoji() {
        #expect(visibleWidth("🚀") == 2)
        #expect(visibleWidth("a🚀b") == 4)
    }

    // MARK: - Grapheme clusters

    @Test("ZWJ emoji sequence counts as two cells, not the sum of its parts")
    func testZWJSequence() {
        // 👨‍👩‍👧‍👦 = 4 emoji + 3 ZWJ; per-scalar summing gave ~11 cells.
        #expect(visibleWidth("👨‍👩‍👧‍👦") == 2)
        #expect(visibleWidth("a👨‍👩‍👧‍👦b") == 4)
    }

    @Test("skin-tone-modified emoji counts as two cells")
    func testSkinToneModifier() {
        // 👍🏽 = base + U+1F3FD; per-scalar summing gave 4 cells.
        #expect(visibleWidth("👍🏽") == 2)
        #expect(visibleWidth("x👍🏽y") == 4)
    }

    @Test("VS16 emoji presentation counts as two cells")
    func testVS16EmojiPresentation() {
        // ❤️ = U+2764 U+FE0F.
        #expect(visibleWidth("❤\u{FE0F}") == 2)
        // Keycap sequence: digit + VS16 + U+20E3.
        #expect(visibleWidth("1\u{FE0F}\u{20E3}") == 2)
        // Text presentation (no VS16) keeps the base width.
        #expect(visibleWidth("❤") == 1)
    }

    @Test("combining marks (Mn/Me) count as zero cells")
    func testCombiningMarks() {
        // Decomposed é = e + U+0301 (COMBINING ACUTE ACCENT).
        #expect(visibleWidth("e\u{0301}") == 1)
        // A bare combining mark occupies no cell.
        #expect(visibleWidth("\u{0301}") == 0)
        // Stacked marks on a CJK base keep the base width.
        #expect(visibleWidth("中\u{0301}\u{0302}") == 2)
    }

    @Test("regional-indicator flag pair counts as two cells")
    func testRegionalIndicatorFlags() {
        #expect(visibleWidth("🇨🇳") == 2)
        #expect(visibleWidth("🇨🇳🇯🇵") == 4)
        #expect(visibleWidth("a🇨🇳b") == 4)
    }

    // MARK: - ANSI sequences

    @Test("ANSI CSI sequences are stripped before measuring")
    func testANSIStripping() {
        #expect(visibleWidth("\u{1B}[31m红\u{1B}[0m") == 2)
        #expect(visibleWidth("\u{1B}[1;42mok\u{1B}[0m") == 2)
    }

    // MARK: - physicalRows

    @Test("physicalRows wraps by grapheme-cluster width")
    func testPhysicalRows() {
        #expect(physicalRows(for: "👨‍👩‍👧‍👦", width: 2) == 1)
        #expect(physicalRows(for: "中a", width: 2) == 2)
        #expect(physicalRows(for: "ab", width: 2) == 1)
    }

    // MARK: - Consistency across consumers

    @Test("visibleWidth equals the sum of per-cluster widths")
    func testClusterSummationConsistency() {
        let samples = [
            "a👨‍👩‍👧‍👦中👍🏽",
            "❤\u{FE0F}x\u{0301}🇨🇳",
            "plain ascii 123",
        ]
        for sample in samples {
            let summed = sample.reduce(0) { $0 + graphemeClusterWidth($1) }
            #expect(visibleWidth(sample) == summed)
        }
    }

    @Test("MultiLineInputState.render cursor offset uses cluster widths")
    func testRenderCursorOffsetWithEmoji() {
        // Cursor after "a" in "a👨‍👩‍👧‍👦b": remaining visible width is
        // 2 (family) + 1 (b) = 3. Scalar-summing gave 12.
        var state = MultiLineInputState(text: "a👨‍👩‍👧‍👦b")
        state.handle(.moveToLineStart)
        state.handle(.moveRight)
        let result = state.render()
        #expect(result.cursor.up == 0)
        #expect(result.cursor.offset == 3)
    }
}
