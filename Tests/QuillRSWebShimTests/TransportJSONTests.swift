import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

@Suite("RSWeb clone — Transport JSON payloads")
struct TransportJSONTests {

    @Test("Encodable payload overload sends JSON data with a content-type header")
    func encodablePayloadOverload() async throws {
        let transport = RecordingTransport()
        let request = URLRequest(url: URL(string: "https://example.com/tags")!)

        try await transport.send(
            request: request,
            method: HTTPMethod.post,
            payload: RenamePayload(oldName: "Old", newName: "New")
        )

        let upload = try #require(transport.upload)
        #expect(upload.method == HTTPMethod.post)
        #expect(upload.request.value(forHTTPHeaderField: HTTPRequestHeader.contentType) == "application/json; charset=utf-8")
        #expect(try JSONDecoder().decode(RenamePayload.self, from: upload.payload) == RenamePayload(oldName: "Old", newName: "New"))
    }

    @Test("Encodable payload plus Decodable result decodes the response")
    func encodablePayloadWithDecodableResult() async throws {
        let transport = RecordingTransport(responseData: try JSONEncoder().encode(APIResult(id: 42)))
        let request = URLRequest(url: URL(string: "https://example.com/subscription")!)

        let (_, result) = try await transport.send(
            request: request,
            method: HTTPMethod.post,
            payload: RenamePayload(oldName: "Old", newName: "New"),
            resultType: APIResult.self
        )

        #expect(result == APIResult(id: 42))
        #expect(try JSONDecoder().decode(RenamePayload.self, from: try #require(transport.upload).payload).newName == "New")
    }

    @Test("Async raw sends require response data")
    func asyncRawSendRequiresResponseData() async throws {
        let transport = RecordingTransport()
        let request = URLRequest(url: URL(string: "https://example.com/no-data")!)

        await #expect(throws: TransportError.noData) {
            _ = try await transport.send(request: request)
        }
        await #expect(throws: TransportError.noData) {
            _ = try await transport.send(request: request, method: HTTPMethod.post, payload: Data())
        }
    }

    private struct RenamePayload: Codable, Equatable, Sendable {
        let oldName: String
        let newName: String
    }

    private struct APIResult: Codable, Equatable, Sendable {
        let id: Int
    }

    private struct Upload: Sendable {
        let request: URLRequest
        let method: String
        let payload: Data
    }

    private final class RecordingTransport: Transport, @unchecked Sendable {
        private let lock = NSLock()
        private let responseData: Data?
        private var recordedUpload: Upload?

        var upload: Upload? {
            lock.lock()
            defer { lock.unlock() }
            return recordedUpload
        }

        init(responseData: Data? = nil) {
            self.responseData = responseData
        }

        func cancelAll() {}

        func send(request: URLRequest) async throws -> (HTTPURLResponse, Data) {
            guard let responseData else {
                throw TransportError.noData
            }
            return (Self.okResponse(url: request.url), responseData)
        }

        func send(request: URLRequest, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void) {
            completion(.success((Self.okResponse(url: request.url), responseData)))
        }

        func send(request: URLRequest, method: String) async throws {}

        func send(request: URLRequest, method: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
            completion(.success(()))
        }

        func send(request: URLRequest, method: String, payload: Data) async throws -> (HTTPURLResponse, Data) {
            record(request: request, method: method, payload: payload)
            guard let responseData else {
                throw TransportError.noData
            }
            return (Self.okResponse(url: request.url), responseData)
        }

        func send(
            request: URLRequest,
            method: String,
            payload: Data,
            completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void
        ) {
            record(request: request, method: method, payload: payload)
            completion(.success((Self.okResponse(url: request.url), responseData)))
        }

        private func record(request: URLRequest, method: String, payload: Data) {
            lock.lock()
            recordedUpload = Upload(request: request, method: method, payload: payload)
            lock.unlock()
        }

        private static func okResponse(url: URL?) -> HTTPURLResponse {
            HTTPURLResponse(url: url ?? URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }
    }
}
