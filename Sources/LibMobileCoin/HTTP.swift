// LibMobileCoin HTTP plumbing surface -- SignalUI's
// Payments/MobileCoinAPI+Configuration.swift implements the MobileCoin
// module's `HttpRequester` protocol (MobileCoinHttpRequester): it switches
// exhaustively over `LibMobileCoin.HTTPMethod` (so the case set must match
// the real SDK exactly) and constructs `LibMobileCoin.HTTPResponse` values
// from OWSURLSession responses.
//
// Inert on Linux: the MobileCoin shim client never invokes its injected
// HttpRequester, so these values are only ever constructed and mapped, never
// sent anywhere.

import Foundation

public enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case HEAD
    case PATCH
    case DELETE
}

public struct HTTPResponse {
    public let statusCode: Int
    public let url: URL?
    public let allHeaderFields: [String: String]
    public let responseData: Data?

    public init(statusCode: Int, url: URL?, allHeaderFields: [String: String], responseData: Data?) {
        self.statusCode = statusCode
        self.url = url
        self.allHeaderFields = allHeaderFields
        self.responseData = responseData
    }
}
