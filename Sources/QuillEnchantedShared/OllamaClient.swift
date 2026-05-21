import Foundation
import QuillEnchantedData
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OllamaClientError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case invalidBaseURL(String)
    case invalidResponse
    case server(Int, String)
    case noModelSelected
    case malformedStream(String)
    case streamingUnavailable(String)

    public var description: String {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid Ollama URL: \(value)"
        case .invalidResponse:
            return "Ollama returned an invalid response."
        case .server(let status, let body):
            return "Ollama returned HTTP \(status): \(body)"
        case .noModelSelected:
            return "Choose an Ollama model before sending a message."
        case .malformedStream(let line):
            return "Ollama returned malformed stream data: \(line)"
        case .streamingUnavailable(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}

public struct OllamaClient: Sendable {
    private let baseURL: URL

    public init(baseURL: String) throws {
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: normalized), url.scheme != nil, url.host != nil else {
            throw OllamaClientError.invalidBaseURL(baseURL)
        }
        self.baseURL = url
    }

    public func fetchModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models
            .map { OllamaModel(name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func chat(model: String, messages: [ChatMessage], imagesForLastUserMessage: [String] = []) async throws -> String {
        guard model.quillTrimmedNonEmpty != nil else {
            throw OllamaClientError.noModelSelected
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: apiMessages(from: messages, imagesForLastUserMessage: imagesForLastUserMessage),
                stream: false
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.message?.content.quillTrimmedNonEmpty ?? decoded.response?.quillTrimmedNonEmpty ?? ""
    }

    public func streamChat(
        model: String,
        messages: [ChatMessage],
        imagesForLastUserMessage: [String] = []
    ) throws -> AsyncThrowingStream<String, Error> {
        guard model.quillTrimmedNonEmpty != nil else {
            throw OllamaClientError.noModelSelected
        }

        let requestBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: apiMessages(from: messages, imagesForLastUserMessage: imagesForLastUserMessage),
                stream: true
            )
        )
        let requestURL = baseURL.appendingPathComponent("api/chat")
        let requestFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillui-ollama-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try requestBody.write(to: requestFileURL, options: [.atomic])

        return AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    try runCurlStream(
                        requestURL: requestURL,
                        requestFileURL: requestFileURL,
                        continuation: continuation
                    )
                } catch {
                    try? FileManager.default.removeItem(at: requestFileURL)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaClientError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func apiMessages(from messages: [ChatMessage], imagesForLastUserMessage: [String]) -> [APIMessage] {
        var apiMessages = messages.map {
            APIMessage(role: $0.role.rawValue, content: $0.content)
        }

        if !imagesForLastUserMessage.isEmpty,
           let index = apiMessages.lastIndex(where: { $0.role == ChatRole.user.rawValue }) {
            apiMessages[index].images = imagesForLastUserMessage
        }

        return apiMessages
    }
}

/// Locate `curl` on disk. Hard-coding `/usr/bin/curl` broke on systems
/// where curl lives in `/usr/local/bin` or only as a symlink; this walks
/// PATH and the common install prefixes.
private func locateCurlExecutable() -> URL? {
    let candidates = ["/usr/bin/curl", "/usr/local/bin/curl", "/snap/bin/curl", "/bin/curl"]
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/curl"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
    }
    return nil
}

/// Emit a diagnostic line to FileHandle.standardError. Visible when the
/// app is launched via the `quill-brain` wrapper (which tees to
/// `/tmp/quill-chat.log`).
private func ollamaLog(_ message: @autoclosure () -> String) {
    let line = "[ollama] \(message())\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func runCurlStream(
    requestURL: URL,
    requestFileURL: URL,
    continuation: AsyncThrowingStream<String, Error>.Continuation
) throws {
    guard let curlURL = locateCurlExecutable() else {
        throw OllamaClientError.streamingUnavailable(
            "curl not found on PATH or in /usr/{bin,local/bin}, /snap/bin, /bin. "
            + "Install curl or set OLLAMA_NO_STREAM=1 to use the non-streaming fallback."
        )
    }

    let process = Process()
    process.executableURL = curlURL
    process.arguments = [
        "--no-buffer",
        "--silent",
        "--show-error",
        // NB: do NOT pass --fail-with-body. curl exits non-zero on HTTP
        // 4xx/5xx and writes the body to stdout — but we then try to
        // parse the body as NDJSON further down and throw .malformedStream
        // instead of surfacing the actual server error. We check
        // terminationStatus + parse the buffer ourselves below.
        "--request", "POST",
        "--header", "Content-Type: application/json",
        "--header", "Accept: application/x-ndjson",
        "--data-binary", "@\(requestFileURL.path)",
        requestURL.absoluteString,
    ]
    ollamaLog("streamChat → \(curlURL.path) \(process.arguments?.joined(separator: " ") ?? "")")

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw OllamaClientError.streamingUnavailable(
            "Could not start curl for Ollama streaming: \(error.localizedDescription)"
        )
    }

    // Kill curl if the consuming Task is cancelled. The continuation's
    // onTermination is the standard hook for this; without it the curl
    // process keeps running after the user clicks Stop.
    continuation.onTermination = { [process] _ in
        if process.isRunning {
            process.terminate()
        }
    }

    var buffer = Data()
    var sawDone = false
    var totalBytes = 0
    var parsedEvents = 0
    var yieldedContentChunks = 0
    var didWaitForExit = false

    defer {
        if process.isRunning {
            process.terminate()
        }
        if !didWaitForExit {
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: requestFileURL)
    }

    // Read with explicit byte-count semantics rather than relying on
    // availableData. On Linux Foundation availableData has historically
    // had inconsistent EOF semantics; reading until read(upToCount:)
    // returns nil (or an empty Data) is the reliable signal.
    let handle = stdout.fileHandleForReading
    while true {
        let chunk: Data
        if #available(macOS 10.15.4, *) {
            chunk = (try? handle.read(upToCount: 4096)) ?? Data()
        } else {
            chunk = handle.availableData
        }
        if chunk.isEmpty { break }
        totalBytes += chunk.count
        buffer.append(chunk)

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            let line = String(decoding: lineData, as: UTF8.self)
            do {
                if let event = try handleStreamLine(line, continuation: continuation) {
                    parsedEvents += 1
                    switch event {
                    case .content:
                        yieldedContentChunks += 1
                    case .done:
                        sawDone = true
                    case .error:
                        break
                    }
                }
            } catch {
                ollamaLog("malformedStream while parsing: \(line.prefix(200))")
                throw error
            }
        }
    }

    if !buffer.isEmpty && !sawDone {
        let line = String(decoding: buffer, as: UTF8.self)
        if let event = try handleStreamLine(line, continuation: continuation) {
            parsedEvents += 1
            switch event {
            case .content:
                yieldedContentChunks += 1
            case .done:
                sawDone = true
            case .error:
                break
            }
        }
    }

    process.waitUntilExit()
    didWaitForExit = true
    let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    ollamaLog(
        "streamChat finished: exit=\(process.terminationStatus) bytes=\(totalBytes) "
        + "events=\(parsedEvents) contentChunks=\(yieldedContentChunks) sawDone=\(sawDone)"
    )

    if process.terminationStatus != 0 {
        // curl exited non-zero. Without --fail-with-body the body may
        // already have been delivered as content lines (if it was
        // valid NDJSON), in which case the stream is fine. Otherwise
        // surface the stderr so the user sees the real reason.
        let errorBody = stderrText.quillTrimmedNonEmpty
            ?? "curl exited \(process.terminationStatus) with no stderr"
        ollamaLog("streamChat curl-error: \(errorBody)")
        if parsedEvents == 0 {
            throw OllamaClientError.server(Int(process.terminationStatus), errorBody)
        }
    }

    // If curl exited cleanly but the parser never saw a content or done
    // event, that's a silent-empty-stream. Blank/keepalive lines are not
    // enough to create a useful assistant response, so surface this
    // explicitly instead of completing as an empty message.
    if parsedEvents == 0 {
        throw OllamaClientError.streamingUnavailable(
            "Ollama stream returned no NDJSON events (\(totalBytes) bytes total). "
            + "Check that the model is loaded: `ollama run <model>` once to warm it up."
        )
    }

    continuation.finish()
}

