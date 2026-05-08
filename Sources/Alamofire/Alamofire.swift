import Foundation
import Security

public protocol ServerTrustEvaluating {
    func evaluate(_ trust: SecTrust, forHost host: String) throws
}

public enum AFError: Error, Sendable {
    case serverTrustEvaluationFailed(reason: ServerTrustFailureReason)

    public enum ServerTrustFailureReason: Sendable {
        case customEvaluationFailed(error: Error)
    }
}

public final class ServerTrustManager: @unchecked Sendable {
    public init(allHostsMustBeEvaluated: Bool, evaluators: [String: ServerTrustEvaluating]) {}
}

public enum HTTPMethod: Sendable {
    case get
    case post
}

public final class Session: @unchecked Sendable {
    public init(serverTrustManager: ServerTrustManager? = nil) {}

    public func request(_ convertible: String, method: HTTPMethod = .get) -> DataRequest {
        DataRequest()
    }
}

public final class DataRequest: @unchecked Sendable {
    public init() {}

    public func validate(statusCode acceptableStatusCodes: Range<Int>) -> DataRequest {
        self
    }

    public func responseDecodable<Value: Decodable>(
        of type: Value.Type,
        queue: DispatchQueue = .main,
        completionHandler: @escaping (DataResponse<Value>) -> Void
    ) {
        completionHandler(DataResponse(result: .failure(AFError.serverTrustEvaluationFailed(reason: .customEvaluationFailed(error: QuillAlamofireCompatibilityError.noResponse)))))
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
