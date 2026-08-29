import XCTest
@testable import ForgeLoopTUI

/// Regression tests for the duplicated-scrollback defect: streaming tables /
/// code fences re-render earlier lines mid-stream, and the legacy
/// drop-last-heuristic append state re-emitted already-printed lines (a
/// 65-line table fixture produced 1675 appended lines). The fix routes
/// committing through the engine-certified stable prefix
/// (`MarkdownEngine.stableRenderedLineCount` →
/// `TranscriptRenderer.activeStreamingStableLineCount` →
/// `StreamingTranscriptAppendState.consume(transcript:activeRange:stableLineCount:)`).
@MainActor
final class StreamingStableCommitTests: XCTestCase {

    // MARK: - End-to-end: appended output equals the final transcript exactly

    /// Streams `text` through TranscriptRenderer + append state, feeding one
    /// source line per tick, and returns every line ever appended.
    private func appendedLinesWhileStreaming(
        _ text: String,
        engine: MarkdownEngine = StreamingMarkdownEngine()
    ) -> (appended: [String], final: [String]) {
        let sourceLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let renderer = TranscriptRenderer(markdownEngine: engine)
        var appendState = StreamingTranscriptAppendState()
        var appended: [String] = []

        func drain() {
            appended += appendState.consume(
                transcript: renderer.transcriptLines,
                activeRange: renderer.activeStreamingRange,
                stableLineCount: renderer.activeStreamingStableLineCount
            )
        }

        renderer.applyCore(.blockStart(id: "b"))
        drain()

        var buffer = ""
        for (index, line) in sourceLines.enumerated() {
            if index > 0 { buffer += "\n" }
            buffer += line
            renderer.applyCore(.blockUpdate(id: "b", lines: [buffer]))
            drain()
        }

        renderer.applyCore(.blockEnd(id: "b", lines: [buffer], footer: nil))
        drain()

        return (appended, renderer.transcriptLines)
    }

    private func assertNoDuplication(
        _ text: String,
        engine: MarkdownEngine = StreamingMarkdownEngine(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = appendedLinesWhileStreaming(text, engine: engine)
        XCTAssertEqual(
            result.appended,
            result.final,
            "every transcript line must be appended exactly once, in order — "
                + "appended \(result.appended.count) lines vs \(result.final.count) final lines",
            file: file,
            line: line
        )
    }

    func testStreamingTableWithGrowingColumnWidthsAppendsEachLineOnce() {
        // The original repro shape: "Alice" widens column 0 after the header
        // was already rendered, so the box borders change mid-stream.
        assertNoDuplication("""
        ## Demo

        | Name  | Score |
        | ----- | ----: |
        | Alice |    99 |
        | Bob   |     7 |
        | Carol |    42 |

        done
        """)
    }

    func testStreamingDegradeToTableFlipAppendsEachLineOnce() {
        // Header+divider render as raw text until the first data row turns
        // them into a box table — the classic mid-stream content flip.
        assertNoDuplication("""
        | Item   | Qty | Price |
        | :----- | --: | ----: |
        | Pencil |   2 |  1.50 |
        | Eraser |   1 |  0.80 |
        """)
    }

    func testStreamingCodeFenceContainingTableLikeLinesAppendsEachLineOnce() {
        assertNoDuplication("""
        ## Fence

        ```markdown
        | raw | table |
        | --- | ----- |
        | no  | parse |
        ```

        after
        """)
    }

    func testGarbleFixtureAppendsEachLineOnce() {
        assertNoDuplication(StreamingGarbleFixture.markdown)
    }

    func testPlainTextStreamingAppendsEachLineOnce() {
        assertNoDuplication(
            "You said: hello\n\nThis is a streaming reply powered by ForgeLoopTUI.",
            engine: PlainTextMarkdownEngine()
        )
    }

    // MARK: - Renderer: stable line count exposure

    func testRendererStableCountHoldsBackUnstableTable() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.blockStart(id: "b"))

        renderer.applyCore(.blockUpdate(id: "b", lines: ["intro"]))
        XCTAssertEqual(renderer.activeStreamingStableLineCount, 0)

        // "intro" is now newline-terminated → stable; the table below it is
        // mid-stream (column widths may still grow) → fully held back.
        renderer.applyCore(.blockUpdate(id: "b", lines: ["intro\n\n| a | b |\n| --- | --- |\n| 1 | 2 |"]))
        XCTAssertEqual(renderer.activeStreamingStableLineCount, 2)

