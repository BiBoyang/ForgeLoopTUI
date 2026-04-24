import Foundation
import ForgeLoopTUI

func splitFixtureLines(_ text: String) -> [String] {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

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
    let tui = TUI(isTTY: isatty(STDOUT_FILENO) == 1)
    let renderer = TranscriptRenderer()
    var appendState = StreamingTranscriptAppendState()
    let fixtureURL = resolveFixtureURL(from: CommandLine.arguments)
    let fixtureText = try String(contentsOf: fixtureURL, encoding: .utf8)
    let fixtureLines = splitFixtureLines(fixtureText)

    func appendTranscriptDelta() {
        let delta = appendState.consume(
            transcript: renderer.transcriptLines,
            activeRange: renderer.activeStreamingRange
        )
        if !delta.isEmpty {
            tui.appendFrame(lines: delta)
        }
    }

    renderer.applyCore(.insert(
        lines: prefixedLogicalLines(
            prefix: Style.user("❯ "),
            text: "stream fixture: \(fixtureURL.lastPathComponent)"
        ) + [""]
    ))
    appendTranscriptDelta()

    renderer.applyCore(.blockStart(id: "demo"))

    var accumulatedLines: [String] = []
    for line in fixtureLines {
        accumulatedLines.append(line)
        renderer.applyCore(.blockUpdate(id: "demo", lines: accumulatedLines))
        appendTranscriptDelta()
        usleep(20_000)
    }

    renderer.applyCore(.blockEnd(id: "demo", lines: accumulatedLines, footer: nil))

    let finalDelta = appendState.consume(
        transcript: renderer.transcriptLines,
        activeRange: nil
    )
    if !finalDelta.isEmpty {
        tui.appendFrame(lines: finalDelta)
    }

    renderer.applyCore(.operationStart(id: "readme", header: #"● read({"path":"README.md"})"#, status: "⎿ running..."))
    renderer.applyCore(.operationEnd(id: "readme", isError: false, result: "Loaded \(fixtureLines.count) fixture lines"))
    tui.appendFrame(lines: Array(renderer.transcriptLines.suffix(2)))
}

do {
    try runDemo()
} catch {
    fputs("Demo failed: \(error)\n", stderr)
    exit(1)
}
