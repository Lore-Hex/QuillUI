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

/// Conversation/thread shape for chat models that own their messages.
///
/// Apps can conform their domain model directly, then use the higher-level
/// `ChatDraft.sendMessage` overload without exposing a writable key path at
/// every call site. The lower-level key-path overload remains available for
/// models whose message storage is nested or named differently.
public protocol ChatThread: ChatListItem {
    associatedtype Message: ChatMessage

    var messages: [Message] { get set }
}

/// Backend-neutral initial selection policy for chat-style apps.
///
/// Linux smoke tests can set a deterministic row before the first frame is
/// painted, while native SwiftUI hosts can pass their own environment map or
/// ignore this helper entirely. The logic deliberately lives below the app
/// models and above the view shell so Signal, Telegram, and future chat apps
/// do not each grow their own string parsing and bounds checks.
public enum ChatInitialSelection {
    public static let sharedEnvironmentKey = "QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START"

    public static func index(
        environmentKeys: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int? {
        for key in environmentKeys {
            guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty,
                  let index = Int(rawValue)
            else { continue }
            return index
        }
        return nil
    }

    public static func selectedID<Item: ChatListItem>(
        in items: [Item],
        environmentKeys: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Item.ID? {
        guard !items.isEmpty,
              let requestedIndex = index(environmentKeys: environmentKeys, environment: environment)
        else { return nil }

        let clampedIndex = min(max(requestedIndex, 0), items.count - 1)
        return items[clampedIndex].id
    }
}

/// Public styling tokens for the shared chat views.
///
/// Defaults match the original Signal/Telegram Linux shell chrome.
/// iOS or app-specific clients can pass a custom value through
/// `ChatBubble`, `ChatRow`, `ChatSidebar`, `ChatTimeline`,
/// `ChatComposer`, or `ChatPane` without forking the view
/// implementations.
public enum ChatInteractionProfile: String, CaseIterable, Sendable {
    /// Desktop-style density used by the Linux and macOS chat shells.
    case desktop

    /// Larger touch targets for iPhone, iPad, and other touch-first hosts.
    case touch

    /// Native SwiftUI clients can use this when they want the chat chrome to
    /// follow the host platform density without importing UIKit or AppKit.
    public static var platformDefault: ChatInteractionProfile {
        #if os(iOS) || os(tvOS) || os(visionOS)
        .touch
        #else
        .desktop
        #endif
    }
}

public struct ChatAppearance {
    public var outgoingBubbleBackground: Color
    public var incomingBubbleBackground: Color
    public var unreadBadgeBackground: Color
    public var unreadBadgeForeground: Color
    public var composerBackground: Color
    public var selectedRowBackground: Color
    public var bubbleCornerRadius: CGFloat
    public var unreadBadgeCornerRadius: CGFloat
    public var selectedRowCornerRadius: CGFloat
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
        selectedRowBackground: Color = Color(red: 0.88, green: 0.94, blue: 1.0),
        bubbleCornerRadius: CGFloat = 12,
        unreadBadgeCornerRadius: CGFloat = 8,
        selectedRowCornerRadius: CGFloat = 8,
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
        self.selectedRowBackground = selectedRowBackground
        self.bubbleCornerRadius = bubbleCornerRadius
        self.unreadBadgeCornerRadius = unreadBadgeCornerRadius
        self.selectedRowCornerRadius = selectedRowCornerRadius
        self.bubblePadding = bubblePadding
        self.rowVerticalPadding = rowVerticalPadding
        self.timelinePadding = timelinePadding
        self.messageSpacing = messageSpacing
        self.composerPadding = composerPadding
    }

    public static func standard(for profile: ChatInteractionProfile) -> ChatAppearance {
        switch profile {
        case .desktop:
            return desktop
        case .touch:
            return touch
        }
    }

    public static var standard: ChatAppearance {
        desktop
    }

    public static var platformDefault: ChatAppearance {
        standard(for: ChatInteractionProfile.platformDefault)
    }

    public static var desktop: ChatAppearance {
        ChatAppearance()
    }

    public static var touch: ChatAppearance {
        ChatAppearance(
            bubbleCornerRadius: 16,
            unreadBadgeCornerRadius: 10,
            bubblePadding: 14,
            rowVerticalPadding: 8,
            timelinePadding: 20,
            messageSpacing: 12,
            composerPadding: 14
        )
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
    public let selected: Bool
    public let appearance: ChatAppearance

    public init(
        title: String,
        preview: String,
        unread: Int = 0,
        selected: Bool = false,
        appearance: ChatAppearance = .standard
    ) {
        self.title = title
        self.preview = preview
        self.unread = unread
        self.selected = selected
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? appearance.selectedRowBackground : Color.clear)
            .cornerRadius(appearance.selectedRowCornerRadius)
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
    public let selectedID: Item.ID?
    public let appearance: ChatAppearance
    public let onSelect: (Item) -> Void

    public init(
        items: [Item],
        selectedID: Item.ID? = nil,
        appearance: ChatAppearance = .standard,
        onSelect: @escaping (Item) -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
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
                            selected: item.id == selectedID,
                            appearance: appearance
                        )
                    }
                }
            }
        }
    }
}

