import XCTest
@testable import ForgeLoopTUI

final class MarkdownThemeTests: XCTestCase {
    // MARK: - MarkdownRenderOptions wiring

    func testRenderOptionsDefaultToDefaultTheme() {
        XCTAssertEqual(MarkdownRenderOptions().theme, .default)
    }

    func testRenderOptionsAcceptExplicitTheme() {
        XCTAssertEqual(MarkdownRenderOptions(theme: .none).theme, .none)
    }

    func testRenderOptionsThemeIsIndependentOfTableOptions() {
        var options = MarkdownRenderOptions()
        options.tableStreamingBehavior = .strict
        XCTAssertEqual(options.theme, .default)
        options.theme = .none
        XCTAssertEqual(options.tableStreamingBehavior, .strict)
    }

    // MARK: - Theme presets

    func testNoneThemeLeavesEverySlotEmpty() {
        let theme = MarkdownTheme.none
        XCTAssertTrue(theme.heading1.isEmpty)
        XCTAssertTrue(theme.heading2.isEmpty)
        XCTAssertTrue(theme.heading3.isEmpty)
        XCTAssertTrue(theme.heading4.isEmpty)
        XCTAssertTrue(theme.heading5.isEmpty)
        XCTAssertTrue(theme.heading6.isEmpty)
        XCTAssertTrue(theme.tableHeader.isEmpty)
        XCTAssertTrue(theme.tableBorder.isEmpty)
        XCTAssertTrue(theme.blockquoteLine.isEmpty)
        XCTAssertTrue(theme.fenceBorder.isEmpty)
        XCTAssertTrue(theme.fenceLanguageLabel.isEmpty)
        XCTAssertTrue(theme.taskListChecked.isEmpty)
        XCTAssertTrue(theme.taskListUnchecked.isEmpty)
        XCTAssertTrue(theme.code.keyword.isEmpty)
        XCTAssertTrue(theme.code.string.isEmpty)
        XCTAssertTrue(theme.code.comment.isEmpty)
        XCTAssertTrue(theme.code.number.isEmpty)
    }

    func testDefaultThemeStylesEverySlot() {
        let theme = MarkdownTheme.default
        XCTAssertFalse(theme.heading1.isEmpty)
        XCTAssertFalse(theme.heading2.isEmpty)
        XCTAssertFalse(theme.heading3.isEmpty)
        XCTAssertFalse(theme.heading4.isEmpty)
        XCTAssertFalse(theme.heading5.isEmpty)
        XCTAssertFalse(theme.heading6.isEmpty)
        XCTAssertFalse(theme.tableHeader.isEmpty)
        XCTAssertFalse(theme.tableBorder.isEmpty)
        XCTAssertFalse(theme.blockquoteLine.isEmpty)
        XCTAssertFalse(theme.fenceBorder.isEmpty)
        XCTAssertFalse(theme.fenceLanguageLabel.isEmpty)
        XCTAssertFalse(theme.taskListChecked.isEmpty)
        XCTAssertFalse(theme.taskListUnchecked.isEmpty)
        XCTAssertFalse(theme.code.keyword.isEmpty)
        XCTAssertFalse(theme.code.string.isEmpty)
        XCTAssertFalse(theme.code.comment.isEmpty)
        XCTAssertFalse(theme.code.number.isEmpty)
    }

    func testThemeMemberwiseInitDefaultsToDefaultSlots() {
        // Tweaking a single slot starts from the built-in default theme…
        let tweaked = MarkdownTheme(fenceBorder: .none)
        XCTAssertEqual(tweaked.heading1, MarkdownTheme.default.heading1)
        XCTAssertEqual(tweaked.tableHeader, MarkdownTheme.default.tableHeader)
        XCTAssertEqual(tweaked.code, MarkdownTheme.default.code)
        XCTAssertTrue(tweaked.fenceBorder.isEmpty)
        // …while CodeHighlightStyles defaults to unstyled slots.
        XCTAssertEqual(MarkdownTheme.CodeHighlightStyles().keyword, .none)
    }

    func testDefaultThemeHeadingLadderSpotCheck() {
        XCTAssertEqual(MarkdownTheme.default.heading1, MarkdownStyle([.bold, .foreground(.bright(4))]))
        XCTAssertEqual(MarkdownTheme.default.heading4, MarkdownStyle([.bold]))
        XCTAssertEqual(MarkdownTheme.default.heading6, MarkdownStyle([.foreground(.bright(0))]))
    }

    // MARK: - MarkdownStyle byte output

    func testEmptyStylePassesTextThrough() {
        XCTAssertEqual(MarkdownStyle.none.applied(to: "text"), "text")
        XCTAssertEqual(MarkdownStyle().applied(to: "text"), "text")
    }

