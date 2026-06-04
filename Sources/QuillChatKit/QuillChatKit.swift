import Foundation
import QuillFoundation
import SwiftUI
#if !os(Linux)
import AppKit
#endif

/// An `Image` from a local file path, cross-platform. SwiftOpenUI (Linux/GTK)
/// exposes `Image(filePath:)`; real SwiftUI on macOS has no such initializer, so
/// load the file through `NSImage` there. Used by `ChatBubble` for inline
/// attachment thumbnails (the bridge downscales them first).
public func chatFileImage(_ path: String) -> Image {
    #if os(Linux)
    return Image(filePath: path)
    #else
    if let nsImage = NSImage(contentsOfFile: path) {
        return Image(nsImage: nsImage)
    }
    return Image(systemName: "photo")
    #endif
}

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

    /// Local file path of an image attachment to show in the bubble, or
    /// nil for a text-only message. Optional — defaulted to nil so
    /// existing conformances stay valid without supplying it.
    var attachmentImagePath: String? { get }

    /// Coarse kind ("video"/"audio"/"file") of a non-image attachment, so the
    /// bubble can show a typed glyph chip. Optional — defaulted to nil.
    var attachmentKind: String? { get }
}

public extension ChatMessage {
    /// Default: messages have no timestamp. Apps that want them
    /// (Signal / Telegram) override this on their concrete type.
    var timestamp: Date? { nil }

    /// Default: no image attachment.
    var attachmentImagePath: String? { nil }

    /// Default: no attachment kind.
    var attachmentKind: String? { nil }
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
    /// Timestamp of the conversation's last activity, shown as a relative stamp
    /// at the row's trailing edge. Optional — defaulted nil so existing
    /// conformances (e.g. Telegram's) stay valid and simply show no time.
    var lastActivity: Date? { get }
}

