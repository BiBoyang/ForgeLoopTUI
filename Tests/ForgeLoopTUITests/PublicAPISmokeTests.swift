import XCTest
import ForgeLoopTUI

private final class OutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    func record(_ chunk: String) {
        lock.lock()
        chunks.append(chunk)
        lock.unlock()
    }

    var allChunks: [String] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }
}

@MainActor
final class PublicAPISmokeTests: XCTestCase {
    func testCoreSurfaceSupportsMinimalConsumerFlow() {
        let recorder = OutputRecorder()
        let tui = TUI(isTTY: false, writer: { recorder.record($0) })
        let renderer = TranscriptRenderer(markdownEngine: PlainTextMarkdownEngine())
        var appendState = StreamingTranscriptAppendState()

        renderer.applyCore(.insert(
            lines: prefixedLogicalLines(prefix: Style.user("❯ "), text: "demo prompt") + [""]
        ))
        renderer.applyCore(.blockStart(id: "assistant"))
        renderer.applyCore(.blockUpdate(id: "assistant", lines: ["hello", "world"]))

        let streamingDelta = appendState.consume(
            transcript: renderer.transcriptLines,
            activeRange: renderer.activeStreamingRange
        )
        tui.appendFrame(lines: streamingDelta)

        renderer.applyCore(.blockEnd(id: "assistant", lines: ["hello", "world"], footer: nil))
        renderer.applyCore(.operationStart(id: "tool", header: "● read({})", status: "⎿ running..."))
        renderer.applyCore(.operationEnd(id: "tool", isError: false, result: "Loaded 2 lines"))
        tui.requestRender(lines: renderer.transcriptLines)

        XCTAssertEqual(renderer.pendingToolCount, 0)
        XCTAssertTrue(renderer.transcriptLines.contains("❯ demo prompt"))
        XCTAssertTrue(renderer.transcriptLines.contains("hello"))
        XCTAssertTrue(renderer.transcriptLines.contains("⎿ done: Loaded 2 lines"))
        XCTAssertFalse(recorder.allChunks.isEmpty)
    }

    func testInteractionSurfaceSupportsInputAndPickerFlow() {
        var input = TextInputState(text: "demo 中文 prompt")
        input.handle(.moveToEnd)
        let renderedInput = input.render(prefix: Style.prompt("❯ ", mode: .plain), totalWidth: 12)

        var picker = ListPickerState(
            title: "Select a model",
            subtitle: "provider: openai",
            items: [
                .init(id: "gpt-4.1", title: "gpt-4.1"),
                .init(id: "gpt-4o", title: "gpt-4o"),
            ],
            selectedIndex: 0
        )

        _ = picker.handle(.moveDown)
        let pickerLines = ListPickerRenderer(styleMode: .plain).render(state: picker)

        XCTAssertTrue(renderedInput.line.hasPrefix("❯ "))
        XCTAssertEqual(renderedInput.cursorOffset, 0)
        XCTAssertEqual(picker.selectedItem?.id, "gpt-4o")
        XCTAssertEqual(pickerLines.first, "Select a model")
        XCTAssertTrue(pickerLines.contains("● gpt-4o"))
    }
}
