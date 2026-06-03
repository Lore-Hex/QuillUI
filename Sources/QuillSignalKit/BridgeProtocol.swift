//
// QuillSignalKit — the quill-signal-bridge wire-protocol response types.
//
// A single public source of truth for the per-command JSON the Rust bridge
// emits, so the app (QuillSignalCore) and the decode-contract check
// (QuillSignalDecodeCheck) decode the exact same shapes. The streaming event
// lines (ping/status/link-*) use `BridgeMessage`; these are the list/whoami
// response envelopes.
//
import Foundation

// MARK: - list-conversations

/// One conversation (contact) entry from `list-conversations`.
public struct BridgeConversation: Codable, Sendable {
    public let type: String?
    public let uuid: String?
    public let name: String?
}

/// `{"conversations":[...]}` — the `data` payload of a list-conversations reply.
public struct ConversationsData: Codable, Sendable {
    public let conversations: [BridgeConversation]
}

/// A full list-conversations response line.
public struct ConversationsResponse: Codable, Sendable {
    public let data: ConversationsData?
}

// MARK: - list-messages

/// One stored message from `list-messages`. `fromSelf` (wire key `from_self`)
/// marks the account's own outgoing messages so the UI can attribute them.
public struct BridgeStoredMessage: Codable, Sendable {
    public let body: String?
    public let timestamp: UInt64?
    public let sender: String?
    public let fromSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case body, timestamp, sender
        case fromSelf = "from_self"
    }
}

/// `{"messages":[...]}` — the `data` payload of a list-messages reply.
public struct MessagesData: Codable, Sendable {
    public let messages: [BridgeStoredMessage]
}

/// A full list-messages response line.
public struct MessagesResponse: Codable, Sendable {
    public let data: MessagesData?
}

// MARK: - receive stream

/// One pushed message line from the `receive` stream:
/// `{"event":"message","thread":…,"sender":…,"body":…,"timestamp":…,"from_self":…}`.
public struct IncomingMessage: Codable, Sendable {
    public let event: String?
    public let thread: String?
    public let sender: String?
    public let body: String?
    public let timestamp: UInt64?
    public let fromSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case event, thread, sender, body, timestamp
        case fromSelf = "from_self"
    }
}

// MARK: - whoami

/// The linked-account identity payload from `whoami`.
public struct WhoamiData: Codable, Sendable {
    public let registered: Bool?
    public let number: String?
}

/// A full whoami response line.
public struct WhoamiResponse: Codable, Sendable {
    public let data: WhoamiData?
}
