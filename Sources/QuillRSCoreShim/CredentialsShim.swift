// Minimal Secrets.Credentials shim — just the two value types
// that vendored upstream modules (NewsBlur, FeedFinder, future
// Account) reference via `import Secrets`. The full upstream
// Secrets module includes CredentialsManager which wraps
// macOS Security.framework keychain APIs (SecItemAdd / SecItemCopyMatching
// / SecAccessControlCreateWithFlags) that swift-corelibs-foundation
// has no equivalent for. Account login flows that depend on the
// keychain path land alongside a QuillKeychain shim in a later
// iteration (file-backed, encrypted-at-rest, opt-in).

import Foundation

/// Mirrors `Secrets.CredentialsType`. Raw values match upstream
/// byte-for-byte so on-disk credentials written by upstream
/// NetNewsWire (or future cross-installation imports) decode
/// the same way.
public enum CredentialsType: String, Sendable {
    case basic = "password"
    case newsBlurBasic = "newsBlurBasic"
    case newsBlurSessionID = "newsBlurSessionId"
    case readerBasic = "readerBasic"
    case readerAPIKey = "readerAPIKey"
    case oauthAccessToken = "oauthAccessToken"
    case oauthAccessTokenSecret = "oauthAccessTokenSecret"
    case oauthRefreshToken = "oauthRefreshToken"
}

/// Mirrors `Secrets.Credentials`. The 3-field tuple used to
/// authenticate against every sync backend NetNewsWire supports.
/// Equatable + Sendable for the same reasons upstream needs:
/// safe to pass between actors, comparable when account
/// configuration changes.
nonisolated public struct Credentials: Equatable, Sendable {
    public let type: CredentialsType
    public let username: String
    public let secret: String

    public init(type: CredentialsType, username: String, secret: String) {
        self.type = type
        self.username = username
        self.secret = secret
    }
}
