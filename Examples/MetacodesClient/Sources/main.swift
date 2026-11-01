// MetacodesClient — ForgeLoopTUI as a foreign-language wire client for metacodes.
//
// This example connects to a running `metacodes serve --uds <sock>` daemon and
// projects its journal (wire v1 NDJSON lines) into a ForgeLoopTUI transcript:
//
//   attach (UDS)            → replay + live event stream
//   message/interrupt (UDS) → submit a prompt / stop the current run
//   ui_request (wire line)  → permission prompt answered over HTTP POST /s/<id>/respond
//                             (the UDS binding has no respond op today — wall #1)
//
// Zero changes to metacodes: everything here consumes the surface as shipped.
//
// Usage:
//   metacodes-client <uds-socket-path> [--session <id>] [--http <port>] [--since <n>]
//
// Keys: Enter submit · Esc interrupt current run · y/n/a answer a pending
// permission request (when input is empty) · Ctrl+C quit.

import Foundation
import ForgeLoopTUI

import Darwin

// MARK: - Wire message (Sendable projection of one journal line)

enum WireMsg: Sendable {
    case userMessage(String)
    case runDone(stop: String?, err: String?)
    case sessionLifecycle(String)
    case streamBegin
    case streamDone
    case segmentBegin(index: Int)
    case segmentEnd(index: Int, disposition: String)
    case textChunk(String)
    case thinkingChunk(String)
    case toolStart(id: String, name: String, input: String)
    case toolResult(id: String, name: String, isError: Bool, content: String)
    case usage(input: Int, output: Int)
    case uiRequest(id: UInt64, kind: String, summary: String)
    case uiRequestClosed(id: UInt64, outcome: String)
    case notice(String)
    case ignored
}

enum WireParser {
    /// Parse one NDJSON journal line. Tolerates both envelopes the daemon
    /// emits today: wire v1 ({"v":1,"type":...,"data":...} / ui_request lines)
    /// and the session driver's bare host envelopes ({"user_message": ...},
    /// {"run_done": {...}}, {"session_lifecycle": {...}}).
    static func parse(_ line: Data) -> WireMsg {
        guard let any = try? JSONSerialization.jsonObject(with: line),
              let obj = any as? [String: Any] else { return .notice("<non-json line>") }

        // Bare host envelopes (no "type").
        if obj["type"] == nil {
            if let text = obj["user_message"] as? String { return .userMessage(text) }
            if let done = obj["run_done"] as? [String: Any] {
                return .runDone(stop: done["stop_reason"] as? String, err: done["err"] as? String)
            }
            if let lifecycle = obj["session_lifecycle"] as? [String: Any] {
                let what = lifecycle.keys.first ?? "?"
                return .sessionLifecycle(what)
            }
            return .ignored
        }

        let type = obj["type"] as? String ?? "?"
        let data = obj["data"]

        switch type {
        case "keepalive": return .ignored
        case "stream_begin": return .streamBegin
        case "stream_done": return .streamDone
        case "text_chunk": return .textChunk(data as? String ?? "")
        case "thinking_chunk": return .thinkingChunk(data as? String ?? "")
        case "output_segment_begin":
            let d = data as? [String: Any]
            return .segmentBegin(index: (d?["index"] as? Int) ?? 0)
        case "output_segment_end":
            let d = data as? [String: Any]
            return .segmentEnd(
                index: (d?["index"] as? Int) ?? 0,
                disposition: (d?["disposition"] as? String) ?? "final"
            )
        case "tool_start":
            let d = data as? [String: Any]
            return .toolStart(
                id: (d?["id"] as? String) ?? "?",
                name: (d?["name"] as? String) ?? "?",
                input: (d?["input"] as? String) ?? ""
            )
        case "tool_result":
            let d = data as? [String: Any]
            return .toolResult(
                id: (d?["id"] as? String) ?? "?",
                name: (d?["name"] as? String) ?? "?",
                isError: (d?["is_error"] as? Bool) ?? false,
                content: (d?["content"] as? String) ?? ""
            )
        case "usage":
            let d = data as? [String: Any]
            return .usage(
                input: (d?["input_tokens"] as? Int) ?? 0,
                output: (d?["output_tokens"] as? Int) ?? 0
            )
        case "ui_request":
            let id = (obj["id"] as? NSNumber)?.uint64Value ?? 0
            let kind = obj["kind"] as? String ?? "?"
            var summary = kind
            if let req = obj["request"] as? [String: Any] {
                if kind == "permission" {
                    let tool = req["tool"] as? String ?? "?"
                    let args = req["args"] as? String ?? ""
                    summary = "\(tool) \(args.prefix(120))"
                } else {
                    summary = "\(kind) (unsupported in this client)"
                }
            }
            return .uiRequest(id: id, kind: kind, summary: summary)
        case "ui_request_closed":
            let id = (obj["id"] as? NSNumber)?.uint64Value ?? 0
            return .uiRequestClosed(id: id, outcome: obj["outcome"] as? String ?? "?")
        case "context_warning", "auto_compact", "retry_notice", "environment_fault",
             "context_projection":
            return .notice("\(type): \(compact(data))")
        default:
            return .ignored // diag_*, progress, set/clear_current_tool, config_changed, …
        }
    }