    func testEmptyTextPassesThroughWithoutEscapeBytes() {
        XCTAssertEqual(MarkdownStyle([.bold]).applied(to: ""), "")
    }

    func testSingleAttributeWrapsWithSGRAndReset() {
        XCTAssertEqual(
            MarkdownStyle([.bold]).applied(to: "x"),
            "\u{1B}[1mx\u{1B}[0m"
        )
        XCTAssertEqual(
            MarkdownStyle([.faint]).applied(to: "│"),
            "\u{1B}[2m│\u{1B}[0m"
        )
    }

    func testMultipleAttributesJoinParametersInOrder() {
        XCTAssertEqual(
            MarkdownStyle([.faint, .italic, .foreground(.standard(3))]).applied(to: "swift"),
            "\u{1B}[2;3;33mswift\u{1B}[0m"
        )
    }

    func testColorParameterEncodings() {
        XCTAssertEqual(MarkdownSGRColor.standard(4).sgrParameters(isBackground: false), [34])
        XCTAssertEqual(MarkdownSGRColor.standard(4).sgrParameters(isBackground: true), [44])
        XCTAssertEqual(MarkdownSGRColor.bright(0).sgrParameters(isBackground: false), [90])
        XCTAssertEqual(MarkdownSGRColor.bright(7).sgrParameters(isBackground: true), [107])
        XCTAssertEqual(MarkdownSGRColor.indexed(208).sgrParameters(isBackground: false), [38, 5, 208])
        XCTAssertEqual(MarkdownSGRColor.indexed(238).sgrParameters(isBackground: true), [48, 5, 238])
        XCTAssertEqual(
            MarkdownSGRColor.rgb(red: 1, green: 2, blue: 255).sgrParameters(isBackground: false),
            [38, 2, 1, 2, 255]
        )
        XCTAssertEqual(
            MarkdownStyle([.background(.rgb(red: 0, green: 128, blue: 255))]).applied(to: "bg"),
            "\u{1B}[48;2;0;128;255mbg\u{1B}[0m"
        )
    }

    func testAttributeParameterCodes() {
        XCTAssertEqual(MarkdownSGRAttribute.bold.parameters, [1])
        XCTAssertEqual(MarkdownSGRAttribute.faint.parameters, [2])
        XCTAssertEqual(MarkdownSGRAttribute.italic.parameters, [3])
        XCTAssertEqual(MarkdownSGRAttribute.underline.parameters, [4])
        XCTAssertEqual(MarkdownSGRAttribute.inverse.parameters, [7])
        XCTAssertEqual(MarkdownSGRAttribute.strikethrough.parameters, [9])
    }

    // MARK: - Heading level mapping

    func testHeadingStyleMapsEachLevel() {
        let theme = MarkdownTheme.default
        XCTAssertEqual(theme.headingStyle(forLevel: 1), theme.heading1)
        XCTAssertEqual(theme.headingStyle(forLevel: 2), theme.heading2)
        XCTAssertEqual(theme.headingStyle(forLevel: 3), theme.heading3)
        XCTAssertEqual(theme.headingStyle(forLevel: 4), theme.heading4)
        XCTAssertEqual(theme.headingStyle(forLevel: 5), theme.heading5)
        XCTAssertEqual(theme.headingStyle(forLevel: 6), theme.heading6)
    }

    func testHeadingStyleClampsOutOfRangeLevels() {
        let theme = MarkdownTheme.none
        XCTAssertEqual(theme.headingStyle(forLevel: 0), theme.heading1)
        XCTAssertEqual(theme.headingStyle(forLevel: Int.min), theme.heading1)
        XCTAssertEqual(theme.headingStyle(forLevel: 7), theme.heading6)
        XCTAssertEqual(theme.headingStyle(forLevel: Int.max), theme.heading6)
    }

    // MARK: - Engine pin

    /// `.none` pins the pre-theme plain byte stream: block chrome carries no
    /// escape sequences. (Inline formatting emits its own SGR independent of
    /// the theme, so the sample avoids inline constructs.) Default-theme
    /// styling bytes are covered by `BlockElementStylingTests`.
    func testNoneThemeEngineOutputContainsNoEscapeSequences() {
        let sample = """
        # Release Notes

        ## Highlights

        > Streams are stable now.

        ```swift
        let theme = MarkdownTheme.default
        ```

        | Area | Status |
        | --- | --- |
        | streaming | stable |
        | theming | scaffolded |

        - [x] stable prefix
        - [ ] colors
        """
        let engine = StreamingMarkdownEngine(options: MarkdownRenderOptions(theme: .none))
        let lines = engine.render(text: sample, isFinal: true)
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertFalse(
                line.contains("\u{1B}"),
                "unexpected escape sequence in .none-themed output: \(line.debugDescription)"
            )
        }
    }
}
