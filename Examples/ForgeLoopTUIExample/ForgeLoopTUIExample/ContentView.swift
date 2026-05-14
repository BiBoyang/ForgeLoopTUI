import SwiftUI
import Combine
import AppKit
import ForgeLoopTUI
import Foundation

struct TerminalPaneStreamUpdate: Sendable {
    let snapshotText: String
    let progress: Double
    let isFinal: Bool
}

protocol TerminalPaneStreamingSource: Sendable {
    nonisolated var sourceDisplayName: String { get }
    nonisolated func streamText(from sourceText: String, preferredChunkSize: Int) -> AsyncThrowingStream<TerminalPaneStreamUpdate, Error>
}

struct TerminalPaneChatMessage: Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

protocol TerminalPaneChatStreamingSource: Sendable {
    nonisolated var sourceDisplayName: String { get }
    nonisolated func streamReply(messages: [TerminalPaneChatMessage]) -> AsyncThrowingStream<TerminalPaneStreamUpdate, Error>
}

struct FileHandleStreamingSource: TerminalPaneStreamingSource {
    nonisolated let sourceDisplayName: String = "fixture file stream"

    nonisolated init() {}

    nonisolated func streamText(from sourceText: String, preferredChunkSize: Int) -> AsyncThrowingStream<TerminalPaneStreamUpdate, Error> {
        let chunkSize = max(64, preferredChunkSize)
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let textBytes = Array(sourceText.utf8)
                if textBytes.isEmpty {
                    continuation.yield(
                        TerminalPaneStreamUpdate(
                            snapshotText: "",
                            progress: 1.0,
                            isFinal: true
                        )
                    )
                    continuation.finish()
                    return
                }

                var emittedText = ""
                var pendingBytes = Data()
                var consumedBytes = 0

                while consumedBytes < textBytes.count {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    let next = min(textBytes.count, consumedBytes + chunkSize)
                    let slice = textBytes[consumedBytes..<next]
                    pendingBytes.append(contentsOf: slice)
                    consumedBytes = next

                    let completePrefixCount = Self.completeUTF8PrefixLength(in: pendingBytes)
                    if completePrefixCount > 0 {
                        let completeChunk = pendingBytes.prefix(completePrefixCount)
                        emittedText.append(String(decoding: completeChunk, as: UTF8.self))
                        pendingBytes.removeFirst(completePrefixCount)
                    }

                    continuation.yield(
                        TerminalPaneStreamUpdate(
                            snapshotText: emittedText,
                            progress: min(1.0, Double(consumedBytes) / Double(textBytes.count)),
                            isFinal: false
                        )
                    )

                    if consumedBytes < textBytes.count {
                        try? await Task.sleep(nanoseconds: 25_000_000)
                    }
                }

                if !pendingBytes.isEmpty {
                    emittedText.append(String(decoding: pendingBytes, as: UTF8.self))
                }

                continuation.yield(
                    TerminalPaneStreamUpdate(
                        snapshotText: emittedText,
                        progress: 1.0,
                        isFinal: true
                    )
                )
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private nonisolated static func completeUTF8PrefixLength(in data: Data) -> Int {
        guard !data.isEmpty else { return 0 }

        let bytes = [UInt8](data)
        var index = bytes.count - 1
        var trailingContinuationCount = 0

        while (bytes[index] & 0b1100_0000) == 0b1000_0000 {
            trailingContinuationCount += 1
            guard index > 0 else { return 0 }
            index -= 1
        }

        let lead = bytes[index]
        let expectedContinuationCount: Int

        if (lead & 0b1000_0000) == 0 {
            expectedContinuationCount = 0
        } else if (lead & 0b1110_0000) == 0b1100_0000 {
            expectedContinuationCount = 1
        } else if (lead & 0b1111_0000) == 0b1110_0000 {
            expectedContinuationCount = 2
        } else if (lead & 0b1111_1000) == 0b1111_0000 {
            expectedContinuationCount = 3
        } else {
            return bytes.count
        }

        if trailingContinuationCount < expectedContinuationCount {
            let incompleteCount = trailingContinuationCount + 1
            return max(0, bytes.count - incompleteCount)
        }

        return bytes.count
    }
}

enum OpenAIStreamingSourceError: LocalizedError {
    case invalidHTTPResponse
    case httpStatus(code: Int)
    case apiError(String)
    case unsupportedRequestPayload

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "OpenAI stream returned a non-HTTP response"
        case .httpStatus(let code):
            return "OpenAI stream failed with HTTP \(code)"
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        case .unsupportedRequestPayload:
            return "OpenAI request payload could not be encoded"
        }
    }
}

struct OpenAIResponsesStreamingSource: TerminalPaneStreamingSource, TerminalPaneChatStreamingSource {
    enum APIStyle: String, Sendable {
        case responses
        case chatCompletions
    }

    struct Config: Sendable {
        let apiKey: String
        let model: String
        let endpoint: URL
        let apiStyle: APIStyle
    }

    private let config: Config
    nonisolated var sourceDisplayName: String {
        "openai-compatible sse (\(config.apiStyle.rawValue), \(config.model))"
    }

    nonisolated init(config: Config) {
        self.config = config
    }