    private static func compact(_ any: Any?) -> String {
        guard let any,
              let data = try? JSONSerialization.data(withJSONObject: any),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(140))
    }
}

// MARK: - UDS plumbing (blocking POSIX sockets; one connection per op, plus a
// long-lived attach connection)

enum UDS {
    static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let bytes = Array(path.utf8CString)
        guard bytes.count <= maxLen + 1 else { close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            for (i, c) in bytes.enumerated() { dst[i] = UInt8(bitPattern: c) }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, size)
            }
        }
        guard result == 0 else { close(fd); return nil }
        return fd
    }

    static func sendLine(_ fd: Int32, _ object: [String: Any]) -> Bool {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        data.append(0x0A)
        return data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// One-shot op: connect → send one line → read one reply line → close.
    static func request(_ path: String, _ object: [String: Any]) -> [String: Any]? {
        guard let fd = connect(path) else { return nil }
        defer { close(fd) }
        guard sendLine(fd, object) else { return nil }
        var buf = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buf.append(byte)
        }
        guard !buf.isEmpty,
              let any = try? JSONSerialization.jsonObject(with: buf) else { return nil }
        return any as? [String: Any]
    }
}

// MARK: - Config

struct ClientConfig: Sendable {
    var socketPath: String
    var sessionID: String
    var httpPort: Int
    var since: Int
}

// MARK: - App

@MainActor
final class MetacodesClientApp {
    private let tui: TUI
    private let transcript = TranscriptRenderer()
    private var appendState = StreamingTranscriptAppendState()
    private var input = MultiLineInputState()
    private var history = PromptHistory()
    private let resolver: KeyResolver<Command>
    private let config: ClientConfig
    private var lastTerminalSize: TerminalSize?
    private var shouldExit = false
    private var winchSource: DispatchSourceSignal?

    // Streaming projection state.
    private var activeBlockID: String?
    private var buffer = ""
    private var thinkingBuffer = ""
    private var isRunning = false
    private var currentToolCount = 0
    private var tokensIn = 0
    private var tokensOut = 0
    private var pendingPermission: (id: UInt64, summary: String)?

    enum Command: Sendable {
        case submit, backspace, deleteForward, moveLeft, moveRight, moveUp, moveDown
        case lineStart, lineEnd, killToStart, killToEnd, historyPrev, historyNext
        case escape, quit, insertNewline
    }

    // Debug tap (MC_DEBUG_LOG=path): one line per TUI interaction, so a pty
    // harness can reconstruct exactly which call emitted which frame.
    nonisolated(unsafe) static var debugHandle: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["MC_DEBUG_LOG"] else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    nonisolated static func dlog(_ line: @autoclosure () -> String) {
        guard let handle = debugHandle else { return }
        handle.write((line() + "\n").data(using: .utf8)!)
    }

    init(config: ClientConfig) {
        self.config = config
        self.tui = TUI(
            isTTY: isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1,
            liveBudget: 4,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker
        )
        if Self.debugHandle != nil {
            tui.diagnosticsHandler = { diagnostic in
                Self.dlog("diag \(diagnostic)")
            }
        }
        var registry = KeybindingRegistry<Command>()
        func bind(_ stroke: KeyStroke, _ command: Command) {
            try? registry.register(KeySequence(stroke), action: command)
        }
        bind(KeyStroke(key: .enter), .submit)
        bind(KeyStroke(key: .backspace), .backspace)
        bind(KeyStroke(key: .delete), .deleteForward)
        bind(KeyStroke(key: .left), .moveLeft)
        bind(KeyStroke(key: .right), .moveRight)
        bind(KeyStroke(key: .up), .moveUp)
        bind(KeyStroke(key: .down), .moveDown)
        bind(KeyStroke(key: .home), .lineStart)
        bind(KeyStroke(key: .end), .lineEnd)
        bind(KeyStroke(key: .escape), .escape)
        bind(KeyStroke(key: .character("A"), modifiers: .ctrl), .lineStart)
        bind(KeyStroke(key: .character("E"), modifiers: .ctrl), .lineEnd)
        bind(KeyStroke(key: .character("U"), modifiers: .ctrl), .killToStart)
        bind(KeyStroke(key: .character("K"), modifiers: .ctrl), .killToEnd)
        bind(KeyStroke(key: .character("P"), modifiers: .ctrl), .historyPrev)
        bind(KeyStroke(key: .character("N"), modifiers: .ctrl), .historyNext)
        bind(KeyStroke(key: .character("O"), modifiers: .ctrl), .insertNewline)
        bind(KeyStroke(key: .character("C"), modifiers: .ctrl), .quit)
        self.resolver = KeyResolver(registry: registry)
    }

