import Foundation
import SwiftUI

private struct ChatUncheckedSendableView<Content: View>: @unchecked Sendable {
    let content: Content
}

private enum ChatMainActorView {
    static func assumeIsolated<Content: View>(_ content: @MainActor () -> Content) -> Content {
        MainActor.assumeIsolated {
            ChatUncheckedSendableView(content: content())
        }.content
    }
}

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

/// Summary shape for rows in a chat/conversation sidebar.
///
/// Apps keep their own conversation model while exposing only the
/// title, preview, and optional unread count needed by the shared row
/// chrome. This keeps Signal/Telegram-style sidebars visually
/// identical without forcing a shared storage model.
public protocol ChatListItem: Identifiable, Hashable, Sendable {
    var title: String { get }
    var preview: String { get }
    var unreadCount: Int { get }
}

public extension ChatListItem {
    var unreadCount: Int { 0 }
}

/// Public styling tokens for the shared chat views.
///
/// Defaults match the original Signal/Telegram Linux shell chrome.
/// iOS or app-specific clients can pass a custom value through
/// `ChatBubble`, `ChatRow`, `ChatTimeline`, `ChatComposer`, or
/// `ChatPane` without forking the view implementations.
public struct ChatAppearance {
    public var outgoingBubbleBackground: Color
    public var incomingBubbleBackground: Color
    public var unreadBadgeBackground: Color
    public var unreadBadgeForeground: Color
    public var composerBackground: Color
    public var bubbleCornerRadius: CGFloat
    public var unreadBadgeCornerRadius: CGFloat
    public var bubblePadding: CGFloat
    public var rowVerticalPadding: CGFloat
    public var timelinePadding: CGFloat
    public var messageSpacing: CGFloat
    public var composerPadding: CGFloat

    public init(
        outgoingBubbleBackground: Color = Color.blue.opacity(0.18),
        incomingBubbleBackground: Color = Color.gray.opacity(0.18),
        unreadBadgeBackground: Color = .blue,
        unreadBadgeForeground: Color = .white,
        composerBackground: Color = Color.gray.opacity(0.06),
        bubbleCornerRadius: CGFloat = 12,
        unreadBadgeCornerRadius: CGFloat = 8,
        bubblePadding: CGFloat = 10,
        rowVerticalPadding: CGFloat = 4,
        timelinePadding: CGFloat = 16,
        messageSpacing: CGFloat = 10,
        composerPadding: CGFloat = 10
    ) {
        self.outgoingBubbleBackground = outgoingBubbleBackground
        self.incomingBubbleBackground = incomingBubbleBackground
        self.unreadBadgeBackground = unreadBadgeBackground
        self.unreadBadgeForeground = unreadBadgeForeground
        self.composerBackground = composerBackground
        self.bubbleCornerRadius = bubbleCornerRadius
        self.unreadBadgeCornerRadius = unreadBadgeCornerRadius
        self.bubblePadding = bubblePadding
        self.rowVerticalPadding = rowVerticalPadding
        self.timelinePadding = timelinePadding
        self.messageSpacing = messageSpacing
        self.composerPadding = composerPadding
    }

    public static var standard: ChatAppearance {
        ChatAppearance()
    }
}

#if os(Linux)
private typealias ChatLayoutLength = Int
#else
private typealias ChatLayoutLength = CGFloat
#endif

private extension ChatAppearance {
    var chatBubblePadding: ChatLayoutLength { ChatLayoutLength(bubblePadding) }
    var chatRowVerticalPadding: ChatLayoutLength { ChatLayoutLength(rowVerticalPadding) }
    var chatTimelinePadding: ChatLayoutLength { ChatLayoutLength(timelinePadding) }
    var chatMessageSpacing: ChatLayoutLength { ChatLayoutLength(messageSpacing) }
    var chatComposerPadding: ChatLayoutLength { ChatLayoutLength(composerPadding) }
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
    public let appearance: ChatAppearance

