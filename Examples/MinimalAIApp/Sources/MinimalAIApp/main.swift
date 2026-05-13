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

// MARK: - Commands & Keybindings

enum AppCommand: Sendable {
    case submit
    case insertNewline
    case backspace
    case deleteForward
    case moveLeft
    case moveRight
    case moveUpInBuffer
    case moveDownInBuffer
    case moveLineStart
    case moveLineEnd
    case killToLineStart
    case killToLineEnd
    case historyPrev
    case historyNext
    case clearOrCancel
    case interrupt
}

// MARK: - App State

@MainActor
final class MinimalAIApp: @unchecked Sendable {
    private let tui: TUI
    private let transcript: TranscriptRenderer
    private let layoutRenderer = ScreenLayoutRenderer()
    private var input = MultiLineInputState()
    private var history = PromptHistory()
    private var streamingTask: Task<Void, Never>?
    private var currentAssistantBlockID: String?
    private var isStreaming = false
    private let provider: MinimalAIProvider
    private var lastTerminalSize: TerminalSize?
    private let exitFlag = ExitFlag()
    private let resolver: KeyResolver<AppCommand>

    init(provider: MinimalAIProvider = FauxAIProvider()) {
        let isInteractive = isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        // Use the new physical-rows live budget so that long / wrapped streaming
        // input is settled into committed instead of being silently clipped.
        // Budget 4 means the live region (input area) can grow up to 4 physical
        // rows before head settlement kicks in.
        //
        // Use .marker positioning so multi-line wrapped input keeps the
        // hardware cursor exactly under the logical caret — important for IME
        // candidate windows when typing Chinese.
        self.tui = TUI(
            isTTY: isInteractive,
            liveBudget: 4,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker
        )
        self.provider = provider
        self.transcript = TranscriptRenderer()
        self.resolver = KeyResolver(registry: MinimalAIApp.defaultKeybindings())
    }