    // MARK: Wire ingestion

    func handle(_ msg: WireMsg) {
        switch msg {
        case .userMessage(let text):
            // The journal echoes every accepted submission; the client never
            // locally echoes, so the transcript has a single source of truth.
            let prompt = Style.prompt("❯ ", mode: .automatic)
            transcript.applyCore(.insert(lines: text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(prompt)\($0)" }))
            isRunning = true
        case .runDone(let stop, let err):
            isRunning = false
            finishThinkingIfNeeded()
            // Not a .notification: those live in a capped FIFO and a busy run
            // (session created / permission / answered) already fills it — the
            // run boundary must never be the line that gets dropped.
            if let err { transcript.applyCore(.insert(lines: ["✖ run failed: \(err)"])) }
            else { transcript.applyCore(.insert(lines: ["— run done (\(stop ?? "?")) —"])) }
        case .sessionLifecycle(let what):
            transcript.applyCore(.notification(text: "session \(what)"))
        case .streamBegin:
            isRunning = true
        case .streamDone:
            finishThinkingIfNeeded()
        case .segmentBegin(let index):
            buffer = ""
            activeBlockID = "seg-\(index)"
            transcript.applyCore(.blockStart(id: activeBlockID!))
        case .textChunk(let text):
            guard !text.isEmpty else { break }
            if activeBlockID == nil {
                activeBlockID = "seg-?"
                transcript.applyCore(.blockStart(id: activeBlockID!))
            }
            buffer += text
            transcript.applyCore(.blockUpdate(id: activeBlockID!, lines: bufferLines()))
        case .thinkingChunk(let text):
            thinkingBuffer += text
            transcript.applyCore(.thinking(content: thinkingBuffer, isFinal: false))
        case .segmentEnd(_, let disposition):
            guard let id = activeBlockID else { break }
            switch disposition {
            case "discarded":
                // The protocol's discard semantics: drop the buffered bytes.
                transcript.applyCore(.blockCancel(id: id))
            case "partial":
                // blockEnd's footer renders as an error footer — appropriate
                // only for an interrupted segment.
                transcript.applyCore(.blockEnd(id: id, lines: bufferLines(), footer: "interrupted"))
            default: // final / commentary / continued are all fine text.
                transcript.applyCore(.blockEnd(id: id, lines: bufferLines(), footer: nil))
            }
            activeBlockID = nil
            buffer = ""
        case .toolStart(let id, let name, let inputJSON):
            currentToolCount += 1
            let preview = inputJSON.prefix(80)
            transcript.applyCore(.operationStart(
                id: id,
                header: "● \(name)(\(preview))",
                status: "⎿ running…"
            ))
        case .toolResult(let id, _, let isError, let content):
            transcript.applyCore(.operationEnd(
                id: id,
                isError: isError,
                result: Self.toolResultPreview(content)
            ))
        case .usage(let input, let output):
            tokensIn += input
            tokensOut += output
        case .uiRequest(let id, let kind, let summary):
            if kind == "permission" {
                pendingPermission = (id, summary)
                transcript.applyCore(.notification(
                    text: "permission #\(id): \(summary) — y allow / a always / n deny"))
            } else {
                transcript.applyCore(.notification(
                    text: "ui_request #\(id) kind=\(kind): not supported by this client"))
            }
        case .uiRequestClosed(let id, let outcome):
            if pendingPermission?.id == id { pendingPermission = nil }
            transcript.applyCore(.notification(text: "request #\(id) \(outcome)"))
        case .notice(let text):
            transcript.applyCore(.notification(text: text))
        case .ignored:
            return
        }
        render()
    }

    private func bufferLines() -> [String] {
        buffer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func finishThinkingIfNeeded() {
        guard !thinkingBuffer.isEmpty else { return }
        transcript.applyCore(.thinking(content: thinkingBuffer, isFinal: true))
        thinkingBuffer = ""
    }

    private static func toolResultPreview(_ content: String) -> String {
        // Bash results arrive as metacodes.bash-result.v2 JSON; show stdout.
        if let data = content.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let stdout = obj["stdout"] as? String {
                let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "(no output)" : String(trimmed.prefix(400))
            }
        }
        return String(content.prefix(400))
    }

    // MARK: Outbound ops

    private func submit() {
        let text = input.text
        // Bare y/n/a with a pending permission answers it instead of chatting.
        if let pending = pendingPermission,
           ["y", "n", "a", "s"].contains(text.trimmingCharacters(in: .whitespaces).lowercased()) {
            let choice: String
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "y": choice = "allow_once"
            case "a": choice = "allow_always"
            case "s": choice = "deny_tool_session"
            default: choice = "deny_once"
            }
            input.handle(.clear)
            respondPermission(id: pending.id, choice: choice)
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.commit(text)
        input.handle(.clear)
        render()
        let cfg = config
        Task.detached {
            let reply = UDS.request(cfg.socketPath, [
                "op": "message", "session": cfg.sessionID, "text": text,
            ])
            let ok = (reply?["ok"] as? Bool) ?? false
            if !ok {
                let detail = (reply?["error"] as? String) ?? "no ack"
                await MainActor.run { [weak self] in
                    self?.transcript.applyCore(.notification(text: "submit failed: \(detail)"))
                    self?.render()
                }
            }
        }
    }

    private func interrupt() {
        let cfg = config
        Task.detached {
            _ = UDS.request(cfg.socketPath, ["op": "interrupt", "session": cfg.sessionID])
        }
        transcript.applyCore(.notification(text: "interrupt requested"))
        render()
    }

    /// Wall #1 made visible: the UDS binding has no respond op, so permission
    /// answers travel over the HTTP binding instead.
    private func respondPermission(id: UInt64, choice: String) {
        let cfg = config
        Task.detached {
            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(cfg.httpPort)/s/\(cfg.sessionID)/respond")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "id": id, "choice": choice,
            ])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: Input handling (same skeleton as MinimalAIApp)

    private func apply(_ command: Command) -> Bool {
        switch command {
        case .submit: submit()
        case .backspace: input.handle(.backspace)
        case .deleteForward: input.handle(.deleteForward)
        case .moveLeft: input.handle(.moveLeft)
        case .moveRight: input.handle(.moveRight)
        case .moveUp: input.handle(.moveUp)
        case .moveDown: input.handle(.moveDown)
        case .lineStart: input.handle(.moveToLineStart)
        case .lineEnd: input.handle(.moveToLineEnd)
        case .killToStart: input.handle(.killToLineStart)
        case .killToEnd: input.handle(.killToLineEnd)
        case .historyPrev: if let text = history.prev() { input.handle(.replace(text)) }
        case .historyNext: if let text = history.next() { input.handle(.replace(text)) }
        case .insertNewline: input.handle(.insertNewline)
        case .escape:
            if isRunning { interrupt() } else { input.handle(.clear) }
        case .quit:
            return false
        }
        return true
    }

    private func handleResolved(_ resolved: ResolvedKey<Command>) -> Bool {
        switch resolved {
        case .action(let command):
            return apply(command)
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

    private func processEvents(_ events: [KeyEvent]) -> Bool {
        for event in events {
            for resolved in resolver.feed(event) where !handleResolved(resolved) {
                return false
            }
        }
        return true
    }

    // MARK: Rendering (MinimalAIApp's oracle-pinned three-step settle)

    private func render() {
        let size = getTerminalSize()
        let width = size?.columns ?? 80
        if let newSize = size, lastTerminalSize != newSize {
            lastTerminalSize = newSize
            Self.dlog("resize -> \(newSize.columns)x\(newSize.rows)")
            tui.updateTerminalSize(width: newSize.columns, height: newSize.rows)
        }
        let viewportWidth = max(1, width - 2)
        if input.viewport?.width != viewportWidth {
            input.setViewport(Viewport(width: viewportWidth))
        }

        let preview: [String]
        if let range = transcript.activeStreamingRange {
            let lines = transcript.transcriptLines
            let unstableStart = min(
                range.lowerBound + transcript.activeStreamingStableLineCount,
                range.upperBound
            )
            preview = Array(lines[unstableStart..<range.upperBound])
        } else {
            preview = []
        }

        let delta = appendState.consume(
            transcript: transcript.transcriptLines,
            activeRange: transcript.activeStreamingRange,
            stableLineCount: transcript.activeStreamingStableLineCount,
            unsettledFrom: transcript.firstUnsettledLineIndex
        )
        if !delta.isEmpty {
            Self.dlog("erase+append \(delta.count) lines: \(delta.first.map { String($0.prefix(24)) } ?? "")")
            tui.render(committed: [], live: [], cursorOffset: 0)
            tui.appendFrame(lines: delta)
        }

        var status = isRunning ? "● running" : "● idle"
        status += " · in \(tokensIn) / out \(tokensOut) tok"
        status += " · session \(config.sessionID.suffix(8))"
        if let pending = pendingPermission {
            status += " · PERMISSION #\(pending.id) awaiting y/a/n"
        }

        let inputRendered = input.render()
        let prompt = Style.prompt("❯ ", mode: .automatic)
        let continuation = "  "
        let inputLines: [String] = inputRendered.lines.enumerated().map { idx, line in
            idx == 0 ? prompt + line : continuation + line
        }

        Self.dlog("render preview=\(preview.count) live=\(1 + inputLines.count) first=\(preview.first.map { String($0.prefix(24)) } ?? "-")")
        tui.render(
            committed: preview,
            live: [status] + inputLines,
            cursorPlacement: inputRendered.cursor
        )
    }

    // MARK: Attach reader + main loop

    func run() throws {
        guard let attachFD = UDS.connect(config.socketPath) else {
            throw ClientError.connectFailed(config.socketPath)
        }
        guard UDS.sendLine(attachFD, [
            "op": "attach", "session": config.sessionID, "since": config.since,
        ]) else {
            throw ClientError.attachFailed
        }
        let thread = Thread { [weak self] in
            var pending = Data()
            var byte: UInt8 = 0
            while true {
                let n = read(attachFD, &byte, 1)
                if n <= 0 { break }
                if byte == 0x0A {
                    let line = pending
                    pending = Data()
                    guard !line.isEmpty else { continue }
                    let msg = WireParser.parse(line)
                    Task { @MainActor [weak self] in self?.handle(msg) }
                } else {
                    pending.append(byte)
                }
            }
            Task { @MainActor [weak self] in
                self?.transcript.applyCore(.notification(text: "attach stream closed"))
                self?.render()
            }
        }
        thread.name = "metacodes-attach"
        thread.start()

        let reader = InputReader { [weak self] events in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.processEvents(events) {
                    self.shouldExit = true
                }
                self.render()
            }
        }
        try reader.start()
        defer {
            reader.stop()
            close(attachFD)
        }

        // The hosting panel resizes the pty when its layout changes; without a
        // SIGWINCH listener an idle client would not re-anchor until the next
        // wire event arrives. render() polls getTerminalSize() and routes the
        // width change into TUI.updateTerminalSize → geometry reanchor.
        signal(SIGWINCH, SIG_IGN)
        let winch = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        winch.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.render() }
        }
        winch.resume()
        winchSource = winch

        render()
        while reader.running && !shouldExit {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            let flushed = resolver.tick()
            if !flushed.isEmpty {
                for resolved in flushed where !handleResolved(resolved) {
                    shouldExit = true
                }
                render()
            }
        }
    }
}

enum ClientError: Error, CustomStringConvertible {
    case connectFailed(String)
    case attachFailed
    case usage
    case noSession