    nonisolated static func fromEnvironment() -> OpenAIResponsesStreamingSource? {
        let env = ProcessInfo.processInfo.environment
        guard let rawAPIKey = firstNonEmpty(
            in: env,
            keys: ["FORGELOOPTUI_OPENAI_API_KEY", "OPENAI_API_KEY"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rawAPIKey.isEmpty else {
            return nil
        }

        let rawModel = firstNonEmpty(
            in: env,
            keys: ["FORGELOOPTUI_OPENAI_MODEL", "OPENAI_MODEL"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = rawModel.isEmpty ? "gpt-4.1-mini" : rawModel

        let rawBaseURL = firstNonEmpty(
            in: env,
            keys: ["FORGELOOPTUI_OPENAI_BASE_URL", "OPENAI_BASE_URL"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseURLString = rawBaseURL.isEmpty ? "https://api.openai.com" : rawBaseURL
        let baseURL = URL(string: baseURLString) ?? URL(string: "https://api.openai.com")!

        let endpointOverride = firstNonEmpty(
            in: env,
            keys: ["FORGELOOPTUI_OPENAI_ENDPOINT", "OPENAI_ENDPOINT"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let styleOverride = firstNonEmpty(
            in: env,
            keys: ["FORGELOOPTUI_OPENAI_API_STYLE", "OPENAI_API_STYLE"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let apiStyle = resolveAPIStyle(
            styleOverride: styleOverride,
            endpointOverride: endpointOverride,
            baseURL: baseURL
        )

        let endpoint = makeEndpoint(
            baseURL: baseURL,
            endpointOverride: endpointOverride,
            apiStyle: apiStyle
        )

        return OpenAIResponsesStreamingSource(
            config: Config(
                apiKey: rawAPIKey,
                model: model,
                endpoint: endpoint,
                apiStyle: apiStyle
            )
        )
    }

    nonisolated func streamText(from sourceText: String, preferredChunkSize: Int) -> AsyncThrowingStream<TerminalPaneStreamUpdate, Error> {
        let payload = Self.makePromptRequestPayload(
            model: config.model,
            input: sourceText,
            apiStyle: config.apiStyle
        )
        return streamPayload(payload)
    }

    nonisolated func streamReply(messages: [TerminalPaneChatMessage]) -> AsyncThrowingStream<TerminalPaneStreamUpdate, Error> {
        let payload = Self.makeChatRequestPayload(
            model: config.model,
            messages: messages,
            apiStyle: config.apiStyle
        )
        return streamPayload(payload)
    }

    private nonisolated func streamPayload(_ payload: [String: Any]) -> AsyncThrowingStream<TerminalPaneStreamUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    var request = URLRequest(url: config.endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    guard JSONSerialization.isValidJSONObject(payload) else {
                        throw OpenAIStreamingSourceError.unsupportedRequestPayload
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAIStreamingSourceError.invalidHTTPResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw OpenAIStreamingSourceError.httpStatus(code: httpResponse.statusCode)
                    }

                    var emittedText = ""
                    var pendingDataLines: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if line.isEmpty {
                            try Self.consumeSSEEvent(
                                dataLines: &pendingDataLines,
                                emittedText: &emittedText,
                                continuation: continuation
                            )
                            continue
                        }

                        if line.hasPrefix(":") {
                            continue
                        }

                        if line.hasPrefix("data:") {
                            let rawValue = String(line.dropFirst(5))
                            let dataLine = rawValue.hasPrefix(" ") ? String(rawValue.dropFirst()) : rawValue
                            pendingDataLines.append(dataLine)
                        }
                    }

                    try Self.consumeSSEEvent(
                        dataLines: &pendingDataLines,
                        emittedText: &emittedText,
                        continuation: continuation
                    )

                    continuation.yield(
                        TerminalPaneStreamUpdate(
                            snapshotText: emittedText,
                            progress: 1.0,
                            isFinal: true
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private nonisolated static func makePromptRequestPayload(
        model: String,
        input: String,
        apiStyle: APIStyle
    ) -> [String: Any] {
        switch apiStyle {
        case .responses:
            return [
                "model": model,
                "input": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "input_text",
                                "text": input,
                            ],
                        ],
                    ],
                ],
                "stream": true,
            ]
        case .chatCompletions:
            return [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": input,
                    ],
                ],
                "stream": true,
            ]
        }
    }

    private nonisolated static func makeChatRequestPayload(
        model: String,
        messages: [TerminalPaneChatMessage],
        apiStyle: APIStyle
    ) -> [String: Any] {
        switch apiStyle {
        case .responses:
            let responseInput = messages.map { message in
                [
                    "role": message.role.rawValue,
                    "content": [
                        [
                            "type": "input_text",
                            "text": message.content,
                        ],
                    ],
                ] as [String: Any]
            }
            return [
                "model": model,
                "input": responseInput,
                "stream": true,
            ]
        case .chatCompletions:
            let chatMessages = messages.map { message in
                [
                    "role": message.role.rawValue,
                    "content": message.content,
                ] as [String: Any]
            }
            return [
                "model": model,
                "messages": chatMessages,
                "stream": true,
            ]
        }
    }

    private nonisolated static func consumeSSEEvent(
        dataLines: inout [String],
        emittedText: inout String,
        continuation: AsyncThrowingStream<TerminalPaneStreamUpdate, Error>.Continuation
    ) throws {
        guard !dataLines.isEmpty else { return }
        defer { dataLines.removeAll(keepingCapacity: true) }

        let payloadText = dataLines.joined(separator: "\n")
        let trimmedPayload = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPayload == "[DONE]" || trimmedPayload.isEmpty {
            return
        }

        let objects = parseEventObjects(from: payloadText)
        guard !objects.isEmpty else {
            return
        }

        for object in objects {
            if let apiError = extractAPIError(from: object) {
                throw OpenAIStreamingSourceError.apiError(apiError)
            }

            if let delta = extractTextDelta(from: object) {
                emittedText.append(delta)
                continuation.yield(
                    TerminalPaneStreamUpdate(
                        snapshotText: emittedText,
                        progress: 0.0,
                        isFinal: false
                    )
                )
            }
        }
    }

    private nonisolated static func parseEventObjects(from payloadText: String) -> [[String: Any]] {
        let normalized = payloadText
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        func parseOne(_ candidate: String) -> [String: Any]? {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return nil
            }
            return object as? [String: Any]
        }

        if let direct = parseOne(normalized) {
            return [direct]
        }

        var parsed: [[String: Any]] = []
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let object = parseOne(line) {
                parsed.append(object)
            }
        }
        return parsed
    }

    private nonisolated static func extractAPIError(from object: [String: Any]) -> String? {
        if let type = object["type"] as? String, type == "error",
           let errorObject = object["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            return message
        }

        if let errorObject = object["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            return message
        }

        return nil
    }

    private nonisolated static func extractTextDelta(from object: [String: Any]) -> String? {
        if let type = object["type"] as? String,
           type == "response.output_text.delta",
           let delta = object["delta"] as? String {
            return delta
        }

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let deltaObject = firstChoice["delta"] as? [String: Any],
           let content = deltaObject["content"] as? String,
           !content.isEmpty {
            return content
        }

        if let choices = object["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let deltaObject = firstChoice["delta"] as? [String: Any],
           let reasoning = deltaObject["reasoning_content"] as? String,
           !reasoning.isEmpty {
            return reasoning
        }

        return nil
    }

    private nonisolated static func firstNonEmpty(
        in env: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = env[key] else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private nonisolated static func resolveAPIStyle(
        styleOverride: String?,
        endpointOverride: String?,
        baseURL: URL
    ) -> APIStyle {
        if let styleOverride {
            let normalized = styleOverride.lowercased()
            if normalized == "chat" || normalized == "chat_completions" || normalized == "chat-completions" {
                return .chatCompletions
            }
            if normalized == "responses" {
                return .responses
            }
        }

        if let endpointOverride {
            let normalized = endpointOverride.lowercased()
            if normalized.contains("chat/completions") {
                return .chatCompletions
            }
            if normalized.contains("/responses") {
                return .responses
            }
        }

        if let host = baseURL.host?.lowercased(), host.contains("deepseek.com") {
            return .chatCompletions
        }

        return .responses
    }

    private nonisolated static func makeEndpoint(
        baseURL: URL,
        endpointOverride: String?,
        apiStyle: APIStyle
    ) -> URL {
        if let endpointOverride,
           let absolute = URL(string: endpointOverride),
           absolute.scheme != nil {
            return absolute
        }

        if let endpointOverride, !endpointOverride.isEmpty {
            if endpointOverride.hasPrefix("/") {
                return replacingPath(baseURL: baseURL, absolutePath: endpointOverride)
            }
            return appendingRelativePath(baseURL: baseURL, relativePath: endpointOverride)
        }

        switch apiStyle {
        case .responses:
            return replacingPath(baseURL: baseURL, absolutePath: "/v1/responses")
        case .chatCompletions:
            if let host = baseURL.host?.lowercased(), host.contains("deepseek.com") {
                return appendingRelativePath(baseURL: baseURL, relativePath: "chat/completions")
            }
            return replacingPath(baseURL: baseURL, absolutePath: "/v1/chat/completions")
        }
    }

    private nonisolated static func replacingPath(baseURL: URL, absolutePath: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = normalizedAbsolutePath(absolutePath)
        return components?.url ?? baseURL
    }

    private nonisolated static func appendingRelativePath(baseURL: URL, relativePath: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let base = (components?.path ?? "/").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBase = base.isEmpty ? "/" : base
        let rootBase = cleanBase == "/" ? "" : trimSuffix(cleanBase, suffix: "/")
        let cleanRelative = trimPrefix(
            relativePath.trimmingCharacters(in: .whitespacesAndNewlines),
            prefix: "/"
        )
        components?.path = "\(rootBase)/\(cleanRelative)"
        return components?.url ?? baseURL
    }

    private nonisolated static func normalizedAbsolutePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private nonisolated static func trimPrefix(_ text: String, prefix: String) -> String {
        guard text.hasPrefix(prefix) else { return text }
        return String(text.dropFirst(prefix.count))
    }

    private nonisolated static func trimSuffix(_ text: String, suffix: String) -> String {
        guard text.hasSuffix(suffix) else { return text }
        return String(text.dropLast(suffix.count))
    }
}

enum TerminalPaneStreamingSourceFactory {
    nonisolated static func makeDefault() -> any TerminalPaneStreamingSource {
        OpenAIResponsesStreamingSource.fromEnvironment() ?? FileHandleStreamingSource()
    }
}

@MainActor
final class TerminalPaneDemoModel: ObservableObject {
    // Embedded AppKit pane uses a VirtualTerminal surface (not a real interactive TTY).
    // Absolute full-frame redraw is more stable than inline-anchor diff under rapid updates.
    private static let embeddedRenderStrategy: RenderStrategy = .legacyAbsolute

    struct Fixture: Identifiable, Hashable {
        let id: String
        let title: String
        let fileName: String
    }

    enum DemoMode: String, CaseIterable, Identifiable {
        case fixture
        case liveChat

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fixture:
                return "Fixture Demo"
            case .liveChat:
                return "Live Chat"
            }
        }
    }

    struct ChatMessage: Identifiable, Sendable {
        enum Role: Sendable {
            case user
            case assistant

            var markdownLabel: String {
                switch self {
                case .user:
                    return "User"
                case .assistant:
                    return "Assistant"
                }
            }

            var transportRole: TerminalPaneChatMessage.Role {
                switch self {
                case .user:
                    return .user
                case .assistant:
                    return .assistant
                }
            }
        }

        let id: UUID
        let role: Role
        var content: String
    }

    static let fixtures: [Fixture] = [
        Fixture(id: "sample", title: "Markdown Sample", fileName: "markdownview-sample.md"),
        Fixture(id: "tables", title: "Table Showcase", fileName: "markdown-table-showcase.md"),
        Fixture(id: "wide-table-cat", title: "Wide Table (Cat)", fileName: "markdown-wide-table-cat.md"),
        Fixture(id: "narrow", title: "Narrow Terminal", fileName: "markdown-narrow-terminal-showcase.md"),
        Fixture(id: "long-mixed", title: "Long Mixed", fileName: "markdown-long-mixed-showcase.md"),
        Fixture(id: "syntax-lab", title: "Syntax Lab", fileName: "markdown-syntax-lab.md"),
    ]

    @Published var demoMode: DemoMode = .fixture
    @Published var selectedFixtureID: String
    @Published var chatInputText: String = ""
    @Published private(set) var screenCells: [[Cell]] = []
    @Published private(set) var cursorRow: Int = 0
    @Published private(set) var cursorCol: Int = 0
    @Published private(set) var statusText: String = "Ready"
    @Published private(set) var progressText: String = "0%"
    @Published private(set) var terminalInfoText: String = "cols 96 rows 32"
    @Published private(set) var isStreaming: Bool = false

    var fixtures: [Fixture] { Self.fixtures }

    private var columns: Int = 96
    private var rows: Int = 32
    private var terminal: VirtualTerminal
    private var tui: TUI
    private let layoutRenderer = ScreenLayoutRenderer()
    private var markdownEngine: MarkdownEngine
    private let fixtureStreamSource: any TerminalPaneStreamingSource
    private let remoteStreamSource: OpenAIResponsesStreamingSource?

    private var currentSourceText: String = ""
    private var chatMessages: [ChatMessage] = []
    private var streamTask: Task<Void, Never>?

    private static let fixturesDirectory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // .../ForgeLoopTUIExample
            .deletingLastPathComponent() // .../Examples/ForgeLoopTUIExample
            .deletingLastPathComponent() // .../Examples
            .appendingPathComponent("Fixtures", isDirectory: true)
    }()

    var streamSourceInfoText: String {
        let fixtureLine = "Play Stream: \(fixtureStreamSource.sourceDisplayName)"
        if let remoteStreamSource {
            return "\(fixtureLine) | Play Remote SSE/Chat: \(remoteStreamSource.sourceDisplayName)"
        }
        return "\(fixtureLine) | Play Remote SSE/Chat: unavailable (set OPENAI_API_KEY)"
    }

    var hasRemoteStreamingSource: Bool {
        remoteStreamSource != nil
    }

    var modeList: [DemoMode] { DemoMode.allCases }

    init(
        fixtureStreamSource: any TerminalPaneStreamingSource = FileHandleStreamingSource(),
        remoteStreamSource: OpenAIResponsesStreamingSource? = OpenAIResponsesStreamingSource.fromEnvironment()
    ) {
        let initialFixture = Self.fixtures.first ?? Fixture(id: "sample", title: "Markdown Sample", fileName: "markdownview-sample.md")
        selectedFixtureID = initialFixture.id

        let terminal = VirtualTerminal(width: 96, height: 32)
        self.terminal = terminal
        self.tui = TUI(
            strategy: Self.embeddedRenderStrategy,
            isTTY: true,
            terminalWidth: 96,
            terminalHeight: 32,
            liveBudget: 4,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker,
            terminal: terminal
        )
        markdownEngine = StreamingMarkdownEngine(options: Self.markdownOptions(maxRenderedWidth: 96))
        self.fixtureStreamSource = fixtureStreamSource
        self.remoteStreamSource = remoteStreamSource

        renderSelectedFixtureStatic()
    }

    deinit {
        streamTask?.cancel()
    }

    func setDemoMode(_ mode: DemoMode) {
        guard mode != demoMode else { return }
        stopStreaming()
        demoMode = mode
        switch mode {
        case .fixture:
            renderSelectedFixtureStatic()
        case .liveChat:
            markdownEngine = makeMarkdownEngine()
            resetTerminalSurface()
            progressText = "100%"
            statusText = hasRemoteStreamingSource
                ? "Live chat ready"
                : "Live chat unavailable: set OPENAI_API_KEY (or FORGELOOPTUI_OPENAI_API_KEY)"
            renderLiveChatSnapshot(modeLabel: "chat-idle", isFinal: true)
        }
    }

    func renderSelectedFixtureStatic() {
        demoMode = .fixture
        stopStreaming()

        currentSourceText = loadFixtureText(for: selectedFixture)

        markdownEngine = makeMarkdownEngine()
        resetTerminalSurface()
        renderCurrentSource(modeLabel: "static", isFinal: true)

        statusText = "Static render loaded: \(selectedFixture.title)"
        progressText = "100%"
    }

    func streamSelectedFixture() {
        demoMode = .fixture
        startStreaming(
            using: fixtureStreamSource,
            allowFallback: false
        )
    }

    func streamSelectedFixtureViaRemote() {
        demoMode = .fixture
        guard let remoteStreamSource else {
            statusText = "Remote stream unavailable: set OPENAI_API_KEY (or FORGELOOPTUI_OPENAI_API_KEY)"
            return
        }

        startStreaming(
            using: remoteStreamSource,
            allowFallback: true
        )
    }

    func sendChatPrompt() {
        demoMode = .liveChat

        let submitted = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty else { return }
        guard let remoteStreamSource else {
            statusText = "Live chat unavailable: set OPENAI_API_KEY (or FORGELOOPTUI_OPENAI_API_KEY)"
            renderLiveChatSnapshot(modeLabel: "chat-idle", isFinal: true)
            return
        }

        stopStreaming()
        chatInputText = ""

        let userMessage = ChatMessage(id: UUID(), role: .user, content: submitted)
        chatMessages.append(userMessage)

        let assistantMessage = ChatMessage(id: UUID(), role: .assistant, content: "")
        chatMessages.append(assistantMessage)

        let requestMessages = chatMessages.dropLast().map { message in
            TerminalPaneChatMessage(
                role: message.role.transportRole,
                content: message.content
            )
        }
        let stream = remoteStreamSource.streamReply(messages: Array(requestMessages))

        isStreaming = true
        progressText = "0%"
        statusText = "Live chat: streaming reply via \(remoteStreamSource.sourceDisplayName)"
        renderLiveChatSnapshot(modeLabel: "chat-stream", isFinal: false)

        streamTask = Task { [weak self] in
            await self?.consumeChatStream(
                stream,
                assistantMessageID: assistantMessage.id
            )
        }
    }

    func clearLiveChatTranscript() {
        demoMode = .liveChat
        stopStreaming()
        chatMessages.removeAll(keepingCapacity: false)
        chatInputText = ""
        markdownEngine = makeMarkdownEngine()
        resetTerminalSurface()
        progressText = "100%"
        statusText = "Live chat cleared"
        renderLiveChatSnapshot(modeLabel: "chat-idle", isFinal: true)
    }

    private func startStreaming(
        using source: any TerminalPaneStreamingSource,
        allowFallback: Bool
    ) {
        demoMode = .fixture
        stopStreaming()

        currentSourceText = ""
        markdownEngine = makeMarkdownEngine()
        resetTerminalSurface()

        isStreaming = true
        progressText = "0%"
        statusText = "Streaming: \(selectedFixture.title) via \(source.sourceDisplayName)"

        let fixture = selectedFixture
        let sourceText = loadFixtureText(for: fixture)
        let preferredChunkSize = max(128, columns * 3)
        let stream = source.streamText(
            from: sourceText,
            preferredChunkSize: preferredChunkSize
        )

        streamTask = Task { [weak self] in
            await self?.consumeStream(
                stream,
                fixture: fixture,
                fallbackSourceText: sourceText,
                preferredChunkSize: preferredChunkSize,
                allowFallback: allowFallback
            )
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil

        if isStreaming {
            isStreaming = false
            statusText = "Streaming stopped"
        }
    }

    func updateViewport(pixelWidth: CGFloat, pixelHeight: CGFloat) {
        let cellWidth = max(1.0, "W".size(withAttributes: [.font: TerminalTextSurface.baseFont]).width)
        let lineHeight = max(1.0, TerminalTextSurface.baseFont.ascender - TerminalTextSurface.baseFont.descender + TerminalTextSurface.baseFont.leading)

        let nextColumns = max(20, Int((pixelWidth - 12.0) / cellWidth))
        let nextRows = max(10, Int((pixelHeight - 12.0) / lineHeight))

        guard nextColumns != columns || nextRows != rows else { return }

        columns = nextColumns
        rows = nextRows

        rebuildTerminalSurface()
        markdownEngine = makeMarkdownEngine()
        renderCurrentSource(modeLabel: currentModeLabel, isFinal: !isStreaming)
    }

    private var selectedFixture: Fixture {
        Self.fixtures.first(where: { $0.id == selectedFixtureID }) ?? Self.fixtures[0]
    }

    private var currentModeLabel: String {
        switch demoMode {
        case .fixture:
            return isStreaming ? "stream" : "static"
        case .liveChat:
            return isStreaming ? "chat-stream" : "chat-idle"
        }
    }

    private func consumeStream(
        _ stream: AsyncThrowingStream<TerminalPaneStreamUpdate, Error>,
        fixture: Fixture,
        fallbackSourceText: String,
        preferredChunkSize: Int,
        allowFallback: Bool
    ) async {
        var hasRenderedText = false

        do {
            for try await update in stream {
                if Task.isCancelled {
                    streamTask = nil
                    return
                }

                currentSourceText = update.snapshotText
                hasRenderedText = hasRenderedText || !update.snapshotText.isEmpty
                progressText = Self.progressLabel(fraction: update.progress)
                renderCurrentSource(modeLabel: "stream", isFinal: update.isFinal)
            }

            if Task.isCancelled {
                streamTask = nil
                return
            }

            if allowFallback && !hasRenderedText {
                statusText = "Primary stream produced no visible output, switching to fixture fallback…"
                progressText = "0%"
                let fallback = FileHandleStreamingSource().streamText(
                    from: fallbackSourceText,
                    preferredChunkSize: preferredChunkSize
                )
                await consumeStream(
                    fallback,
                    fixture: fixture,
                    fallbackSourceText: fallbackSourceText,
                    preferredChunkSize: preferredChunkSize,
                    allowFallback: false
                )
                return
            }

            isStreaming = false
            progressText = "100%"
            statusText = currentSourceText.isEmpty ? "Fixture is empty" : "Streaming completed: \(fixture.title)"
            streamTask = nil
        } catch {
            if Task.isCancelled {
                streamTask = nil
                return
            }

            if allowFallback {
                statusText = "Primary stream failed (\(error.localizedDescription)), switching to fixture fallback…"
                progressText = "0%"
                let fallback = FileHandleStreamingSource().streamText(
                    from: fallbackSourceText,
                    preferredChunkSize: preferredChunkSize
                )
                await consumeStream(
                    fallback,
                    fixture: fixture,
                    fallbackSourceText: fallbackSourceText,
                    preferredChunkSize: preferredChunkSize,
                    allowFallback: false
                )
                return
            }

            isStreaming = false
            statusText = "Streaming failed: \(error.localizedDescription)"
            streamTask = nil
        }
    }

    private func consumeChatStream(
        _ stream: AsyncThrowingStream<TerminalPaneStreamUpdate, Error>,
        assistantMessageID: UUID
    ) async {
        var hasRenderedText = false

        do {
            for try await update in stream {
                if Task.isCancelled {
                    streamTask = nil
                    return
                }

                if let index = chatMessages.firstIndex(where: { $0.id == assistantMessageID }) {
                    chatMessages[index].content = update.snapshotText
                }
                hasRenderedText = hasRenderedText || !update.snapshotText.isEmpty
                progressText = Self.progressLabel(fraction: update.progress)
                renderLiveChatSnapshot(modeLabel: "chat-stream", isFinal: update.isFinal)
            }

            if Task.isCancelled {
                streamTask = nil
                return
            }

            isStreaming = false
            progressText = "100%"

            if !hasRenderedText,
               let index = chatMessages.firstIndex(where: { $0.id == assistantMessageID }) {
                chatMessages[index].content = "_(empty response)_"
            }

            renderLiveChatSnapshot(modeLabel: "chat-idle", isFinal: true)
            statusText = "Live chat reply completed"
            streamTask = nil
        } catch {
            if Task.isCancelled {
                streamTask = nil
                return
            }

            isStreaming = false
            progressText = "100%"
            if let index = chatMessages.firstIndex(where: { $0.id == assistantMessageID }),
               chatMessages[index].content.isEmpty {
                chatMessages[index].content = "_Error: \(error.localizedDescription)_"
            }

            renderLiveChatSnapshot(modeLabel: "chat-idle", isFinal: true)
            statusText = "Live chat failed: \(error.localizedDescription)"
            streamTask = nil
        }
    }

    private func renderLiveChatSnapshot(modeLabel: String, isFinal: Bool) {
        // Live chat can contain rapidly changing, mixed-width markdown (CJK + code fences).
        // In this embedded virtual terminal demo we prefer deterministic full-frame redraw
        // over incremental diff to avoid stale tail rows under constrained viewport heights.
        terminal.clear()
        tui.resetRetainedFrame()
        currentSourceText = chatMessages.isEmpty
            ? Self.emptyLiveChatMarkdown(hasRemoteSource: hasRemoteStreamingSource)
            : Self.chatTranscriptMarkdown(messages: chatMessages)
        renderCurrentSource(modeLabel: modeLabel, isFinal: isFinal)
    }

    private func renderCurrentSource(modeLabel: String, isFinal: Bool) {
        let transcriptLines = markdownEngine.render(text: currentSourceText, isFinal: isFinal)
        let contextLine: String
        let statusDetail: String

        switch demoMode {
        case .fixture:
            contextLine = "Fixture: \(selectedFixture.fileName)"
            statusDetail = "Viewport: \(columns)x\(rows)"
        case .liveChat:
            contextLine = "Live Chat: OpenAI-compatible stream"
            let turnCount = chatMessages.filter { $0.role == .user }.count
            statusDetail = "Viewport: \(columns)x\(rows) | Turns: \(turnCount)"
        }

        let layout = ScreenLayout(
            header: [
                "ForgeLoopTUI Embedded Terminal Pane",
                contextLine,
            ],
            transcript: transcriptLines,
            queue: [],
            status: [
                "Mode: \(modeLabel) | Stream: \(isStreaming ? "on" : "off") | Progress: \(progressText)",
                statusDetail,
            ],
            input: []
        )

        let config = ScreenLayoutConfig(
            terminalHeight: rows,
            terminalWidth: columns,
            showHeader: true
        )

        let frame = layoutRenderer.render(layout: layout, config: config)
        tui.render(frame: frame)

        screenCells = terminal.screenCells
        cursorRow = terminal.cursorRow
        cursorCol = terminal.cursorCol
        terminalInfoText = "cols \(columns) rows \(rows) cursor \(cursorRow + 1),\(cursorCol + 1)"
    }

    private func resetTerminalSurface() {
        terminal.clear()
        tui.resetRetainedFrame()
        screenCells = terminal.screenCells
        cursorRow = terminal.cursorRow
        cursorCol = terminal.cursorCol
    }

    private func rebuildTerminalSurface() {
        let newTerminal = VirtualTerminal(width: columns, height: rows)
        terminal = newTerminal
        tui = TUI(
            strategy: Self.embeddedRenderStrategy,
            isTTY: true,
            terminalWidth: columns,
            terminalHeight: rows,
            liveBudget: 4,
            liveBudgetMode: .physicalRows,
            cursorPositioningMode: .marker,
            terminal: newTerminal
        )
    }

    private func makeMarkdownEngine() -> MarkdownEngine {
        StreamingMarkdownEngine(options: Self.markdownOptions(maxRenderedWidth: columns))
    }

    private static func markdownOptions(maxRenderedWidth: Int) -> MarkdownRenderOptions {
        let width = max(24, maxRenderedWidth - 2)
        return MarkdownRenderOptions(
            tablePolicy: TableRenderPolicy(
                maxRenderedWidth: width,
                minColumnWidth: 4,
                maxColumnWidth: max(12, width / 3),
                truncationIndicator: "…",
                overflowBehavior: .compactThenTruncateThenDegrade,
                wideTableStrategy: .autoReadable
            )
        )
    }

    private func fixtureURL(for fixture: Fixture) -> URL {
        Self.fixturesDirectory.appendingPathComponent(fixture.fileName)
    }

    private func loadFixtureText(for fixture: Fixture) -> String {
        let path = fixtureURL(for: fixture)
        do {
            return try String(contentsOf: path, encoding: .utf8)
        } catch {
            let banner = [
                "> Fixture file unavailable at runtime, using embedded markdown sample.",
                "> file: \(fixture.fileName)",
                "> error: \(error.localizedDescription)",
                "",
            ].joined(separator: "\n")
            return banner + Self.embeddedFixtureMarkdown(for: fixture)
        }
    }

    private static func progressLabel(fraction: Double) -> String {
        let clamped = max(0.0, min(1.0, fraction))
        return String(format: "%.0f%%", clamped * 100.0)
    }

    private static func emptyLiveChatMarkdown(hasRemoteSource: Bool) -> String {
        let availability = hasRemoteSource
            ? "Remote source is ready. Enter a prompt and click Send."
            : "Remote source unavailable. Set OPENAI_API_KEY (or FORGELOOPTUI_OPENAI_API_KEY)."

        return [
            "# Live Chat Mode",
            "",
            availability,
            "",
            "## How To Use",
            "1. Type your prompt in the input field.",
            "2. Click `Send` to stream assistant output.",
            "3. Click `Stop` to cancel current generation.",
        ].joined(separator: "\n")
    }

    private static func chatTranscriptMarkdown(messages: [ChatMessage]) -> String {
        guard !messages.isEmpty else {
            return emptyLiveChatMarkdown(hasRemoteSource: true)
        }

        var lines: [String] = [
            "# Live Chat Transcript",
            "",
        ]
        for message in messages {
            lines.append("## \(message.role.markdownLabel)")
            lines.append("")
            lines.append(message.content.isEmpty ? "_(waiting...)_" : message.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func embeddedFixtureMarkdown(for fixture: Fixture) -> String {
        switch fixture.id {
        case "tables":
            return [
                "# Table Showcase",
                "",
                "| Feature | Status | Notes |",
                "| --- | --- | --- |",
                "| Headers | ✅ | H1-H3 with wrapping |",
                "| Lists | ✅ | Ordered + unordered + nested |",
                "| Code | ✅ | Inline and fenced blocks |",
                "| Tables | ✅ | Width-aware rendering policy |",
                "",
                "```swift",
                "struct Cell {",
                "    let text: String",
                "}",
                "```",
                "",
                "> Blockquote: This fixture is embedded to guarantee visible TUI output.",
            ].joined(separator: "\n")
        case "wide-table-cat":
            return [
                "# Wide Table: Cat Breed Comparison",
                "",
                "## 常见猫咪品种对比",
                "",
                "| 品种 | 原产地 | 毛色特征 | 性格特点 | 平均体重 | 寿命 | 饲养难度 | 价格区间 |",
                "| --- | --- | --- | --- | --- | --- | --- | --- |",
                "| 狸花猫 | 中国 | 棕色虎斑纹，短毛密实 | 活泼好动，独立性强，捕鼠能手 | 3.5-5.5kg | 12-16年 | 容易，适应力强 | 低，常见于流浪猫 |",
                "| 布偶猫 | 美国加州 | 重点色，长毛丝滑如绸 | 温顺粘人，像布偶一样柔软 | 4.5-9.0kg | 10-15年 | 中等，需定期梳毛 | 高，纯种幼猫数千 |",
                "| 英国短毛猫 | 英国 | 蓝灰色，圆胖体型，毛质浓密 | 安静温和，不爱动，适合公寓 | 4.0-8.0kg | 12-17年 | 容易，食量较大 | 中等，宠物级可接受 |",
            ].joined(separator: "\n")
        case "narrow":
            return [
                "# Narrow Terminal Fixture",
                "",
                "This sentence is intentionally long to test wrapping behavior under a narrow viewport and ensure rows are recomputed correctly on resize.",
                "",
                "1. First ordered item with extra long detail segment.",
                "2. Second ordered item with `inline code`.",
                "3. Third item with a link: [ForgeLoopTUI](https://github.com/BiBoyang/ForgeLoopTUI).",
                "",
                "- Bullet A",
                "- Bullet B",
                "  - Nested B.1",
                "  - Nested B.2",
            ].joined(separator: "\n")
        case "long-mixed":
            return [
                "# Long Mixed Fixture",
                "",
                "## Paragraph",
                "A mixed markdown sample with multiple constructs to force scrolling and test stream + static parity.",
                "",
                "## Checklist",
                "- [x] Heading render",
                "- [x] List render",
                "- [x] Quote render",
                "- [x] Code render",
                "",
                "## Quote",
                "> Streaming markdown should remain stable across viewport changes.",
                "",
                "## Code",
                "```bash",
                "echo \"ForgeLoopTUI streaming demo\"",
                "```",
                "",
                "## Table",
                "| Col A | Col B | Col C |",
                "| --- | --- | --- |",
                "| A1 | B1 | C1 |",
                "| A2 | B2 | C2 |",
                "| A3 | B3 | C3 |",
            ].joined(separator: "\n")
        default:
            return [
                "# Markdown Sample",
                "",
                "ForgeLoopTUI embedded terminal pane demo.",
                "",
                "## Features",
                "- Streaming markdown updates",
                "- Static markdown render",
                "- Resize-aware viewport layout",
                "",
                "## Quote",
                "> This fallback content guarantees a visible TUI rendering path.",
                "",
                "## Code",
                "```swift",
                "let message = \"hello tui\"",
                "print(message)",
                "```",
                "",
                "## Table",
                "| Item | Value |",
                "| --- | --- |",
                "| mode | static/stream |",
                "| source | fixture/openai-compatible |",
            ].joined(separator: "\n")
        }
    }
}

struct TerminalTextSurface: NSViewRepresentable {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    static let defaultForeground = NSColor(calibratedRed: 0.75, green: 0.90, blue: 0.72, alpha: 1)
    static let defaultBackground = NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 1)

    let cells: [[Cell]]
    let cursorRow: Int
    let cursorCol: Int

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.backgroundColor = Self.defaultBackground
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.font = Self.baseFont

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.lineFragmentPadding = 0
            textContainer.lineBreakMode = .byClipping
        }

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Self.defaultBackground
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let attributed = buildAttributedScreen(
            cells: cells,
            cursorRow: cursorRow,
            cursorCol: cursorCol
        )
        textView.textStorage?.setAttributedString(attributed)
    }

    private func buildAttributedScreen(cells: [[Cell]], cursorRow: Int, cursorCol: Int) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for rowIndex in cells.indices {
            let row = cells[rowIndex]
            if row.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            var segmentText = ""
            var segmentStyle = row[0].style
            var segmentCursor = rowIndex == cursorRow && 0 == cursorCol

            func appendSegment() {
                guard !segmentText.isEmpty else { return }
                output.append(
                    NSAttributedString(
                        string: segmentText,
                        attributes: makeAttributes(style: segmentStyle, cursorActive: segmentCursor)
                    )
                )
                segmentText = ""
            }

            for colIndex in row.indices {
                let cell = row[colIndex]
                let isCursorCell = rowIndex == cursorRow && colIndex == cursorCol
                if cell.style != segmentStyle || isCursorCell != segmentCursor {
                    appendSegment()
                    segmentStyle = cell.style
                    segmentCursor = isCursorCell
                }
                segmentText.append(cell.character)
            }
            appendSegment()

            if rowIndex < cells.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: makeAttributes(style: SGRState(), cursorActive: false)))
            }
        }

        return output
    }

