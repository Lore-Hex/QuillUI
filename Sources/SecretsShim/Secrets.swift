@_exported import Foundation
@_exported import QuillFoundation

public enum SecretKey {
    public static let feedlyClientID = ""
    public static let feedlyClientSecret = ""
    public static let newsBlurConsumerKey = ""
    public static let newsBlurConsumerSecret = ""
    public static let redditConsumerKey = ""
    public static let inoreaderAppID = ""
    public static let inoreaderAppKey = ""
    public static let mercuryClientID = ""
    public static let mercuryClientSecret = ""
}

public enum CredentialsType: String, Sendable {
    case basic
    case readerBasic
    case readerAPIKey
    case oauthAccessToken
    case oauthAccessTokenSecret
    case oauthRefreshToken
    case newsBlurBasic
    case newsBlurSessionID
}

public struct Credentials: Sendable, Equatable {
    public let type: CredentialsType
    public let username: String
    public let secret: String
    public init(type: CredentialsType, username: String, secret: String) {
        self.type = type
        self.username = username
        self.secret = secret
    }
}

public enum CredentialsError: Error {
    case missingAccessToken
    case missingUsername
    case missingEndpointURL
}

public enum CredentialsManager {
    public static func storeCredentials(_ credentials: Credentials, server: String) throws {}
    public static func retrieveCredentials(type: CredentialsType, server: String, username: String) throws -> Credentials? { nil }
    public static func removeCredentials(type: CredentialsType, server: String, username: String) throws {}
}