    var description: String {
        switch self {
        case .connectFailed(let path): return "cannot connect UDS socket at \(path)"
        case .attachFailed: return "attach op failed"
        case .usage:
            return "usage: metacodes-client <uds-socket> [--session <id>] [--http <port>] [--since <n>]"
        case .noSession: return "daemon reports no sessions (op list)"
        }
    }
}

// MARK: - Entry

@MainActor
func main() {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else {
        fputs("\(ClientError.usage)\n", stderr)
        exit(2)
    }
    let socketPath = args.removeFirst()
    var sessionID: String?
    var httpPort = 7777
    var since = 0
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--session" where index + 1 < args.count:
            sessionID = args[index + 1]; index += 2
        case "--http" where index + 1 < args.count:
            httpPort = Int(args[index + 1]) ?? 7777; index += 2
        case "--since" where index + 1 < args.count:
            since = Int(args[index + 1]) ?? 0; index += 2
        default:
            fputs("\(ClientError.usage)\n", stderr)
            exit(2)
        }
    }
    if sessionID == nil {
        let reply = UDS.request(socketPath, ["op": "list"])
        sessionID = (reply?["sessions"] as? [Any])?.first as? String
    }
    guard let session = sessionID else {
        fputs("\(ClientError.noSession)\n", stderr)
        exit(1)
    }
    let app = MetacodesClientApp(config: ClientConfig(
        socketPath: socketPath, sessionID: session, httpPort: httpPort, since: since))
    do {
        try app.run()
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

main()
