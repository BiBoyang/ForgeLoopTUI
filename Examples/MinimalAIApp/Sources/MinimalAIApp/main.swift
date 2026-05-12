import Foundation
import ForgeLoopTUI

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Minimal AI Provider Protocol

protocol MinimalAIProvider: Sendable {
    func streamReply(to prompt: String) -> AsyncStream<String>
}

// MARK: - Faux Provider (local simulation, replaceable)

struct FauxAIProvider: MinimalAIProvider {
    func streamReply(to prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                let reply = "You said: \(prompt)\n\nThis is a streaming reply powered by ForgeLoopTUI."
                let words = reply.split(separator: " ", omittingEmptySubsequences: false)
                var buffer = ""
                for (index, word) in words.enumerated() {
                    guard !Task.isCancelled else { break }
                    if index > 0 {
                        buffer += " "
                    }
                    buffer += String(word)
                    continuation.yield(buffer)
                    try? await Task.sleep(nanoseconds: 40_000_000) // 40ms per word
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Thread-safe boxes

final class ExitFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = ""

    var value: String {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private func splitPromptLines(_ text: String) -> [String] {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

// MARK: - App State

@MainActor
final class MinimalAIApp: @unchecked Sendable {
    private let tui: TUI
    private let transcript: TranscriptRenderer
    private let layoutRenderer = ScreenLayoutRenderer()
    private var input = TextInputState()
    private var history = PromptHistory()
    private var streamingTask: Task<Void, Never>?
    private var currentAssistantBlockID: String?
    private var isStreaming = false
    private let provider: MinimalAIProvider
    private var lastTerminalSize: TerminalSize?
    private let exitFlag = ExitFlag()

    init(provider: MinimalAIProvider = FauxAIProvider()) {
        let isInteractive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        self.tui = TUI(isTTY: isInteractive)
        self.provider = provider
        self.transcript = TranscriptRenderer()
    }

    // MARK: - Rendering

    private func render() {
        let size = getTerminalSize()
        let width = size?.columns ?? 80
        let height = size?.rows ?? 24

        if let newSize = size, lastTerminalSize != newSize {
            lastTerminalSize = newSize
            tui.updateTerminalSize(width: newSize.columns, height: newSize.rows)
        }

        let statusLines = [
            isStreaming ? "● streaming" : "● idle",
            "pending tools: \(transcript.pendingToolCount)",
        ]

        let inputRendered = input.render(
            prefix: Style.prompt("❯ ", mode: .automatic),
            totalWidth: width
        )
        let inputLines = [inputRendered.line]

        let layout = ScreenLayout(
            header: [],
            transcript: transcript.transcriptLines,
            queue: [],
            status: statusLines,
            input: inputLines,
            pinnedTranscriptRange: transcript.preferredPinnedRange
        )

        let config = ScreenLayoutConfig(
            terminalHeight: height,
            terminalWidth: width,
            showHeader: false
        )

        let frame = layoutRenderer.render(
            layout: layout,
            config: config,
            cursorOffset: inputRendered.cursorOffset
        )
        tui.render(frame: frame)
    }

    // MARK: - Streaming

    private func startAssistantStreaming(prompt: String) {
        let blockID = "assistant-\(UUID().uuidString)"
        currentAssistantBlockID = blockID
        isStreaming = true

        transcript.applyCore(.blockStart(id: blockID))
        render()

        streamingTask = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            for await token in self.provider.streamReply(to: prompt) {
                guard !Task.isCancelled else { break }
                buffer = token
                await MainActor.run {
                    self.transcript.applyCore(.blockUpdate(id: blockID, lines: [buffer]))
                    self.render()
                }
            }

            await MainActor.run {
                self.transcript.applyCore(.blockEnd(id: blockID, lines: [buffer], footer: nil))
                if self.currentAssistantBlockID == blockID {
                    self.isStreaming = false
                    self.currentAssistantBlockID = nil
                    self.streamingTask = nil
                }
                self.render()
            }
        }
    }

    private func cancelStreaming() {
        streamingTask?.cancel()
        transcript.applyCore(.notification(text: "cancelled"))
    }

    // MARK: - Submission

    private func submit() {
        let submitted = input.text
        history.commit(submitted)
        input.handle(.clear)
        render()

        guard !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        transcript.applyCore(.insert(
            lines: splitPromptLines(submitted).map { "\(Style.prompt("❯ ", mode: .automatic))\($0)" }
        ))
        render()

        if let task = streamingTask {
            task.cancel()
        }
        startAssistantStreaming(prompt: submitted)
    }

    // MARK: - Input Handling

    private func handleKeyEvent(_ event: KeyEvent) -> Bool {
        if case .character(let c) = event.key,
           event.modifiers.contains(.ctrl),
           (c == "c" || c == "C")
        {
            cancelStreaming()
            return false
        }

        switch (event.key, event.modifiers) {
        case (.character(let c), []):
            input.handle(.insert(c))
            render()

        case (.backspace, []):
            input.handle(.backspace)
            render()

        case (.delete, []):
            input.handle(.deleteForward)
            render()

        case (.left, []):
            input.handle(.moveLeft)
            render()

        case (.right, []):
            input.handle(.moveRight)
            render()

        case (.home, []):
            input.handle(.moveToStart)
            render()

        case (.end, []):
            input.handle(.moveToEnd)
            render()

        case (.enter, []):
            submit()

        case (.up, []):
            if let text = history.prev() {
                input.handle(.replace(text))
                render()
            }

        case (.down, []):
            if let text = history.next() {
                input.handle(.replace(text))
                render()
            } else if history.isAtCurrent {
                input.handle(.clear)
                render()
            }

        case (.escape, []):
            if isStreaming {
                cancelStreaming()
                render()
            } else {
                input.handle(.clear)
                render()
            }

        default:
            break
        }
        return true
    }

    // MARK: - Run

    func runInteractive() throws {
        let reader = InputReader { [weak self] events in
            guard let self else { return }
            Task { @MainActor in
                for event in events {
                    let keepRunning = self.handleKeyEvent(event)
                    if !keepRunning {
                        self.exitFlag.value = true
                        return
                    }
                }
            }
        }
        try reader.start()
        defer { reader.stop() }

        // Initial render
        render()

        // Keep the main thread alive while reader runs
        while reader.running && !exitFlag.value {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
    }

    func runNonInteractive() {
        var prompt = ""
        while let line = readLine() {
            if !prompt.isEmpty {
                prompt += "\n"
            }
            prompt += line
        }

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox()

        Task.detached { [provider = self.provider] in
            for await token in provider.streamReply(to: prompt) {
                resultBox.value = token
            }
            semaphore.signal()
        }

        semaphore.wait()
        print(resultBox.value)
    }
}

// MARK: - Entry Point

@main
struct Entry {
    static func main() {
        let app = MinimalAIApp()
        let isInteractive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1

        if isInteractive {
            do {
                try app.runInteractive()
            } catch {
                fputs("Error: \(error)\n", stderr)
                exit(1)
            }
        } else {
            app.runNonInteractive()
        }
    }
}
