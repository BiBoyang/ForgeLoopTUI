import XCTest
@testable import ForgeLoopTUI

final class MultiLineInputTests: XCTestCase {

    // MARK: - Insertion

    func testInsertCharacterUpdatesLineAndColumn() {
        var state = MultiLineInputState()
        state.handle(.insert(Character("h")))
        state.handle(.insert(Character("i")))

        XCTAssertEqual(state.lines, ["hi"])
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testInsertTextPreservesNewlines() {
        var state = MultiLineInputState()
        state.handle(.insertText("alpha\nbeta\r\ngamma"))

        XCTAssertEqual(state.lines, ["alpha", "beta", "gamma"])
        XCTAssertEqual(state.cursorRow, 2)
        XCTAssertEqual(state.cursorColumn, 5)
        XCTAssertEqual(state.text, "alpha\nbeta\ngamma")
    }

    func testInsertTextInMiddleSplitsCurrentLine() {
        var state = MultiLineInputState(text: "before-after")
        // place cursor between "before-" and "after"
        for _ in 0..<5 { state.handle(.moveLeft) }
        XCTAssertEqual(state.cursorColumn, 7)

        state.handle(.insertText("X\nY"))

        XCTAssertEqual(state.lines, ["before-X", "Yafter"])
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 1)
    }

