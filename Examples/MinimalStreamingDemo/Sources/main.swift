import Foundation
import ForgeLoopTUI

func resolveFixtureURL(from arguments: [String]) -> URL {
    if arguments.count > 1 {
        let path = arguments[1]
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    return URL(fileURLWithPath: "../Fixtures/long-transcript.md").standardizedFileURL
}

@MainActor
func runDemo() throws {
    let tui = TUI()
    let renderer = TranscriptRenderer()
    var appendState = StreamingTranscriptAppendState()
    let fixtureURL = resolveFixtureURL(from: CommandLine.arguments)
    let fixtureText = try String(contentsOf: fixtureURL, encoding: .utf8)
    let fixtureLines = splitLogicalLines(fixtureText)

    func appendTranscriptDelta() {
        let delta = appendState.consume(
            transcript: renderer.lines.all,
            activeRange: renderer.activeStreamingRange
        )
        if !delta.isEmpty {
            tui.appendFrame(lines: delta)
        }
    }

    renderer.apply(.messageStart(message: .user("stream fixture: \(fixtureURL.lastPathComponent)")))
    appendTranscriptDelta()

    renderer.apply(.messageStart(message: .assistant(text: "", errorMessage: nil)))

    var accumulatedLines: [String] = []
    for line in fixtureLines {
        accumulatedLines.append(line)
        renderer.apply(.messageUpdate(message: .assistant(
            text: accumulatedLines.joined(separator: "\n"),
            errorMessage: nil
        )))
        appendTranscriptDelta()
        usleep(20_000)
    }

    renderer.apply(.messageEnd(message: .assistant(
        text: accumulatedLines.joined(separator: "\n"),
        errorMessage: nil
    )))

    let finalDelta = appendState.consume(
        transcript: renderer.lines.all,
        activeRange: nil
    )
    if !finalDelta.isEmpty {
        tui.appendFrame(lines: finalDelta)
    }

    renderer.apply(.toolExecutionStart(toolCallId: "readme", toolName: "read", args: #"{"path":"README.md"}"#))
    renderer.apply(.toolExecutionEnd(
        toolCallId: "readme",
        toolName: "read",
        isError: false,
        summary: "Loaded \(fixtureLines.count) fixture lines"
    ))
    tui.appendFrame(lines: Array(renderer.lines.all.suffix(2)))
}

do {
    try runDemo()
} catch {
    fputs("Demo failed: \(error)\n", stderr)
    exit(1)
}
