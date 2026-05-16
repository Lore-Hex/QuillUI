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

private func runCurlStream(
    requestURL: URL,
    requestFileURL: URL,
    continuation: AsyncThrowingStream<String, Error>.Continuation
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = [
        "--no-buffer",
        "--silent",
        "--show-error",
        "--fail-with-body",
        "--request", "POST",
        "--header", "Content-Type: application/json",
        "--data-binary", "@\(requestFileURL.path)",
        requestURL.absoluteString
    ]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw OllamaClientError.streamingUnavailable("Could not start curl for Ollama streaming: \(error.localizedDescription)")
    }

    var buffer = Data()
    var sawDone = false

    while true {
        let chunk = stdout.fileHandleForReading.availableData
        if chunk.isEmpty {
            break
        }
        buffer.append(chunk)

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            let line = String(decoding: lineData, as: UTF8.self)
            sawDone = try handleStreamLine(line, continuation: continuation) || sawDone
        }
    }

    if !buffer.isEmpty && !sawDone {
        let line = String(decoding: buffer, as: UTF8.self)
        _ = try handleStreamLine(line, continuation: continuation)
    }

    process.waitUntilExit()
    let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    try? FileManager.default.removeItem(at: requestFileURL)

    guard process.terminationStatus == 0 else {
        throw OllamaClientError.server(Int(process.terminationStatus), errorOutput.quillTrimmedNonEmpty ?? "curl stream failed")
    }

    continuation.finish()
}

@discardableResult
private func handleStreamLine(
    _ line: String,
    continuation: AsyncThrowingStream<String, Error>.Continuation
) throws -> Bool {
    guard let event = try OllamaStreamParser.parseLine(line) else {
        return false
    }

    switch event {
    case .content(let content):
        continuation.yield(content)
        return false
    case .done:
        return true
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
    var done: Bool?
    var error: String?
}
