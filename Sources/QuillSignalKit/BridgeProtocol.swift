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
    /// Local file path of a downloaded inline image attachment, or nil for a
    /// text-only message. The bridge downloads + downscales received images and
    /// reports the cached PNG path here. Optional, so older payloads still decode.
    public let attachmentPath: String?
    /// Coarse attachment kind ("image"/"video"/"audio"/"file") so the UI can show
    /// a typed chip for non-image attachments, or nil when there's no attachment.
    /// Optional, so older payloads still decode.
    public let attachmentKind: String?

    enum CodingKeys: String, CodingKey {
        case body, timestamp, sender
        case fromSelf = "from_self"
        case attachmentPath = "attachment_path"
        case attachmentKind = "attachment_kind"
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
    public let senderName: String?
    public let body: String?
    /// Detail for a non-message event (e.g. a `receive-error`).
    public let msg: String?
    public let timestamp: UInt64?
    public let fromSelf: Bool?
    /// Coarse attachment kind for a typed chip ("image"/"video"/"audio"/"file"),
    /// or nil. Mirrors the list-messages field.
    public let attachmentKind: String?

    enum CodingKeys: String, CodingKey {
        case event, thread, sender, body, msg, timestamp
        case senderName = "sender_name"
        case fromSelf = "from_self"
        case attachmentKind = "attachment_kind"
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

// MARK: - attachment marker

/// Detects the bridge's `[attachment: …]` marker, which `display_body` folds into
/// a message body for any message carrying an attachment. The receive stream
/// can't download attachments inline (it holds the manager mutably), so when a
/// pushed message contains this marker the app re-pulls the thread via
/// `list-messages` — which downloads the image and backfills it into the bubble.
public enum AttachmentMarker {
    /// The literal prefix the bridge emits (see the bridge's `display_body`).
    public static let prefix = "[attachment:"

    /// True when `body` contains the attachment marker. Nil / plain text → false.
    public static func isPresent(in body: String?) -> Bool {
        body?.contains(prefix) ?? false
    }
}
