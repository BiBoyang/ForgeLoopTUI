import XCTest
@testable import ForgeLoopTUI

/// End-to-end snapshot tests: feed CoreRenderEvents through the full
/// TranscriptRenderer → ScreenLayoutRenderer → VirtualTerminal pipeline
/// and compare VirtualTerminal.buffer against known-good references.
@MainActor
final class SnapshotTests: XCTestCase {

    func testBasicAssistantStreamingE2E() {
        let renderer = TranscriptRenderer()
        let layoutRenderer = ScreenLayoutRenderer()
        let vt = VirtualTerminal(width: 40, height: 10)
        let tui = TUI(isTTY: true, terminal: vt)

        // Simulate a user message + assistant streaming response
        renderer.applyCore(.insert(lines: ["❯ Hello"]))
        renderer.applyCore(.insert(lines: [""]))
        renderer.applyCore(.blockStart(id: "msg1"))
        renderer.applyCore(.blockUpdate(id: "msg1", lines: ["Hi there!"]))
        renderer.applyCore(.blockEnd(id: "msg1", lines: ["Hi there!"], footer: nil))

        let layout = ScreenLayout(
            transcript: renderer.transcriptLines
        )
        let config = ScreenLayoutConfig(terminalHeight: 10, terminalWidth: 40, showHeader: false)
        let frame = layoutRenderer.render(layout: layout, config: config)
        tui.render(frame: frame)

        let buffer = vt.buffer
        XCTAssertTrue(buffer.contains("❯ Hello"))
        XCTAssertTrue(buffer.contains("Hi there!"))
    }

    func testToolExecutionAppearsInSnapshot() {
        let renderer = TranscriptRenderer()
        let layoutRenderer = ScreenLayoutRenderer()
        let vt = VirtualTerminal(width: 40, height: 10)
        let tui = TUI(isTTY: true, terminal: vt)

        renderer.applyCore(.insert(lines: ["❯ read file.txt"]))
        renderer.applyCore(.operationStart(id: "t1", header: "● read({\"path\":\"file.txt\"})", status: "⎿ running..."))
        renderer.applyCore(.operationEnd(id: "t1", isError: false, result: "hello world"))

        let layout = ScreenLayout(
            transcript: renderer.transcriptLines
        )
        let config = ScreenLayoutConfig(terminalHeight: 10, terminalWidth: 40, showHeader: false)
        let frame = layoutRenderer.render(layout: layout, config: config)
        tui.render(frame: frame)

        let buffer = vt.buffer
        XCTAssertTrue(buffer.contains("● read"))
        XCTAssertTrue(buffer.contains("done: hello world"))
    }

    func testBlockCancelRemovesStreamingContent() {
        let renderer = TranscriptRenderer()
        let layoutRenderer = ScreenLayoutRenderer()
        let vt = VirtualTerminal(width: 40, height: 10)
        let tui = TUI(isTTY: true, terminal: vt)

        renderer.applyCore(.blockStart(id: "b1"))
        renderer.applyCore(.blockUpdate(id: "b1", lines: ["discard this"]))
        renderer.applyCore(.blockCancel(id: "b1"))

        let layout = ScreenLayout(
            transcript: renderer.transcriptLines
        )
        let config = ScreenLayoutConfig(terminalHeight: 10, terminalWidth: 40, showHeader: false)
        let frame = layoutRenderer.render(layout: layout, config: config)
        tui.render(frame: frame)

        let buffer = vt.buffer
        XCTAssertTrue(buffer.contains("[cancelled]"))
        XCTAssertFalse(buffer.contains("discard this"))
    }
}
