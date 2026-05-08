import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine

public enum OllamaKitError: Error, LocalizedError, Sendable {
    case invalidResponse
    case server(statusCode: Int, body: String)
    case malformedStreamLine(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ollama returned an invalid response."
        case .server(let statusCode, let body):
            return "Ollama returned HTTP \(statusCode): \(body)"
        case .malformedStreamLine(let line):
            return "Ollama returned malformed stream data: \(line)"
        }
    }
}

public protocol OllamaKitTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionOllamaKitTransport: OllamaKitTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public final class OllamaKit: @unchecked Sendable {
    public let baseURL: URL
    public let bearerToken: String?
    private let transport: any OllamaKitTransport

    public init(
        baseURL: URL,
        bearerToken: String? = nil,
        transport: any OllamaKitTransport = URLSessionOllamaKitTransport()
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.transport = transport
    }

    public func models() async throws -> OKModelsResponse {
        let (data, response) = try await transport.data(for: request(path: "api/tags"))
        try validate(response: response, data: data)
        return try JSONDecoder().decode(OKModelsResponse.self, from: data)
    }

    public func reachable() async -> Bool {
        do {
            let (_, response) = try await transport.data(for: request(path: "api/version"))
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    public func chat(data requestData: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error> {
        Deferred { [self] in
            let box = OKChatSubjectBox()
            let task = Task {
                do {
                    let responses = try await performChat(data: requestData)
                    for response in responses {
                        guard !Task.isCancelled else { return }
                        box.send(response)
                    }
                    box.send(completion: .finished)
                } catch {
                    box.send(completion: .failure(error))
                }
            }

            return box.publisher
                .handleEvents(receiveCancel: {
                    task.cancel()
                })
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    private func performChat(data requestData: OKChatRequestData) async throws -> [OKChatResponse] {
        var request = request(path: "api/chat")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload = requestData
        if payload.stream == nil {
            payload.stream = true
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
        return try Self.decodeChatResponses(from: data)
    }

    private func request(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OllamaKitError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaKitError.server(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    public static func decodeChatResponses(from data: Data) throws -> [OKChatResponse] {
        let decoder = JSONDecoder()
        let text = String(decoding: data, as: UTF8.self)
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return try lines.map { line in
                guard let lineData = line.data(using: .utf8) else {
                    throw OllamaKitError.malformedStreamLine(line)
                }
                return try decoder.decode(OKChatResponse.self, from: lineData)
            }
        }

        return [try decoder.decode(OKChatResponse.self, from: data)]
    }
}

private final class OKChatSubjectBox: @unchecked Sendable {
    let publisher = PassthroughSubject<OKChatResponse, Error>()

    func send(_ response: OKChatResponse) {
        publisher.send(response)
    }

    func send(completion: Subscribers.Completion<Error>) {
        publisher.send(completion: completion)
    }
}

public struct OKModelsResponse: Codable, Equatable, Sendable {
    public var models: [OKModelResponse]

    public init(models: [OKModelResponse]) {
        self.models = models
    }
}

public struct OKModelResponse: Codable, Equatable, Sendable {
    public var name: String
    public var details: OKModelDetails

    public init(name: String, details: OKModelDetails = OKModelDetails()) {
        self.name = name
        self.details = details
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.details = try container.decodeIfPresent(OKModelDetails.self, forKey: .details) ?? OKModelDetails()
    }
}

public struct OKModelDetails: Codable, Equatable, Sendable {
    public var families: [String]?

    public init(families: [String]? = nil) {
        self.families = families
    }
}

public struct OKCompletionOptions: Codable, Equatable, Sendable {
    public var temperature: Double?

    public init(temperature: Double? = nil) {
        self.temperature = temperature
    }
}

public struct OKChatRequestData: Codable, Equatable, Sendable {
    public var model: String
    public var messages: [Message]
    public var options: OKCompletionOptions?
    public var stream: Bool?

    public init(
        model: String,
        messages: [Message],
        options: OKCompletionOptions? = nil,
        stream: Bool? = nil
    ) {
        self.model = model
        self.messages = messages
        self.options = options
        self.stream = stream
    }

    public struct Message: Codable, Equatable, Sendable {
        public var role: Role
        public var content: String
        public var images: [String]?

        public init(role: Role, content: String, images: [String]? = nil) {
            self.role = role
            self.content = content
            self.images = images
        }

        public enum Role: String, Codable, Equatable, Sendable {
            case system
            case user
            case assistant
            case tool
        }
    }
}

public struct OKChatResponse: Codable, Equatable, Sendable {
    public var message: OKChatRequestData.Message?
    public var response: String?
    public var done: Bool?
    public var error: String?

    public init(
        message: OKChatRequestData.Message? = nil,
        response: String? = nil,
        done: Bool? = nil,
        error: String? = nil
    ) {
        self.message = message
        self.response = response
        self.done = done
        self.error = error
    }
}