    static func defaultKeybindings() -> KeybindingRegistry<AppCommand> {
        var registry = KeybindingRegistry<AppCommand>()
        func bind(_ sequence: KeySequence, _ command: AppCommand) {
            do {
                try registry.register(sequence, action: command)
            } catch {
                assertionFailure("keybinding registration failed: \(error)")
            }
        }
        bind(KeySequence(KeyStroke(key: .enter)), .submit)
        bind(KeySequence(KeyStroke(key: .backspace)), .backspace)
        bind(KeySequence(KeyStroke(key: .delete)), .deleteForward)
        bind(KeySequence(KeyStroke(key: .left)), .moveLeft)
        bind(KeySequence(KeyStroke(key: .right)), .moveRight)
        bind(KeySequence(KeyStroke(key: .up)), .moveUpInBuffer)
        bind(KeySequence(KeyStroke(key: .down)), .moveDownInBuffer)
        bind(KeySequence(KeyStroke(key: .home)), .moveLineStart)
        bind(KeySequence(KeyStroke(key: .end)), .moveLineEnd)
        bind(KeySequence(KeyStroke(key: .escape)), .clearOrCancel)

        // readline-style control-letter bindings (KeyParser emits uppercase letters
        // for Ctrl- combos, so register the uppercase form).
        bind(KeySequence(KeyStroke(key: .character("O"), modifiers: .ctrl)), .insertNewline)
        bind(KeySequence(KeyStroke(key: .character("A"), modifiers: .ctrl)), .moveLineStart)
        bind(KeySequence(KeyStroke(key: .character("E"), modifiers: .ctrl)), .moveLineEnd)
        bind(KeySequence(KeyStroke(key: .character("U"), modifiers: .ctrl)), .killToLineStart)
        bind(KeySequence(KeyStroke(key: .character("K"), modifiers: .ctrl)), .killToLineEnd)
        bind(KeySequence(KeyStroke(key: .character("P"), modifiers: .ctrl)), .historyPrev)
        bind(KeySequence(KeyStroke(key: .character("N"), modifiers: .ctrl)), .historyNext)
        bind(KeySequence(KeyStroke(key: .character("C"), modifiers: .ctrl)), .interrupt)

        // Chord example: Ctrl-X Ctrl-S commits the current input (Emacs-style).
        bind(KeySequence([
            KeyStroke(key: .character("X"), modifiers: .ctrl),
            KeyStroke(key: .character("S"), modifiers: .ctrl),
        ]), .submit)

        return registry
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

        // Soft-wrap aware viewport for moveUp/Down. The input area visually
        // reserves a 2-cell prompt ("❯ ") on the first row, so the usable
        // wrap width is `width - 2` (clamped to at least 1).
        let viewportWidth = max(1, width - 2)
        if input.viewport?.width != viewportWidth {
            input.setViewport(Viewport(width: viewportWidth))
        }

        let statusLines = [
            isStreaming ? "● streaming" : "● idle",
            "pending tools: \(transcript.pendingToolCount)",
        ]

        let inputRendered = input.render()
        let prompt = Style.prompt("❯ ", mode: .automatic)
        let continuation = "  " // two ASCII spaces to mirror the visible width of "❯ "
        let inputLines: [String] = inputRendered.lines.enumerated().map { idx, line in
            idx == 0 ? prompt + line : continuation + line
        }

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
            cursorPlacement: inputRendered.cursor
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

    @discardableResult
    private func handleResolved(_ resolved: ResolvedKey<AppCommand>) -> Bool {
        switch resolved {
        case .action(let command):
            return apply(command: command)
        case .passthrough(let event):
            switch event.key {
            case .character(let c) where event.modifiers.isEmpty:
                input.handle(.insert(c))
            case .paste(let text):
                input.handle(.insertText(text))
            default:
                break
            }
            return true
        }
    }

    @discardableResult
    private func apply(command: AppCommand) -> Bool {
        switch command {
        case .submit:
            submit()
        case .insertNewline:
            input.handle(.insertNewline)
        case .backspace:
            input.handle(.backspace)
        case .deleteForward:
            input.handle(.deleteForward)
        case .moveLeft:
            input.handle(.moveLeft)
        case .moveRight:
            input.handle(.moveRight)
        case .moveUpInBuffer:
            input.handle(.moveUp)
        case .moveDownInBuffer:
            input.handle(.moveDown)
        case .moveLineStart:
            input.handle(.moveToLineStart)
        case .moveLineEnd:
            input.handle(.moveToLineEnd)
        case .killToLineStart:
            input.handle(.killToLineStart)
        case .killToLineEnd:
            input.handle(.killToLineEnd)
        case .historyPrev:
            if let text = history.prev() {
                input.handle(.replace(text))
            }
        case .historyNext:
            if let text = history.next() {
                input.handle(.replace(text))
            }
        case .clearOrCancel:
            if isStreaming {
                cancelStreaming()
            } else {
                input.handle(.clear)
            }
        case .interrupt:
            cancelStreaming()
            return false
        }
        return true
    }

    private func processEvents(_ events: [KeyEvent]) -> Bool {
        for event in events {
            for resolved in resolver.feed(event) {
                if !handleResolved(resolved) {
                    // Stop draining the rest of this batch as soon as a command
                    // requests shutdown — otherwise queued events would still be
                    // applied after we've already decided to exit.
                    return false
                }
            }
        }
        return true
    }

    private func tickResolver() {
        let resolveds = resolver.tick()
        guard !resolveds.isEmpty else { return }
        for r in resolveds {
            if !handleResolved(r) {
                exitFlag.value = true
                return
            }
        }
        render()
    }

    // MARK: - Run

    func runInteractive() throws {
        let reader = InputReader { [weak self] events in
            guard let self else { return }
            Task { @MainActor in
                let keepRunning = self.processEvents(events)
                self.render()
                if !keepRunning {
                    self.exitFlag.value = true
                }
            }
        }
        try reader.start()
        defer { reader.stop() }

        // Initial render
        render()

        // Keep the main thread alive while reader runs.
        // Periodically tick the key resolver so that chord prefix timeouts can
        // flush even when no further input arrives. The whole loop runs on the
        // MainActor (this method is @MainActor-isolated via the enclosing class),
        // so tickResolver() is invoked synchronously rather than spawning a Task
        // each tick.
        while reader.running && !exitFlag.value {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            if exitFlag.value { break }
            tickResolver()
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
