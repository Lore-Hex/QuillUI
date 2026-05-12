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

    /// When the message was sent. Optional — the bubble omits
    /// the timestamp caption entirely when nil so existing
    /// conformances stay valid without supplying a date.
    var timestamp: Date? { get }
}

public extension ChatMessage {
    /// Default: messages have no timestamp. Apps that want them
    /// (Signal / Telegram) override this on their concrete type.
    var timestamp: Date? { nil }
}

/// Cached time-only formatter used by `ChatBubble`. Static so the
/// `ChatBubble` body doesn't allocate a new formatter every paint.
@MainActor
public enum ChatTimestampFormatter {
    public static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    public static func formatted(_ timestamp: Date) -> String {
        shortTime.string(from: timestamp)
    }
}

/// One message bubble. Self-messages right-align with a blue tint,
/// peer messages left-align with a neutral tint.
@MainActor
public struct ChatBubble<M: ChatMessage>: View {
    public let message: M

    public init(_ message: M) {
        self.message = message
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            VStack(alignment: message.fromSelf ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .padding(10)
                    .background(
                        message.fromSelf
                            ? Color.blue.opacity(0.18)
                            : Color.gray.opacity(0.18)
                    )
                    .cornerRadius(12)
                HStack(spacing: 6) {
                    Text(message.sender)
                    if let timestamp = message.timestamp {
                        Text(ChatTimestampFormatter.formatted(timestamp))
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: message.fromSelf ? .trailing : .leading
            )
        }
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

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
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
}

/// Predicate for whether a draft string would actually produce a
/// sendable message. Trims whitespace + newlines and requires the
/// remainder to be non-empty. Hosts use this to drive the Send
/// button's `.disabled` state and to short-circuit empty submits.
public enum ChatDraft {
    public static func isSendable(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func trimmed(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Take" the draft if it is sendable: returns the trimmed
    /// body and clears the source string. Returns `nil` if the
    /// draft is empty / whitespace-only (in which case the
    /// source is left untouched). Hosts use this to fold the
    /// `isSendable → trim → reset` cycle into a single
    /// `guard let body = ChatDraft.consume(&draft) else { return }`.
    public static func consume(_ draft: inout String) -> String? {
        guard isSendable(draft) else { return nil }
        let body = trimmed(draft)
        draft = ""
        return body
    }

    /// Canonical "send a chat message" path. Validates the
    /// target item exists, the draft is sendable, then appends
    /// `makeMessage(trimmedBody)` to the `[M]` stored at
    /// `messagesAt` and clears the draft. Returns `true` if a
    /// message was actually appended.
    ///
    /// Order matters: the id + lookup checks run BEFORE the
    /// draft is cleared, so a "no conversation selected" tap on
    /// Send leaves what the user has typed intact. Validating
    /// after `consume` would silently eat their draft.
    ///
    /// Signal and Telegram's `send()` shrink to a single call
    /// against this helper — they only differ by which @State
    /// collection holds the conversations and which ChatMessage
    /// type the make-closure returns.
    @discardableResult
    public static func sendMessage<Item: Identifiable, M: ChatMessage>(
        from draft: inout String,
        toID id: Item.ID?,
        in items: inout [Item],
        messagesAt keyPath: WritableKeyPath<Item, [M]>,
        makeMessage: (String) -> M
    ) -> Bool {
        guard let id = id,
              let idx = items.firstIndex(where: { $0.id == id }),
              isSendable(draft)
        else { return false }
        items[idx][keyPath: keyPath].append(makeMessage(trimmed(draft)))
        draft = ""
        return true
    }
}

/// A composer row: text field bound to a draft string + Send
/// button that fires `onSend`. The composer itself does NOT
/// append messages or mutate any model — hosts own that step so
/// they can decide which conversation receives the message and
/// how to render the resulting state.
@MainActor
public struct ChatComposer: View {
    public let placeholder: String
    @Binding public var draft: String
    public let onSend: () -> Void

    public init(
        placeholder: String = "Message",
        draft: Binding<String>,
        onSend: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        self._draft = draft
        self.onSend = onSend
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                Button("Send") {
                    onSend()
                }
                .disabled(!ChatDraft.isSendable(draft))
            }
            .padding(10)
            .background(Color.gray.opacity(0.06))
        }
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

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
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
}

/// `ChatTimeline` stacked over a `ChatComposer` with a `Divider`
/// between them. The standard chat-app detail-pane idiom — what
/// Signal, Telegram, and similar apps render once the user has
/// picked a conversation. Hosts forward the draft binding and
/// the send closure; everything else is layout.
@MainActor
public struct ChatPane<M: ChatMessage>: View {
    public let title: String
    public let messages: [M]
    public let placeholder: String
    @Binding public var draft: String
    public let onSend: () -> Void

    public init(
        title: String,
        messages: [M],
        draft: Binding<String>,
        placeholder: String = "Message",
        onSend: @escaping () -> Void
    ) {
        self.title = title
        self.messages = messages
        self._draft = draft
        self.placeholder = placeholder
        self.onSend = onSend
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            VStack(spacing: 0) {
                ChatTimeline(title: title, messages: messages)
                Divider()
                ChatComposer(placeholder: placeholder, draft: $draft, onSend: onSend)
            }
        }
    }
}
