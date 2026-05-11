// Local re-implementation of the Mastodon API surface from
// `Dimillian/IceCubesApp/Packages/Models` + `NetworkClient`.
//
// The upstream packages restrict themselves to
// `platforms: [.iOS(.v18), .visionOS(.v1)]` so they don't
// resolve as path dependencies on macOS or Linux. Rather than
// fork the upstream platform pins, redeclare the minimal
// subset that `QuillIceCubesContentView` needs — the public-
// timeline shell. Each type carries the same property names
// and signatures used by upstream so future ports of larger
// IceCubes views can compile against this surface without
// app-side rewrites.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - HTML payload wrapper

/// Mastodon status fields like `content`, `account.displayName`,
/// and emoji-shortcode strings arrive HTML-formatted. Upstream
/// `Models.HTMLString` decodes them lazily; this stub strips
/// tags + decodes a small set of HTML entities so the
/// placeholder timeline shows readable text.
public struct HTMLString: Codable, Hashable, Sendable {
    public var htmlValue: String

    public init(stringLiteral: String) {
        self.htmlValue = stringLiteral
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.htmlValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(htmlValue)
    }

    public var asRawText: String {
        var output = ""
        output.reserveCapacity(htmlValue.count)
        var insideTag = false
        for character in htmlValue {
            if character == "<" {
                insideTag = true
            } else if character == ">" {
                insideTag = false
            } else if !insideTag {
                output.append(character)
            }
        }
        return output
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// MARK: - Account

public struct Account: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let acct: String
    public let username: String
    public let displayName: String?
    public let avatar: URL?

    public init(
        id: String,
        acct: String,
        username: String,
        displayName: String? = nil,
        avatar: URL? = nil
    ) {
        self.id = id
        self.acct = acct
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
    }

    public var cachedDisplayName: HTMLString {
        HTMLString(stringLiteral: displayName ?? username)
    }
}

// MARK: - Status

public struct Status: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let account: Account
    public let content: HTMLString
    public let createdAt: String

    public init(
        id: String,
        account: Account,
        content: HTMLString,
        createdAt: String = ""
    ) {
        self.id = id
        self.account = account
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - Endpoint + Timelines

public protocol Endpoint: Sendable {
    var path: String { get }
    var query: [URLQueryItem] { get }
}

/// Mirrors upstream `Models.Timelines` enum's case set — only
/// `pub` is wired today, but the shape keeps room for the
/// other cases (`home`, `hashtag`, `list`, etc.) as the
/// IceCubes port grows.
public enum Timelines: Endpoint, Sendable {
    case pub(sinceId: String?, maxId: String?, minId: String?, local: Bool, limit: Int)

    public var path: String {
        switch self {
        case .pub:
            return "/api/v1/timelines/public"
        }
    }

    public var query: [URLQueryItem] {
        switch self {
        case let .pub(sinceId, maxId, minId, local, limit):
            var items: [URLQueryItem] = [
                URLQueryItem(name: "local", value: local ? "true" : "false"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
            if let sinceId { items.append(URLQueryItem(name: "since_id", value: sinceId)) }
            if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
            if let minId { items.append(URLQueryItem(name: "min_id", value: minId)) }
            return items
        }
    }
}

// MARK: - MastodonClient

public enum MastodonVersion: Sendable {
    case v1
    case v2

    fileprivate var pathSegment: String {
        switch self {
        case .v1: return "v1"
        case .v2: return "v2"
        }
    }
}

public enum MastodonClientError: Error, Sendable {
    case invalidServer(String)
    case invalidResponse
    case http(statusCode: Int)
}

public struct MastodonClient: Sendable {
    public let server: String
    public let version: MastodonVersion
    public let oauthToken: String?

    public init(
        server: String,
        version: MastodonVersion = .v1,
        oauthToken: String? = nil
    ) {
        self.server = server
        self.version = version
        self.oauthToken = oauthToken
    }

    public func get<T: Decodable & Sendable>(endpoint: Endpoint) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = server
        components.path = endpoint.path
        components.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
        guard let url = components.url else {
            throw MastodonClientError.invalidServer(server)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let oauthToken {
            request.setValue("Bearer \(oauthToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MastodonClientError.http(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