/// Standard sidebar chrome for chat-style apps: a title, optional
/// app-owned accessory controls, then the shared `ChatSidebarList`.
///
/// Signal uses the empty-accessory initializer while Telegram passes
/// folder pills as the accessory. Keeping that shell here means those
/// apps share the same sidebar spacing and typography on GTK, Qt, and
/// native SwiftUI hosts without making `QuillChatKit` depend on
/// `QuillUI`.
@MainActor
public struct ChatSidebar<Item: ChatListItem, Accessory: View>: View {
    public let title: String
    public let items: [Item]
    public let selectedID: Item.ID?
    public let appearance: ChatAppearance
    public let accessory: Accessory
    public let onSelect: (Item) -> Void

    public init(
        title: String,
        items: [Item],
        selectedID: Item.ID? = nil,
        appearance: ChatAppearance = .standard,
        @ViewBuilder accessory: () -> Accessory,
        onSelect: @escaping (Item) -> Void
    ) {
        self.title = title
        self.items = items
        self.selectedID = selectedID
        self.appearance = appearance
        self.accessory = accessory()
        self.onSelect = onSelect
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.title2).bold()
                    .padding(14)

                accessory

                ChatSidebarList(
                    items: items,
                    selectedID: selectedID,
                    appearance: appearance,
                    onSelect: onSelect
                )
            }
        }
    }
}

public extension ChatSidebar where Accessory == EmptyView {
    init(
        title: String,
        items: [Item],
        selectedID: Item.ID? = nil,
        appearance: ChatAppearance = .standard,
        onSelect: @escaping (Item) -> Void
    ) {
        self.init(
            title: title,
            items: items,
            selectedID: selectedID,
            appearance: appearance,
            accessory: { EmptyView() },
            onSelect: onSelect
        )
    }
}

/// Shared placeholder for a detail pane with no selected chat.
///
/// Apps provide the concrete copy ("Select a conversation",
/// "Select a chat", etc.) while the empty-state layout stays aligned
/// across chat targets.
@MainActor
public struct ChatSelectionPlaceholder: View {
    public let title: String