    func testInsertNewlineSplitsLineAndAdvancesRow() {
        var state = MultiLineInputState(text: "hello world")
        // place cursor after "hello"
        state.handle(.moveToLineStart)
        for _ in 0..<5 { state.handle(.moveRight) }
        XCTAssertEqual(state.cursorColumn, 5)

        state.handle(.insertNewline)

        XCTAssertEqual(state.lines, ["hello", " world"])
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 0)
    }

    // MARK: - Delete

    func testBackspaceAtLineStartMergesWithPreviousLine() {
        var state = MultiLineInputState(text: "first\nsecond")
        // cursor is at end of "second"
        state.handle(.moveToLineStart)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 0)

        state.handle(.backspace)

        XCTAssertEqual(state.lines, ["firstsecond"])
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 5)
    }

    func testDeleteForwardAtLineEndMergesWithNextLine() {
        var state = MultiLineInputState(text: "alpha\nbeta")
        // cursor at end of "beta"; move to end of "alpha"
        state.handle(.moveToBufferStart)
        state.handle(.moveToLineEnd)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 5)

        state.handle(.deleteForward)

        XCTAssertEqual(state.lines, ["alphabeta"])
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 5)
    }

    func testBackspaceInsideLineRemovesPreviousCharacter() {
        var state = MultiLineInputState(text: "abc")
        state.handle(.backspace)

        XCTAssertEqual(state.lines, ["ab"])
        XCTAssertEqual(state.cursorColumn, 2)
    }

    // MARK: - Movement

    func testMoveLeftCrossesLineBoundary() {
        var state = MultiLineInputState(text: "ab\ncd")
        // cursor at end of "cd" (row 1 col 2)
        state.handle(.moveToLineStart)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 0)

        state.handle(.moveLeft)

        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testMoveRightCrossesLineBoundary() {
        var state = MultiLineInputState(text: "ab\ncd")
        state.handle(.moveToBufferStart)
        state.handle(.moveToLineEnd)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)

        state.handle(.moveRight)

        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 0)
    }

    func testMoveUpDownMaintainsPreferredColumn() {
        var state = MultiLineInputState(text: "wide line\nx\nanother long line")
        // cursor at end of last line (row 2 col 17)
        state.handle(.moveToBufferStart)
        // jump to col 7 on row 0
        for _ in 0..<7 { state.handle(.moveRight) }
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 7)

        // down -> row 1 (only 1 char) clamps to col 1
        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 1)

        // down -> row 2, preferred column 7 restored
        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 2)
        XCTAssertEqual(state.cursorColumn, 7)

        // up -> row 1 clamps again
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 1)

        // up -> row 0 restores col 7
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 7)
    }

    func testMoveUpAtTopAndDownAtBottomAreNoOps() {
        var state = MultiLineInputState(text: "only line")
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 0)
    }

    func testMoveToBufferStartAndEnd() {
        var state = MultiLineInputState(text: "a\nb\ncccc")
        state.handle(.moveToBufferStart)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 0)

        state.handle(.moveToBufferEnd)
        XCTAssertEqual(state.cursorRow, 2)
        XCTAssertEqual(state.cursorColumn, 4)
    }

    // MARK: - Kill (Emacs)

    func testKillToLineStartRemovesLeftPortion() {
        var state = MultiLineInputState(text: "abcdef")
        // place cursor between "abc" and "def"
        for _ in 0..<3 { state.handle(.moveLeft) }
        XCTAssertEqual(state.cursorColumn, 3)

        state.handle(.killToLineStart)

        XCTAssertEqual(state.lines, ["def"])
        XCTAssertEqual(state.cursorColumn, 0)
    }

    func testKillToLineEndRemovesRightPortion() {
        var state = MultiLineInputState(text: "abcdef")
        for _ in 0..<3 { state.handle(.moveLeft) }
        state.handle(.killToLineEnd)

        XCTAssertEqual(state.lines, ["abc"])
        XCTAssertEqual(state.cursorColumn, 3)
    }

    // MARK: - Replace & Clear

    func testReplacePopulatesMultipleLines() {
        var state = MultiLineInputState(text: "old")
        state.handle(.replace("one\ntwo\r\nthree"))

        XCTAssertEqual(state.lines, ["one", "two", "three"])
        XCTAssertEqual(state.cursorRow, 2)
        XCTAssertEqual(state.cursorColumn, 5)
    }

    func testClearResetsToSingleEmptyLine() {
        var state = MultiLineInputState(text: "a\nb\nc")
        state.handle(.clear)

        XCTAssertEqual(state.lines, [""])
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 0)
        XCTAssertTrue(state.isEmpty)
    }

    // MARK: - Render / CursorPlacement

    func testRenderCursorOnLastLine() {
        let state = MultiLineInputState(text: "alpha\nbeta")
        let result = state.render()

        XCTAssertEqual(result.lines, ["alpha", "beta"])
        XCTAssertEqual(result.cursor.up, 0)
        XCTAssertEqual(result.cursor.offset, 0) // cursor at end of "beta"
    }

    func testRenderCursorOnNonLastLine() {
        var state = MultiLineInputState(text: "abcdef\n")
        // Two lines: "abcdef" and ""; cursor at start of empty last line.
        // Move up to row 0, place at column 2 (between b and c).
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 0)
        state.handle(.moveRight)
        state.handle(.moveRight)
        XCTAssertEqual(state.cursorColumn, 2)

        let result = state.render()
        XCTAssertEqual(result.cursor.up, 1) // one row above last line
        XCTAssertEqual(result.cursor.offset, 4) // "abcdef" width 6, col 2 -> offset = 6-2
    }

    func testRenderEmptyBufferProducesSingleEmptyLine() {
        let state = MultiLineInputState()
        let result = state.render()

        XCTAssertEqual(result.lines, [""])
        XCTAssertEqual(result.cursor.up, 0)
        XCTAssertEqual(result.cursor.offset, 0)
        XCTAssertTrue(state.isEmpty)
    }

    func testRenderHandlesCJKWidthForCursorOffset() {
        var state = MultiLineInputState(text: "中文\n")
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 0)

        let result = state.render()
        // "中文" visible width 4; cursor at col 0 -> offset = 4
        XCTAssertEqual(result.cursor.up, 1)
        XCTAssertEqual(result.cursor.offset, 4)
    }

    func testIsEmptyReportsTrueForNewlyClearedState() {
        var state = MultiLineInputState(text: "x")
        XCTAssertFalse(state.isEmpty)
        state.handle(.clear)
        XCTAssertTrue(state.isEmpty)
    }

    // MARK: - Defensive insert

    func testInsertNewlineCharacterRoutesToInsertNewline() {
        var state = MultiLineInputState(text: "ab")
        state.handle(.insert(Character("\n")))
        XCTAssertEqual(state.lines, ["ab", ""])
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 0)
    }

    func testInsertCarriageReturnCharacterRoutesToInsertNewline() {
        var state = MultiLineInputState(text: "ab")
        state.handle(.insert(Character("\r")))
        XCTAssertEqual(state.lines, ["ab", ""])
    }

    func testInsertControlCharacterIsRejected() {
        var state = MultiLineInputState(text: "ab")
        // 0x08 BS — should be rejected, not concatenated as text.
        state.handle(.insert(Character(Unicode.Scalar(0x08)!)))
        XCTAssertEqual(state.lines, ["ab"])
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testInsertTabIsAllowed() {
        var state = MultiLineInputState(text: "ab")
        state.handle(.insert(Character("\t")))
        XCTAssertEqual(state.lines, ["ab\t"])
        XCTAssertEqual(state.cursorColumn, 3)
    }

    // MARK: - Step 5: viewport-aware visual moves

    func testViewportNilUsesLogicalMoves() {
        // No viewport → moveUp/Down behave purely on logical rows.
        var state = MultiLineInputState(text: "abcdefghij\nshort")
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 5)
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 5)
    }

    func testViewportMoveUpWithinWrappedLine() {
        // Single logical line "abcdefghij" (10 chars) at width 4 → 3 visual rows.
        // Cursor at end (col 10): visualRowInRow=10/4=2, visualCol=10%4=2.
        // moveUp → row 0 col (1*4 + 2) = 6.
        var state = MultiLineInputState(text: "abcdefghij", viewport: Viewport(width: 4))
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 10)

        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 6)

        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)

        // Already on top visual row of the logical line; further up is a no-op
        // because cursorRow == 0 and there is no previous logical line.
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testViewportMoveDownWithinWrappedLine() {
        // Cursor at row 0 col 0 of wrapped line; visualRow 0.
        var state = MultiLineInputState(text: "abcdefghij", cursorAtEnd: false, viewport: Viewport(width: 4))
        XCTAssertEqual(state.cursorColumn, 0)

        state.handle(.moveDown)
        XCTAssertEqual(state.cursorColumn, 4)

        state.handle(.moveDown)
        XCTAssertEqual(state.cursorColumn, 8)

        // Now on the bottom visual row of the only logical line; moveDown is no-op.
        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 8)
    }

    func testViewportMoveUpCrossesLogicalBoundaryUsingVisualColumn() {
        // line 0: "abcd" (1 visual row).
        // line 1: "efghij" (2 visual rows: "efgh", "ij").
        var state = MultiLineInputState(text: "abcd\nefghij", viewport: Viewport(width: 4))
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 6)

        // moveUp inside line 1: visualRow 1 → 0, col preferredVisualCol = 6%4=2.
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 2)

        // moveUp again crosses into line 0; line 0 has only 1 visual row;
        // visualCol 2 → col 2.
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testViewportMoveDownCrossesLogicalBoundaryClampsToShortLine() {
        // line 0: "abcdefghij" (3 visual rows). line 1: "x" (1 visual row).
        var state = MultiLineInputState(text: "abcdefghij\nx", viewport: Viewport(width: 4))
        state.handle(.moveToBufferStart)
        for _ in 0..<6 { state.handle(.moveRight) } // col 6
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 6)

        // moveDown inside line 0: visualRow 1 → 2, col = 2*4 + (6%4) = 10.
        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 10)

        // moveDown crosses to line 1; "x" len 1, candidate=preferredVisualCol=2,
        // clamped to 1.
        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 1)
    }

    func testSetViewportTogglesBetweenLogicalAndVisual() {
        var state = MultiLineInputState(text: "abcdefghij")
        XCTAssertNil(state.viewport)
        // logical: cursorRow 0 only → moveUp no-op
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorColumn, 10)

        state.setViewport(Viewport(width: 4))
        XCTAssertEqual(state.viewport?.width, 4)
        // now moveUp walks visual rows: 10 → 6
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorColumn, 6)

        state.setViewport(nil)
        XCTAssertNil(state.viewport)
        // logical again: no-op (single logical line)
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorColumn, 6)
    }

    func testViewportPasteLargeTextRemainsConsistent() {
        // Stress test: paste a long single line that wraps a lot, then
        // run a sequence of visual moves and ensure cursor stays in bounds.
        let bigLine = String(repeating: "x", count: 53)
        var state = MultiLineInputState(viewport: Viewport(width: 8))
        state.handle(.insertText(bigLine))
        XCTAssertEqual(state.lines, [bigLine])
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 53)

        // 7 visual rows: 0..6 (rows 0:0-7, 1:8-15, ..., 5:40-47, 6:48-52).
        // cursorColumn 53 → visualRow 53/8=6, visualCol 53%8=5.
        for _ in 0..<7 {
            state.handle(.moveUp)
        }
        // After 7 moveUp the cursor should be on the top visual row, col 5
        // (visualRowInRow=0, preferredVisualCol=5 → cursorColumn=5).
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 5)

        // Going back down 7 times restores the original position (col 53,
        // because preferredVisualCol stays at 5 and visualRow walks 0→6).
        for _ in 0..<7 {
            state.handle(.moveDown)
        }
        XCTAssertEqual(state.cursorRow, 0)
        // visualRow 6 col 5 = 6*8+5 = 53.
        XCTAssertEqual(state.cursorColumn, 53)
    }

    // MARK: - Step A (failing-first): mixed-width viewport visual moves
    //
    // These cases assume the eventual visibleWidth-aware implementation.
    // Until that lands, the character-index implementation gives the wrong
    // column on lines that mix narrow ASCII with wide CJK glyphs, and the
    // tests below are expected to fail. They define the target semantics
    // for Step B.

    func testViewportMoveUpWithinMixedWidthLineUsesVisibleColumn() {
        // Line "ab中文cd": visible widths [1,1,2,2,1,1] → total 8 cells.
        // Width 4 → 2 visual rows:
        //   row 0 (visible cols 0..3): "ab中"  → char indices 0..3
        //   row 1 (visible cols 4..7): "文cd"  → char indices 3..6
        //
        // Place cursor right after 文 (char index 4, visible col 6, visual
        // row 1, visual col 2). moveUp should land on row 0 at visible col 2,
        // which is char index 2 (between b and 中).
        var state = MultiLineInputState(text: "ab中文cd", viewport: Viewport(width: 4))
        state.handle(.moveLeft) // past d
        state.handle(.moveLeft) // past c → cursor at char index 4 (after 文)
        XCTAssertEqual(state.cursorColumn, 4)

        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testViewportMoveUpAcrossBoundaryPreservesVisibleColumnForMixedWidth() {
        // line 0 "ab中文cd" (8 visible cells, 2 visual rows at width 4)
        // line 1 "xy" (2 visible cells, 1 visual row)
        //
        // Initial cursor at end of line 1 (char index 2, visible col 2).
        // moveUp crosses into line 0's last visual row (visible cols 4..7).
        // Preserving visible col 2 inside that row gives visible col 6, which
        // is char index 4 (right after 文).
        var state = MultiLineInputState(text: "ab中文cd\nxy", viewport: Viewport(width: 4))
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 2)

        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 4)
    }

    func testViewportMoveDownAcrossBoundaryUsesVisibleColumnForMixedWidth() {
        // line 0 "ab中文cd" (2 visual rows at width 4)
        // line 1 "ab" (1 visual row)
        //
        // Cursor positioned right after 文 on line 0 (char index 4, visible
        // col 6, visual row 1, visual col 2). moveDown crosses into line 1
        // and should preserve visible col 2 → char index 2 (after b).
        var state = MultiLineInputState(text: "ab中文cd\nab", viewport: Viewport(width: 4))
        state.handle(.moveUp) // cross into line 0 — also uses visible-col semantics
        // For the purpose of this test we re-anchor the cursor explicitly:
        state.handle(.moveToBufferStart)
        for _ in 0..<4 { state.handle(.moveRight) }
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 4)

        state.handle(.moveDown)
        XCTAssertEqual(state.cursorRow, 1)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testViewportResizeThenMoveUsesNewVisibleGeometryForMixedWidth() {
        // Width 8: "ab中文cd" fits in a single visual row → moveUp is a no-op
        // on a single-line buffer. Resizing to width 4 must re-evaluate the
        // visual geometry: the same char index 4 now sits at visible col 6
        // on visual row 1, so moveUp should land at visible col 2 on visual
        // row 0 → char index 2.
        var state = MultiLineInputState(text: "ab中文cd", viewport: Viewport(width: 8))
        state.handle(.moveLeft) // past d
        state.handle(.moveLeft) // past c → char index 4
        XCTAssertEqual(state.cursorColumn, 4)

        state.setViewport(Viewport(width: 4))
        state.handle(.moveUp)
        XCTAssertEqual(state.cursorRow, 0)
        XCTAssertEqual(state.cursorColumn, 2)
    }
}