    public init(_ message: M, appearance: ChatAppearance = .standard) {
        self.message = message
        self.appearance = appearance
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            VStack(alignment: message.fromSelf ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .padding(appearance.chatBubblePadding)
                    .background(
                        message.fromSelf
                            ? appearance.outgoingBubbleBackground
                            : appearance.incomingBubbleBackground
                    )
                    .cornerRadius(appearance.bubbleCornerRadius)
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
    public let appearance: ChatAppearance

    public init(
        title: String,
        preview: String,
        unread: Int = 0,
        appearance: ChatAppearance = .standard
    ) {
        self.title = title
        self.preview = preview
        self.unread = unread
        self.appearance = appearance
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.headline).lineLimit(1)
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appearance.unreadBadgeBackground)
                            .foregroundColor(appearance.unreadBadgeForeground)
                            .cornerRadius(appearance.unreadBadgeCornerRadius)
                    }
                }
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, appearance.chatRowVerticalPadding)
        }
    }
}

/// A reusable sidebar list for chat/conversation summaries.
///
/// Signal and Telegram both render a `List` of buttons wrapping
/// `ChatRow`. Centralizing that pattern keeps the sidebar interaction
/// and row chrome aligned while each app decides what selecting a row
/// means for its own state.
@MainActor
public struct ChatSidebarList<Item: ChatListItem>: View {
    public let items: [Item]
    public let appearance: ChatAppearance
    public let onSelect: (Item) -> Void

    public init(
        items: [Item],
        appearance: ChatAppearance = .standard,
        onSelect: @escaping (Item) -> Void
    ) {
        self.items = items
        self.appearance = appearance
        self.onSelect = onSelect
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            List {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        ChatRow(
                            title: item.title,
                            preview: item.preview,
                            unread: item.unreadCount,
                            appearance: appearance
                        )
                    }
                }
            }
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
    public let sendTitle: String
    public let appearance: ChatAppearance
    @Binding public var draft: String
    public let onSend: () -> Void

    public init(
        placeholder: String = "Message",
        sendTitle: String = "Send",
        appearance: ChatAppearance = .standard,
        draft: Binding<String>,
        onSend: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        self.sendTitle = sendTitle
        self.appearance = appearance
        self._draft = draft
        self.onSend = onSend
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                Button(sendTitle) {
                    onSend()
                }
                .disabled(!ChatDraft.isSendable(draft))
            }
            .padding(appearance.chatComposerPadding)
            .background(appearance.composerBackground)
        }
    }
}

/// A header + scrolling stack of `ChatBubble`s. Used by Signal,
/// Telegram, and any other app rendering a conversation timeline.
@MainActor
public struct ChatTimeline<M: ChatMessage>: View {
    public let title: String
    public let messages: [M]
    public let appearance: ChatAppearance

    public init(title: String, messages: [M], appearance: ChatAppearance = .standard) {
        self.title = title
        self.messages = messages
        self.appearance = appearance
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            VStack(spacing: 0) {
                Text(title)
                    .font(.title2).bold()
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: appearance.chatMessageSpacing) {
                        ForEach(messages) { message in
                            ChatBubble(message, appearance: appearance)
                        }
                    }
                    .padding(appearance.chatTimelinePadding)
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
    public let sendTitle: String
    public let appearance: ChatAppearance
    @Binding public var draft: String
    public let onSend: () -> Void

    public init(
        title: String,
        messages: [M],
        draft: Binding<String>,
        placeholder: String = "Message",
        sendTitle: String = "Send",
        appearance: ChatAppearance = .standard,
        onSend: @escaping () -> Void
    ) {
        self.title = title
        self.messages = messages
        self._draft = draft
        self.placeholder = placeholder
        self.sendTitle = sendTitle
        self.appearance = appearance
        self.onSend = onSend
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            VStack(spacing: 0) {
                ChatTimeline(title: title, messages: messages, appearance: appearance)
                Divider()
                ChatComposer(
                    placeholder: placeholder,
                    sendTitle: sendTitle,
                    appearance: appearance,
                    draft: $draft,
                    onSend: onSend
                )
            }
        }
    }
}