@discardableResult
private func handleStreamLine(
    _ line: String,
    continuation: AsyncThrowingStream<String, Error>.Continuation
) throws -> OllamaStreamEvent? {
    guard let event = try OllamaStreamParser.parseLine(line) else {
        return nil
    }

    switch event {
    case .content(let content):
        continuation.yield(content)
        return event
    case .done:
        return event
    case .error(let message):
        throw OllamaClientError.server(500, message)
    }
}

public enum OllamaStreamEvent: Equatable {
    case content(String)
    case done
    case error(String)
}

public enum OllamaStreamParser {
    public static func parseLine(_ line: String) throws -> OllamaStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else {
            throw OllamaClientError.malformedStream(line)
        }

        do {
            let chunk = try JSONDecoder().decode(StreamChatResponse.self, from: data)
            if let error = chunk.error?.quillTrimmedNonEmpty {
                return .error(error)
            }
            if let content = chunk.message?.content, !content.isEmpty {
                return .content(content)
            }
            if let response = chunk.response, !response.isEmpty {
                return .content(response)
            }
            if chunk.done == true {
                return .done
            }
            return nil
        } catch {
            throw OllamaClientError.malformedStream(line)
        }
    }
}

private struct TagsResponse: Decodable, Sendable {
    var models: [TagModel]
}

private struct TagModel: Decodable, Sendable {
    var name: String
}

private struct ChatRequest: Encodable, Sendable {
    var model: String
    var messages: [APIMessage]
    var stream: Bool
}

private struct APIMessage: Codable, Sendable {
    var role: String
    var content: String
    var images: [String]?
}

private struct ChatResponse: Decodable, Sendable {
    var message: APIMessage?
    var response: String?
}

private struct StreamChatResponse: Decodable, Sendable {
    var message: APIMessage?
    var response: String?
    var done: Bool?
    var error: String?
}
