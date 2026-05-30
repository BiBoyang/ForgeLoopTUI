import Foundation

// MARK: - DeepSeek (OpenAI-compatible) streaming provider

struct DeepSeekProvider: MinimalAIProvider {
    let apiKey: String
    let model: String
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(apiKey: String, model: String = "deepseek-chat") {
        self.apiKey = apiKey
        self.model = model
    }

    func streamReply(to prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                await _stream(prompt: prompt, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func _stream(prompt: String, continuation: AsyncStream<String>.Continuation) async {
        guard let url = URL(string: "https://api.deepseek.com/v1/chat/completions") else {
            continuation.yield("[Error] Invalid URL")
            continuation.finish()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body = RequestBody(
            model: model,
            messages: [.init(role: "user", content: prompt)],
            stream: true
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            continuation.yield("[Error] Failed to encode request: \(error.localizedDescription)")
            continuation.finish()
            return
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            continuation.yield("[Error] Request failed: \(error.localizedDescription)")
            continuation.finish()
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.finish()
            return
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            do {
                for try await line in bytes.lines {
                    errorBody += line
                }
            } catch {
                errorBody = "(could not read error body)"
            }
            let message: String
            if let data = errorBody.data(using: .utf8),
               let err = try? decoder.decode(ErrorResponse.self, from: data) {
                message = err.error.message
            } else {
                message = "HTTP \(httpResponse.statusCode)"
            }
            continuation.yield("[Error] \(message)")
            continuation.finish()
            return
        }

        var buffer = ""
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                if jsonStr == "[DONE]" { break }

                guard let jsonData = jsonStr.data(using: .utf8),
                      let chunk = try? decoder.decode(ChatCompletionChunk.self, from: jsonData)
                else { continue }

                if let content = chunk.choices.first?.delta.content {
                    buffer += content
                    continuation.yield(buffer)
                }
            }
        } catch {
            if !buffer.isEmpty {
                continuation.yield(buffer + "\n[Stream interrupted]")
            } else {
                continuation.yield("[Error] Stream read failed: \(error.localizedDescription)")
            }
        }
        continuation.finish()
    }
}

// MARK: - Request / Response models

private struct RequestBody: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct ErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}
