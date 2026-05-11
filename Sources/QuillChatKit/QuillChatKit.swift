import Foundation
import QuillUI

/// Shared chat primitives used by QuillSignal, QuillTelegram, and
/// any other QuillUI app that renders a "sidebar of conversations →
/// timeline of bubbles" shape.
///
/// The three apps previously copy-pasted nearly identical bubble,
/// sidebar-row, and timeline views differing only by message
/// shape. This kit conforms message types to `ChatMessage` and
/// renders them through generic views, so each app keeps its own
/// domain model (Signal's `Message`, Telegram's `TGMessage`, …)
/// while sharing pixels.

public protocol ChatMessage: Identifiable, Hashable, Sendable {
    var sender: String { get }
    var body: String { get }
    var fromSelf: Bool { get }
}

/// One message bubble. Self-messages right-align with a blue tint,
/// peer messages left-align with a neutral tint.
@MainActor
public struct ChatBubble<M: ChatMessage>: View {
    public let message: M

    public init(_ message: M) {
        self.message = message
    }

    public var body: some View {
        VStack(alignment: message.fromSelf ? .trailing : .leading, spacing: 2) {
            Text(message.body)
                .padding(10)
                .background(
                    message.fromSelf
                        ? Color.blue.opacity(0.18)
                        : Color.gray.opacity(0.18)
                )
                .cornerRadius(12)
            Text(message.sender)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.fromSelf ? .trailing : .leading
        )
    }
}

/// A sidebar row showing a conversation title, last-message preview,
/// and an optional unread-count badge. Signal omits the badge,
/// Telegram surfaces it — both routes share the same row chrome.
@MainActor
public struct ChatRow: View {
    public let title: String
    public let preview: String
    public let unread: Int

    public init(title: String, preview: String, unread: Int = 0) {
        self.title = title
        self.preview = preview
        self.unread = unread
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.headline).lineLimit(1)
                Spacer()
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            Text(preview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

/// A header + scrolling stack of `ChatBubble`s. Used by Signal,
/// Telegram, and any other app rendering a conversation timeline.
@MainActor
public struct ChatTimeline<M: ChatMessage>: View {
    public let title: String
    public let messages: [M]

    public init(title: String, messages: [M]) {
        self.title = title
        self.messages = messages
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title2).bold()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        ChatBubble(message)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