    private func makeAttributes(style: SGRState, cursorActive: Bool) -> [NSAttributedString.Key: Any] {
        let resolvedForeground = resolveColor(style.foreground) ?? Self.defaultForeground
        let resolvedBackground = resolveColor(style.background) ?? Self.defaultBackground
        let font = style.bold ? Self.boldFont : Self.baseFont
        let foreground = style.dim ? resolvedForeground.withAlphaComponent(0.65) : resolvedForeground

        if cursorActive {
            return [
                .font: font,
                .foregroundColor: Self.defaultBackground,
                .backgroundColor: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1),
            ]
        }

        return [
            .font: font,
            .foregroundColor: foreground,
            .backgroundColor: resolvedBackground,
        ]
    }

    private func resolveColor(_ color: ForgeLoopTUI.Color?) -> NSColor? {
        guard let color else { return nil }

        switch color {
        case .standard(let value):
            return Self.standardANSIColor(value)
        case .bright(let value):
            return Self.brightANSIColor(value)
        case .indexed(let index):
            return Self.indexedANSIColor(index)
        case .rgb(let r, let g, let b):
            let rr = CGFloat(max(0, min(255, r))) / 255.0
            let gg = CGFloat(max(0, min(255, g))) / 255.0
            let bb = CGFloat(max(0, min(255, b))) / 255.0
            return NSColor(calibratedRed: rr, green: gg, blue: bb, alpha: 1)
        }
    }

    private static func standardANSIColor(_ value: Int) -> NSColor {
        switch value {
        case 0: return NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.15, alpha: 1)
        case 1: return NSColor(calibratedRed: 0.76, green: 0.20, blue: 0.18, alpha: 1)
        case 2: return NSColor(calibratedRed: 0.19, green: 0.66, blue: 0.34, alpha: 1)
        case 3: return NSColor(calibratedRed: 0.80, green: 0.62, blue: 0.20, alpha: 1)
        case 4: return NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.86, alpha: 1)
        case 5: return NSColor(calibratedRed: 0.68, green: 0.35, blue: 0.78, alpha: 1)
        case 6: return NSColor(calibratedRed: 0.22, green: 0.72, blue: 0.72, alpha: 1)
        case 7: return NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.86, alpha: 1)
        default: return defaultForeground
        }
    }

    private static func brightANSIColor(_ value: Int) -> NSColor {
        switch value {
        case 0: return NSColor(calibratedRed: 0.35, green: 0.39, blue: 0.43, alpha: 1)
        case 1: return NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.31, alpha: 1)
        case 2: return NSColor(calibratedRed: 0.30, green: 0.84, blue: 0.43, alpha: 1)
        case 3: return NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.33, alpha: 1)
        case 4: return NSColor(calibratedRed: 0.45, green: 0.69, blue: 0.97, alpha: 1)
        case 5: return NSColor(calibratedRed: 0.82, green: 0.50, blue: 0.94, alpha: 1)
        case 6: return NSColor(calibratedRed: 0.40, green: 0.88, blue: 0.88, alpha: 1)
        case 7: return NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1)
        default: return defaultForeground
        }
    }

    private static func indexedANSIColor(_ index: Int) -> NSColor {
        let clamped = max(0, min(255, index))

        if clamped < 8 {
            return standardANSIColor(clamped)
        }
        if clamped < 16 {
            return brightANSIColor(clamped - 8)
        }
        if clamped < 232 {
            let cube = clamped - 16
            let r = cube / 36
            let g = (cube % 36) / 6
            let b = cube % 6
            let scale: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(
                calibratedRed: scale[r] / 255,
                green: scale[g] / 255,
                blue: scale[b] / 255,
                alpha: 1
            )
        }

        let gray = CGFloat(8 + (clamped - 232) * 10) / 255
        return NSColor(calibratedWhite: gray, alpha: 1)
    }
}