public extension ChatListItem {
    var unreadCount: Int { 0 }
    var lastActivity: Date? { nil }
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
        QuillInitialSelection.index(environmentKeys: environmentKeys, environment: environment)
    }

    public static func selectedID<Item: ChatListItem>(
        in items: [Item],
        environmentKeys: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Item.ID? {
        QuillInitialSelection.selectedID(in: items, environmentKeys: environmentKeys, environment: environment)
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

/// Cached formatters + relative-stamp logic used by `ChatBubble`. Static so the
/// `ChatBubble` body doesn't allocate a formatter every paint.
@MainActor
public enum ChatTimestampFormatter {
    public static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Abbreviated weekday ("Mon") for messages within the past week.
    public static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Month + day ("Jun 4") for older messages.
    public static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// The time-of-day for a message ("9:18 AM"). Kept for callers that always
    /// want an absolute stamp regardless of age.
    public static func formatted(_ timestamp: Date) -> String {
        shortTime.string(from: timestamp)
    }

    /// A compact, chat-style relative stamp that sharpens as a message ages:
    /// "Just now" (<1m) → "5m" (<1h) → time-of-day earlier today ("9:18 AM") →
    /// "Yesterday" → an abbreviated weekday within the past week ("Mon") →
    /// a short date ("Jun 4"). `now` is injectable so the choice is testable.
    public static func relative(_ timestamp: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        let cal = Calendar.current
        if cal.isDate(timestamp, inSameDayAs: now) {
            return shortTime.string(from: timestamp)
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(timestamp, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if interval < 7 * 24 * 3600 {
            return weekday.string(from: timestamp)
        }
        return shortDate.string(from: timestamp)
    }

    /// Full weekday name ("Monday") for a day-divider within the past week.
    public static let fullWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// Month + day + year ("Jun 4, 2026") for an older day-divider.
    public static let separatorDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// A day-divider label for a message group: "Today" / "Yesterday" / a full
    /// weekday within the past week ("Monday") / else "MMM d, yyyy". `now` is
    /// injectable so the choice is testable.
    public static func daySeparator(_ timestamp: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(timestamp, inSameDayAs: now) { return "Today" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(timestamp, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if now.timeIntervalSince(timestamp) < 7 * 24 * 3600 {
            return fullWeekday.string(from: timestamp)
        }
        return separatorDate.string(from: timestamp)
    }

    /// Whether a day-divider should precede a message, given the previous
    /// message's timestamp: true for the first message (`prev` nil) or when
    /// `prev` and `current` fall on different calendar days; false when the
    /// current message has no timestamp. `calendar` is injectable for testing.
    public static func needsDaySeparator(prev: Date?, current: Date?, calendar: Calendar = .current) -> Bool {
        guard let current else { return false }
        guard let prev else { return true }
        return !calendar.isDate(prev, inSameDayAs: current)
    }

    /// Split a message list into render rows, inserting a day-divider before the
    /// first message and whenever the calendar day changes. Pure aside from the
    /// label formatting; `now` is injectable for testing.
    public static func timelineRows<M: ChatMessage>(_ messages: [M], now: Date = Date()) -> [ChatTimelineRow<M>] {
        var rows: [ChatTimelineRow<M>] = []
        var prev: Date? = nil
        for message in messages {
            if needsDaySeparator(prev: prev, current: message.timestamp), let ts = message.timestamp {
                rows.append(.separator(id: "\(message.id)", label: daySeparator(ts, now: now)))
            }
            rows.append(.message(message))
            if let ts = message.timestamp { prev = ts }
        }
        return rows
    }
}

/// A transcript render row: a centered day-divider label, or a message bubble.
/// Built by `ChatTimestampFormatter.timelineRows` so the timeline can show
/// Today/Yesterday/weekday/date dividers between calendar days.
public enum ChatTimelineRow<M: ChatMessage>: Identifiable {
    case separator(id: String, label: String)
    case message(M)

    public var id: String {
        switch self {
        case .separator(let id, _): return "sep-\(id)"
        case .message(let message): return "msg-\(message.id)"
        }
    }
}

/// Short uppercase tag for a non-image attachment kind ("VIDEO"/"AUDIO"/"FILE"),
/// or nil for an image or absent kind (no chip). ASCII so it renders on any font
/// (the headless GTK test env has no emoji font); `ChatBubble` shows it as a small
/// badge before the attachment text instead of the bare "[attachment: …]" string.
func chatAttachmentTag(_ kind: String?) -> String? {
    switch kind {
    case "video": return "VIDEO"
    case "audio": return "AUDIO"
    case "file": return "FILE"
    default: return nil
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
                if let imagePath = message.attachmentImagePath,
                   FileManager.default.fileExists(atPath: imagePath) {
                    // Natural size (aspect-correct, GTK honors it reliably); the
                    // bridge downscales attachments to a sane thumbnail dimension.
                    chatFileImage(imagePath)
                        .cornerRadius(appearance.bubbleCornerRadius)
                }
                // A non-image attachment (file/video/audio) renders as a glyph
                // chip; everything else (plain text, or an image caption) stays a
                // normal text bubble. Two mutually-exclusive `if`s avoid an
                // if/else in the SwiftOpenUI ViewBuilder.
                if !message.body.isEmpty,
                   message.attachmentImagePath == nil,
                   let tag = chatAttachmentTag(message.attachmentKind) {
                    HStack(spacing: 6) {
                        Text(tag)
                            .font(.caption2).bold()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appearance.unreadBadgeBackground)
                            .foregroundColor(appearance.unreadBadgeForeground)
                            .cornerRadius(appearance.unreadBadgeCornerRadius)
                        Text(message.body)
                    }
                    .padding(appearance.chatBubblePadding)
                    .background(
                        message.fromSelf
                            ? appearance.outgoingBubbleBackground
                            : appearance.incomingBubbleBackground
                    )
                    .cornerRadius(appearance.bubbleCornerRadius)
                }
                if !message.body.isEmpty,
                   message.attachmentImagePath != nil || chatAttachmentTag(message.attachmentKind) == nil {
                    Text(message.body)
                        .padding(appearance.chatBubblePadding)
                        .background(
                            message.fromSelf
                                ? appearance.outgoingBubbleBackground
                                : appearance.incomingBubbleBackground
                        )
                        .cornerRadius(appearance.bubbleCornerRadius)
                }
                HStack(spacing: 6) {
                    Text(message.sender)
                    if let timestamp = message.timestamp {
                        Text(ChatTimestampFormatter.relative(timestamp))
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
    public let lastActivity: Date?
    public let appearance: ChatAppearance

    public init(
        title: String,
        preview: String,
        unread: Int = 0,
        selected: Bool = false,
        lastActivity: Date? = nil,
        appearance: ChatAppearance = .standard
    ) {
        self.title = title
        self.preview = preview
        self.unread = unread
        self.selected = selected
        self.lastActivity = lastActivity
        self.appearance = appearance
    }

    nonisolated public var body: some View {
        ChatMainActorView.assumeIsolated {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.headline).lineLimit(1)
                    Spacer()
                    if let lastActivity {
                        Text(ChatTimestampFormatter.relative(lastActivity))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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
                            lastActivity: item.lastActivity,
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
                        ForEach(ChatTimestampFormatter.timelineRows(messages)) { row in
                            if case let .separator(_, label) = row {
                                Text(label)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(appearance.incomingBubbleBackground)
                                    .cornerRadius(appearance.bubbleCornerRadius)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            if case let .message(message) = row {
                                ChatBubble(message, appearance: appearance)
                            }
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
