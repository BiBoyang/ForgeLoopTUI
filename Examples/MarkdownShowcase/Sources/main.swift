import Foundation
import ForgeLoopTUI

struct FixtureSpec {
    let label: String
    let url: URL
}

func splitFixtureLines(_ text: String) -> [String] {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

func builtinFixtureSpec(named name: String) -> FixtureSpec? {
    switch name.lowercased() {
    case "showcase", "table-showcase":
        return FixtureSpec(
            label: "table-showcase",
            url: URL(fileURLWithPath: "../Fixtures/markdown-table-showcase.md").standardizedFileURL
        )
    case "edge", "edge-cases", "table-edge-cases":
        return FixtureSpec(
            label: "table-edge-cases",
            url: URL(fileURLWithPath: "../Fixtures/markdown-table-edge-cases.md").standardizedFileURL
        )
    case "long", "long-mixed", "long-mixed-showcase":
        return FixtureSpec(
            label: "long-mixed-showcase",
            url: URL(fileURLWithPath: "../Fixtures/markdown-long-mixed-showcase.md").standardizedFileURL
        )
    case "narrow", "narrow-terminal", "narrow-terminal-showcase":
        return FixtureSpec(
            label: "narrow-terminal-showcase",
            url: URL(fileURLWithPath: "../Fixtures/markdown-narrow-terminal-showcase.md").standardizedFileURL
        )
    case "sample", "markdownview-sample":
        return FixtureSpec(
            label: "markdownview-sample",
            url: URL(fileURLWithPath: "../Fixtures/markdownview-sample.md").standardizedFileURL
        )
    default:
        return nil
    }
}

func resolveFixtureSpec(from argument: String) -> FixtureSpec {
    if let builtin = builtinFixtureSpec(named: argument) {
        return builtin
    }

    let url: URL
    if argument.hasPrefix("/") {
        url = URL(fileURLWithPath: argument).standardizedFileURL
    } else {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(argument)
            .standardizedFileURL
    }

    return FixtureSpec(label: url.lastPathComponent, url: url)
}

func resolveFixtureSpecs(from arguments: [String]) -> [FixtureSpec] {
    let requested = Array(arguments.dropFirst())
    if requested.isEmpty {
        return [builtinFixtureSpec(named: "showcase")!]
    }

    if requested == ["--all"] {
        return [
            builtinFixtureSpec(named: "showcase")!,
            builtinFixtureSpec(named: "edge-cases")!,
            builtinFixtureSpec(named: "long-mixed")!,
            builtinFixtureSpec(named: "narrow-terminal")!,
        ]
    }

    return requested.map(resolveFixtureSpec(from:))
}

@MainActor
func runShowcase(with fixtures: [FixtureSpec]) throws {
    let renderer = TranscriptRenderer()

    for (index, fixture) in fixtures.enumerated() {
        let fixtureText = try String(contentsOf: fixture.url, encoding: .utf8)
        let fixtureLines = splitFixtureLines(fixtureText)

        renderer.applyCore(.insert(
            lines: prefixedLogicalLines(
                prefix: Style.user("❯ "),
                text: "show markdown fixture: \(fixture.label)"
            ) + [""]
        ))
        renderer.applyCore(.blockStart(id: "showcase-\(index)"))
        renderer.applyCore(.blockUpdate(id: "showcase-\(index)", lines: fixtureLines))
        renderer.applyCore(.blockEnd(id: "showcase-\(index)", lines: fixtureLines, footer: nil))

        if index < fixtures.count - 1 {
            renderer.applyCore(.insert(lines: [""]))
        }
    }

    let output = renderer.transcriptLines.joined(separator: "\n") + "\n"
    FileHandle.standardOutput.write(Data(output.utf8))
}

do {
    try runShowcase(with: resolveFixtureSpecs(from: CommandLine.arguments))
} catch {
    fputs("MarkdownShowcase failed: \(error)\n", stderr)
    exit(1)
}
