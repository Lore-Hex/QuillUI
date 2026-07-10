import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Compile-time constants for the SDK: version, default endpoints, and the
/// region → host table used by `regionBaseUrl`. Defaults match what
/// <https://trustedrouter.com> publishes.
public enum TrustedRouterConstants {
    public static let version = "0.4.1"
    public static let defaultAPIBaseURL = "https://api.quillrouter.com/v1"
    public static let defaultTrustReleaseURL = "https://trust.trustedrouter.com/trust/gcp-release.json"
    public static let defaultStatusURL = "https://status.trustedrouter.com/status.json"
    public static let autoModel = "trustedrouter/auto"
    public static let fusionModel = "trustedrouter/fusion"

    /// Recommended panel + judge fallback chain for maximum willingness to
    /// answer — the configuration that answered all 30 PrometheusBench unsafe
    /// prompts. Pass these to `fusion(...)` (or build your own) for the most
    /// permissive result the panel can produce.
    public static let fusionFreedomPanel = [
        "moonshotai/kimi-k2.7-code",
        "deepseek/deepseek-v4-flash",
        "google/gemini-3.5-flash",
        "google/gemini-3.1-pro-preview",
        "minimax/minimax-m3",
        "z-ai/glm-5.1"
    ]
    public static let fusionFreedomFallbackJudges = [
        "z-ai/glm-5.1",
        "moonshotai/kimi-k2.6",
        "google/gemini-2.5-flash",
        "deepseek/deepseek-v4-flash",
        "google/gemini-3-flash-preview",
        "tencent/hy3-preview"
    ]

    public static let regionHosts: [String: String] = [
        "us-central1": "api.quillrouter.com",
        "europe-west4": "api-europe-west4.quillrouter.com"
    ]
}

/// Look up the canonical base URL for a TrustedRouter region. Throws
/// `internalError` if `region` isn't in the published `regionHosts` table.
public func regionBaseUrl(region: String) throws -> String {
    guard let host = TrustedRouterConstants.regionHosts[region] else {
        let known = TrustedRouterConstants.regionHosts.keys.sorted().joined(separator: ", ")
        throw TrustedRouterError.internalError("unknown TrustedRouter region '\(region)'; known: \(known)")
    }
    return "https://\(host)/v1"
}

/// Every error the SDK surfaces. Each HTTP-status case carries the original
/// status code, the server's message (parsed from `error.message` or
/// `message` if present, otherwise the raw body), and the decoded payload
/// for callers that need to inspect provider-specific fields.
public enum TrustedRouterError: Error, LocalizedError, CustomStringConvertible {
    case badRequest(statusCode: Int, message: String, payload: [String: Any]?)
    case authentication(statusCode: Int, message: String, payload: [String: Any]?)
    case permissionDenied(statusCode: Int, message: String, payload: [String: Any]?)
    case notFound(statusCode: Int, message: String, payload: [String: Any]?)
    case endpointNotSupported(statusCode: Int, message: String, payload: [String: Any]?)
    case rateLimit(statusCode: Int, message: String, payload: [String: Any]?, retryAfterSeconds: Double?)
    case internalError(String)
    case generic(statusCode: Int, message: String, payload: [String: Any]?)
    case invalidResponse(String)

    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case let .badRequest(statusCode, message, _),
             let .authentication(statusCode, message, _),
             let .permissionDenied(statusCode, message, _),
             let .notFound(statusCode, message, _),
             let .endpointNotSupported(statusCode, message, _),
             let .generic(statusCode, message, _):
            return "[\(statusCode)] \(message)"
        case let .rateLimit(statusCode, message, _, retryAfterSeconds):
            if let retryAfterSeconds {
                return "[\(statusCode)] \(message) (retry after \(retryAfterSeconds)s)"
            }
            return "[\(statusCode)] \(message)"
        case .internalError(let message), .invalidResponse(let message):
            return message
        }
    }
}

/// Configuration for a `TrustedRouter` client. Construct with `init(...)`,
/// passing only the fields you want to override.
///
/// Pass either `region` (canonical regional host) or `baseUrl` (explicit
/// override) — not both. `maxRetries` applies to 429 and ≥500 responses.
public struct TrustedRouterOptions {
    public var apiKey: String?
    public var baseUrl: String?
    public var region: String?
    public var urlSession: URLSession
    public var headers: [String: String]
    public var workspaceId: String?
    public var maxRetries: Int

    public init(
        apiKey: String? = nil,
        baseUrl: String? = nil,
        region: String? = nil,
        urlSession: URLSession = .shared,
        headers: [String: String] = [:],
        workspaceId: String? = nil,
        maxRetries: Int = 2
    ) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.region = region
        self.urlSession = urlSession
        self.headers = headers
        self.workspaceId = workspaceId
        self.maxRetries = maxRetries
    }
}

/// Per-call overrides on top of a `TrustedRouter` client's defaults. Useful
/// for one-off API-key override, custom headers, an idempotency key, or a
/// short per-request timeout.
public struct PerCallOptions {
    public var apiKey: String?
    public var extraHeaders: [String: String]?
    public var workspaceId: String?
    public var idempotencyKey: String?
    public var timeout: TimeInterval?

    public init(
        apiKey: String? = nil,
        extraHeaders: [String: String]? = nil,
        workspaceId: String? = nil,
        idempotencyKey: String? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.workspaceId = workspaceId
        self.idempotencyKey = idempotencyKey
        self.timeout = timeout
    }
}

/// Strongly-typed chat message. Use this with the `[ChatMessage]` overloads
/// of `chatCompletions(...)` / `chatCompletionsChunks(...)` when you don't
/// need to pass tool-call fields. For tool-call interop, fall back to the
/// `[[String: Any]]` overload.
public struct ChatMessage: Codable, Sendable {
    public var role: String
    public var content: String?
    public var name: String?
    public var toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCallId = "tool_call_id"
    }

    public init(role: String, content: String? = nil, name: String? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
    }

    /// Convenience constructor for a plain user message.
    public static func user(_ content: String) -> ChatMessage {
        .init(role: "user", content: content)
    }
    /// Convenience constructor for a plain assistant message.
    public static func assistant(_ content: String) -> ChatMessage {
        .init(role: "assistant", content: content)
    }
    /// Convenience constructor for the system prompt.
    public static func system(_ content: String) -> ChatMessage {
        .init(role: "system", content: content)
    }
    /// Convenience constructor for a tool-result message (Chat Completions style).
    public static func tool(callId: String, content: String) -> ChatMessage {
        .init(role: "tool", content: content, toolCallId: callId)
    }
}