struct ContentView: View {
    @StateObject private var model = TerminalPaneDemoModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Mode",
                    selection: Binding(
                        get: { model.demoMode },
                        set: { model.setDemoMode($0) }
                    )
                ) {
                    ForEach(model.modeList) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Text(model.progressText)
                    .font(.system(.footnote, design: .monospaced))
                Text(model.terminalInfoText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if model.demoMode == .fixture {
                HStack(spacing: 10) {
                    Picker("Fixture", selection: $model.selectedFixtureID) {
                        ForEach(model.fixtures) { fixture in
                            Text(fixture.title).tag(fixture.id)
                        }
                    }
                    .frame(width: 220)
                    .onChange(of: model.selectedFixtureID, initial: false) { _, _ in
                        model.renderSelectedFixtureStatic()
                    }

                    Button("Render Static") {
                        model.renderSelectedFixtureStatic()
                    }

                    Button("Play Stream") {
                        model.streamSelectedFixture()
                    }
                    .disabled(model.isStreaming)

                    Button("Play Remote SSE") {
                        model.streamSelectedFixtureViaRemote()
                    }
                    .disabled(model.isStreaming || !model.hasRemoteStreamingSource)

                    Button("Stop") {
                        model.stopStreaming()
                    }
                    .disabled(!model.isStreaming)

                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    TextField("Ask the model...", text: $model.chatInputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit {
                            model.sendChatPrompt()
                        }

                    Button("Send") {
                        model.sendChatPrompt()
                    }
                    .disabled(
                        model.isStreaming ||
                        !model.hasRemoteStreamingSource ||
                        model.chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Button("Stop") {
                        model.stopStreaming()
                    }
                    .disabled(!model.isStreaming)

                    Button("Clear") {
                        model.clearLiveChatTranscript()
                    }
                }
            }

            TerminalTextSurface(
                cells: model.screenCells,
                cursorRow: model.cursorRow,
                cursorCol: model.cursorCol
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            model.updateViewport(pixelWidth: proxy.size.width, pixelHeight: proxy.size.height)
                        }
                        .onChange(of: proxy.size, initial: false) { _, newSize in
                            model.updateViewport(pixelWidth: newSize.width, pixelHeight: newSize.height)
                        }
                }
            )

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(model.streamSourceInfoText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.demoMode == .fixture {
                Text("Fixture source: Examples/Fixtures/*.md | Play Stream always demonstrates markdown TUI rendering")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    model.hasRemoteStreamingSource
                    ? "Live chat source ready | Send streams assistant output into the terminal pane."
                    : "Live chat source unavailable | Set OPENAI_API_KEY (or FORGELOOPTUI_OPENAI_API_KEY)."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 900, minHeight: 640)
    }
}

#Preview {
    ContentView()
}
