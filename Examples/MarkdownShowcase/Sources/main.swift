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

    return URL(fileURLWithPath: "../Fixtures/markdown-table-showcase.md").standardizedFileURL
}

@MainActor
func runShowcase() throws {
    let renderer = TranscriptRenderer()
    let fixtureURL = resolveFixtureURL(from: CommandLine.arguments)
    let fixtureText = try String(contentsOf: fixtureURL, encoding: .utf8)
    let fixtureLines = splitFixtureLines(fixtureText)

    renderer.applyCore(.insert(
        lines: prefixedLogicalLines(
            prefix: Style.user("❯ "),
            text: "show markdown fixture: \(fixtureURL.lastPathComponent)"
        ) + [""]
    ))
    renderer.applyCore(.blockStart(id: "showcase"))
    renderer.applyCore(.blockUpdate(id: "showcase", lines: fixtureLines))
    renderer.applyCore(.blockEnd(id: "showcase", lines: fixtureLines, footer: nil))

    let output = renderer.transcriptLines.joined(separator: "\n") + "\n"
    FileHandle.standardOutput.write(Data(output.utf8))
}

do {
    try runShowcase()
} catch {
    fputs("MarkdownShowcase failed: \(error)\n", stderr)
    exit(1)
}
