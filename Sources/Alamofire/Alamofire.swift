import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Security

public protocol ServerTrustEvaluating {
    func evaluate(_ trust: SecTrust, forHost host: String) throws
}

public enum AFError: Error, Sendable {
    case invalidURL(url: String)
    case responseValidationFailed(reason: ResponseValidationFailureReason)
    case responseSerializationFailed(reason: ResponseSerializationFailureReason)
    case serverTrustEvaluationFailed(reason: ServerTrustFailureReason)

    public enum ResponseValidationFailureReason: Sendable {
        case nonHTTPURLResponse
        case unacceptableStatusCode(code: Int)
    }

    public enum ResponseSerializationFailureReason: Sendable {
        case inputDataNilOrZeroLength
        case decodingFailed(error: Error)
    }

    public enum ServerTrustFailureReason: Sendable {
        case customEvaluationFailed(error: Error)
    }
}

public final class ServerTrustManager: @unchecked Sendable {
    public let allHostsMustBeEvaluated: Bool
    public let evaluators: [String: ServerTrustEvaluating]

    public init(allHostsMustBeEvaluated: Bool, evaluators: [String: ServerTrustEvaluating]) {
        self.allHostsMustBeEvaluated = allHostsMustBeEvaluated
        self.evaluators = evaluators
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

internal typealias AlamofireTransport = @Sendable (
    URLRequest,
    @escaping (Result<(Data, URLResponse), Error>) -> Void
) -> Void

private enum AlamofireNetworkingError: Error, Sendable {
    case missingResponse
}

public final class Session: @unchecked Sendable {
    private let serverTrustManager: ServerTrustManager?
    private let transport: AlamofireTransport

    public init(serverTrustManager: ServerTrustManager? = nil) {
        self.serverTrustManager = serverTrustManager
        self.transport = Self.urlSessionTransport
    }

    internal init(
        serverTrustManager: ServerTrustManager? = nil,
        transport: @escaping AlamofireTransport
    ) {
        self.serverTrustManager = serverTrustManager
        self.transport = transport
    }

    public func request(_ convertible: String, method: HTTPMethod = .get) -> DataRequest {
        guard
            let url = URL(string: convertible),
            url.scheme != nil
        else {
            return DataRequest(initializationError: AFError.invalidURL(url: convertible), transport: transport)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        return DataRequest(request: request, transport: transport)
    }

    fileprivate static let urlSessionTransport: AlamofireTransport = { request, completion in
        let completion = TransportCompletionBox(completion)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion.call(.failure(error))
                return
            }

            guard let data, let response else {
                completion.call(.failure(AlamofireNetworkingError.missingResponse))
                return
            }

            completion.call(.success((data, response)))
        }
        task.resume()
    }
}

public final class DataRequest: @unchecked Sendable {
    private let request: URLRequest?
    private let initializationError: Error?
    private let transport: AlamofireTransport
    private var acceptableStatusCodes: Range<Int>?

    public convenience init() {
        self.init(initializationError: QuillAlamofireCompatibilityError.noResponse, transport: Session.urlSessionTransport)
    }

    internal init(
        request: URLRequest? = nil,
        initializationError: Error? = nil,
        transport: @escaping AlamofireTransport
    ) {
        self.request = request
        self.initializationError = initializationError
        self.transport = transport
    }

    public func validate(statusCode acceptableStatusCodes: Range<Int>) -> DataRequest {
        self.acceptableStatusCodes = acceptableStatusCodes
        return self
    }

    public func responseDecodable<Value: Decodable>(
        of type: Value.Type,
        queue: DispatchQueue = .main,
        completionHandler: @escaping (DataResponse<Value>) -> Void
    ) {
        let completion = CompletionBox(completionHandler)
        let queueBox = DispatchQueueBox(queue)

        if let initializationError {
            Self.deliver(DataResponse(result: .failure(initializationError)), on: queueBox, to: completion)
            return
        }

        guard let request else {
            Self.deliver(
                DataResponse(result: .failure(QuillAlamofireCompatibilityError.noResponse)),
                on: queueBox,
                to: completion
            )
            return
        }

        let acceptableStatusCodes = acceptableStatusCodes
        let decoder = ResponseDecoderBox(type: type)
        transport(request) { result in
            let response: DataResponse<Value>

            switch result {
            case .success(let (data, urlResponse)):
                response = decoder.decode(
                    data: data,
                    response: urlResponse,
                    acceptableStatusCodes: acceptableStatusCodes
                )
            case .failure(let error):
                response = DataResponse(result: .failure(error))
            }

            Self.deliver(response, on: queueBox, to: completion)
        }
    }

    fileprivate static func decode<Value: Decodable>(
        data: Data,
        response: URLResponse,
        acceptableStatusCodes: Range<Int>?,
        as type: Value.Type
    ) -> DataResponse<Value> {
        if let acceptableStatusCodes {
            guard let httpResponse = response as? HTTPURLResponse else {
                return DataResponse(result: .failure(AFError.responseValidationFailed(reason: .nonHTTPURLResponse)))
            }

            guard acceptableStatusCodes.contains(httpResponse.statusCode) else {
                return DataResponse(
                    result: .failure(
                        AFError.responseValidationFailed(
                            reason: .unacceptableStatusCode(code: httpResponse.statusCode)
                        )
                    )
                )
            }
        }

        guard !data.isEmpty else {
            return DataResponse(result: .failure(AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)))
        }

        do {
            let value = try JSONDecoder().decode(type, from: data)
            return DataResponse(result: .success(value))
        } catch {
            return DataResponse(result: .failure(AFError.responseSerializationFailed(reason: .decodingFailed(error: error))))
        }
    }

    private static func deliver<Value>(
        _ response: DataResponse<Value>,
        on queue: DispatchQueueBox,
        to completion: CompletionBox<Value>
    ) {
        let responseBox = DataResponseBox(response)
        queue.queue.async {
            completion.call(responseBox.response)
        }
    }
}

public struct DataResponse<Value> {
    public var result: Result<Value, Error>

    public init(result: Result<Value, Error>) {
        self.result = result
    }
}

private enum QuillAlamofireCompatibilityError: Error {
    case noResponse
}

private final class CompletionBox<Value>: @unchecked Sendable {
    private let completion: (DataResponse<Value>) -> Void

    init(_ completion: @escaping (DataResponse<Value>) -> Void) {
        self.completion = completion
    }

    func call(_ response: DataResponse<Value>) {
        completion(response)
    }
}

private final class DataResponseBox<Value>: @unchecked Sendable {
    let response: DataResponse<Value>

    init(_ response: DataResponse<Value>) {
        self.response = response
    }
}

private final class DispatchQueueBox: @unchecked Sendable {
    let queue: DispatchQueue

    init(_ queue: DispatchQueue) {
        self.queue = queue
    }
}

private final class TransportCompletionBox: @unchecked Sendable {
    private let completion: (Result<(Data, URLResponse), Error>) -> Void

    init(_ completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        self.completion = completion
    }

    func call(_ result: Result<(Data, URLResponse), Error>) {
        completion(result)
    }
}

private final class ResponseDecoderBox<Value: Decodable>: @unchecked Sendable {
    private let type: Value.Type

    init(type: Value.Type) {
        self.type = type
    }

    func decode(
        data: Data,
        response: URLResponse,
        acceptableStatusCodes: Range<Int>?
    ) -> DataResponse<Value> {
        DataRequest.decode(
            data: data,
            response: response,
            acceptableStatusCodes: acceptableStatusCodes,
            as: type
        )
    }
}