        renderer.applyCore(.blockEnd(id: "b", lines: ["intro\n\n| a | b |\n| --- | --- |\n| 1 | 2 |"], footer: nil))
        XCTAssertEqual(renderer.activeStreamingStableLineCount, 0)
        XCTAssertNil(renderer.activeStreamingRange)
    }

    func testRendererStableCountAdvancesWithPlainParagraphs() {
        let renderer = TranscriptRenderer()
        renderer.applyCore(.blockStart(id: "b"))

        renderer.applyCore(.blockUpdate(id: "b", lines: ["first paragraph"]))
        XCTAssertEqual(renderer.activeStreamingStableLineCount, 0)

        renderer.applyCore(.blockUpdate(id: "b", lines: ["first paragraph\n\nsecond"]))
        XCTAssertEqual(renderer.activeStreamingStableLineCount, 2)

        renderer.applyCore(.blockEnd(id: "b", lines: ["first paragraph\n\nsecond"], footer: nil))
    }

    // MARK: - Engine: stable prefix immutability

    func testStreamingEngineStablePrefixNeverChangesWhileBufferGrows() {
        let engine = StreamingMarkdownEngine()
        let full = StreamingGarbleFixture.markdown

        let finalLines = engine.render(text: full, isFinal: true)
        engine.reset()

        var buffer = ""
        var previousStableCount = 0
        for (index, line) in full.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { buffer += "\n" }
            buffer += line
            let rendered = engine.render(text: buffer, isFinal: false)
            let stableCount = engine.stableRenderedLineCount
            XCTAssertLessThanOrEqual(stableCount, rendered.count)
            XCTAssertGreaterThanOrEqual(
                stableCount, previousStableCount,
                "stable prefix must not rewind while the buffer only grows (line \(index))"
            )
            XCTAssertEqual(
                Array(rendered.prefix(stableCount)),
                Array(finalLines.prefix(stableCount)),
                "stable lines must match the final render line-for-line (line \(index))"
            )
            previousStableCount = stableCount
        }
    }

    func testStreamingEngineStablePrefixSurvivesStableCacheReset() {
        // Exceed maxStableSourceChars (64KB) mid-stream so the engine drops
        // and rebuilds its stable cache; committed lines must not change.
        let engine = StreamingMarkdownEngine()
        var sectionLines: [String] = []
        for i in 0..<1_000 {
            sectionLines.append("## Section \(i)")
            sectionLines.append("")
            sectionLines.append("| Name   | Value |")
            sectionLines.append("| :----- | ----: |")
            sectionLines.append("| row-\(i) | \(i * 111) |")
            sectionLines.append("")
        }
        let full = sectionLines.joined(separator: "\n")
        XCTAssertGreaterThan(full.count, 65_536)

        let finalLines = engine.render(text: full, isFinal: true)
        engine.reset()

        var previousStableCount = 0
        var cursor = full.startIndex
        var buffer = ""
        while cursor < full.endIndex {
            let next = full.index(cursor, offsetBy: 4_096, limitedBy: full.endIndex) ?? full.endIndex
            buffer += full[cursor..<next]
            cursor = next
            let rendered = engine.render(text: buffer, isFinal: false)
            let stableCount = engine.stableRenderedLineCount
            XCTAssertLessThanOrEqual(stableCount, rendered.count)
            XCTAssertEqual(
                Array(rendered.prefix(stableCount)),
                Array(finalLines.prefix(stableCount)),
                "stable lines must survive the 64KB cache reset (buffer \(buffer.count) chars)"
            )
            previousStableCount = max(previousStableCount, stableCount)
        }
        XCTAssertGreaterThan(previousStableCount, 0)
    }

    func testPlainTextEngineStableLineCount() {
        let engine = PlainTextMarkdownEngine()

        _ = engine.render(text: "a", isFinal: false)
        XCTAssertEqual(engine.stableRenderedLineCount, 0)

        _ = engine.render(text: "a\nb", isFinal: false)
        XCTAssertEqual(engine.stableRenderedLineCount, 1)

        _ = engine.render(text: "a\nb\n", isFinal: false)
        XCTAssertEqual(engine.stableRenderedLineCount, 2)

        _ = engine.render(text: "", isFinal: false)
        XCTAssertEqual(engine.stableRenderedLineCount, 0)
    }
}
