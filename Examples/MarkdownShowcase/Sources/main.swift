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

    return URL(fileURLWithPath: "../Fixtures/markdownview-sample.md").standardizedFileURL
}

@MainActor
func runShowcase() throws {
    let tui = TUI()
    let renderer = TranscriptRenderer()
    let fixtureURL = resolveFixtureURL(from: CommandLine.arguments)
    let fixtureText = try String(contentsOf: fixtureURL, encoding: .utf8)

    renderer.apply(.messageStart(message: .user("show markdown fixture: \(fixtureURL.lastPathComponent)")))
    renderer.apply(.messageStart(message: .assistant(text: "", errorMessage: nil)))
    renderer.apply(.messageUpdate(message: .assistant(text: fixtureText, errorMessage: nil)))
    renderer.apply(.messageEnd(message: .assistant(text: fixtureText, errorMessage: nil)))

    tui.requestRender(lines: renderer.transcriptLines)
}

do {
    try runShowcase()
} catch {
    fputs("MarkdownShowcase failed: \(error)\n", stderr)
    exit(1)
}