    public init(_ title: String) {
        self.title = title
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            Text(title)
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Convenience overload for conversation models that conform to
    /// `ChatThread`. This keeps app send paths generic and backend-agnostic
    /// while still delegating the mutation rules to the canonical key-path
    /// implementation above.
    @discardableResult
    public static func sendMessage<Thread: ChatThread>(
        from draft: inout String,
        toID id: Thread.ID?,
        in threads: inout [Thread],
        makeMessage: (String) -> Thread.Message
    ) -> Bool {
        sendMessage(
            from: &draft,
            toID: id,
            in: &threads,
            messagesAt: \.messages,
            makeMessage: makeMessage
        )
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

    public init<Thread: ChatThread>(
        thread: Thread,
        appearance: ChatAppearance = .standard
    ) where Thread.Message == M {
        self.init(
            title: thread.title,
            messages: thread.messages,
            appearance: appearance
        )
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

    public init<Thread: ChatThread>(
        thread: Thread,
        draft: Binding<String>,
        placeholder: String = "Message",
        sendTitle: String = "Send",
        appearance: ChatAppearance = .standard,
        onSend: @escaping () -> Void
    ) where Thread.Message == M {
        self.init(
            title: thread.title,
            messages: thread.messages,
            draft: draft,
            placeholder: placeholder,
            sendTitle: sendTitle,
            appearance: appearance,
            onSend: onSend
        )
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

/// Full split-view chat shell shared by conversation-style apps.
///
/// `ChatSidebar`, `ChatPane`, and `ChatSelectionPlaceholder` remain available
/// as primitives. Apps that follow the common "conversation list -> selected
/// conversation detail" flow can use this shell so selection, placeholder, and
/// pane routing stay identical across Signal, Telegram, GTK, Qt, and native
/// SwiftUI hosts.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
@MainActor
public struct ChatSplitShell<Thread: ChatThread, SidebarAccessory: View>: View where Thread.ID: Equatable {
    public let title: String
    public let threads: [Thread]
    @Binding public var selectedID: Thread.ID?
    @Binding public var draft: String
    public let placeholder: String
    public let composerPlaceholder: String
    public let sendTitle: String
    public let appearance: ChatAppearance
    public let sidebarAccessory: SidebarAccessory
    public let onSend: () -> Void

    public init(
        title: String,
        threads: [Thread],
        selectedID: Binding<Thread.ID?>,
        draft: Binding<String>,
        placeholder: String,
        composerPlaceholder: String = "Message",
        sendTitle: String = "Send",
        appearance: ChatAppearance = .standard,
        @ViewBuilder sidebarAccessory: () -> SidebarAccessory,
        onSend: @escaping () -> Void
    ) {
        self.title = title
        self.threads = threads
        self._selectedID = selectedID
        self._draft = draft
        self.placeholder = placeholder
        self.composerPlaceholder = composerPlaceholder
        self.sendTitle = sendTitle
        self.appearance = appearance
        self.sidebarAccessory = sidebarAccessory()
        self.onSend = onSend
    }

    private var selectedThread: Thread? {
        guard let selectedID else { return nil }
        return threads.first { $0.id == selectedID }
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            NavigationSplitView {
                ChatSidebar(title: title, items: threads, selectedID: selectedID, appearance: appearance) {
                    sidebarAccessory
                } onSelect: { thread in
                    selectedID = thread.id
                }
            } detail: {
                Group {
                    if let thread = selectedThread {
                        ChatPane(
                            thread: thread,
                            draft: $draft,
                            placeholder: composerPlaceholder,
                            sendTitle: sendTitle,
                            appearance: appearance,
                            onSend: onSend
                        )
                    } else {
                        ChatSelectionPlaceholder(placeholder)
                    }
                }
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public extension ChatSplitShell where SidebarAccessory == EmptyView {
    init(
        title: String,
        threads: [Thread],
        selectedID: Binding<Thread.ID?>,
        draft: Binding<String>,
        placeholder: String,
        composerPlaceholder: String = "Message",
        sendTitle: String = "Send",
        appearance: ChatAppearance = .standard,
        onSend: @escaping () -> Void
    ) {
        self.init(
            title: title,
            threads: threads,
            selectedID: selectedID,
            draft: draft,
            placeholder: placeholder,
            composerPlaceholder: composerPlaceholder,
            sendTitle: sendTitle,
            appearance: appearance,
            sidebarAccessory: { EmptyView() },
            onSend: onSend
        )
    }
}
