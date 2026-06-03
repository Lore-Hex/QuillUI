import Foundation
import QuillUI
import QuillChatKit
import QuillSignalKit

/// Quill Signal — native QuillUI front-end over the real presage/libsignal
/// engine (the `quill-signal-bridge` daemon, reached via QuillSignalKit).
///
/// The view observes `QuillSignalModel`, which talks to the bridge over a unix
/// socket. On launch it queries `status`; if the device isn't linked it shows a
/// device-link panel (driving the bridge's `link-begin`, which returns a real
/// `sgnl://linkdevice` URL the user scans in the Signal app). Once linked it
/// renders the conversation shell (`ChatSplitShell`). Conversation data is still
/// fixture-backed until the bridge grows list-conversations/messages commands;
/// the link + status path is real.

// MARK: - Link state + model

public enum QuillSignalLinkState: Equatable, Sendable {
    case connecting
    case notConnected   // bridge daemon not reachable on the socket
    case unlinked       // bridge reachable, account not registered/linked
    case linked         // registered
}

@MainActor
public final class QuillSignalModel: ObservableObject {
    @Published public var linkState: QuillSignalLinkState = .connecting
    @Published public var statusDetail: String = ""
    @Published public var linkURL: String?
    @Published public var isLinking: Bool = false
    private var isRefreshing = false
    private var hasAutoStarted = false

    private let socketPath: String

    public init(socketPath: String = BridgeClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Diagnostic line to stderr (visible in headless/smoke runs).
    nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data(("[QuillSignal] " + message + "\n").utf8))
    }

    /// Kick off the first status query. Idempotent — `.onAppear` can fire on
    /// every render, and we must not re-query (concurrent presage store opens
    /// race on the sqlite migrations).
    public func startOnce() {
        guard !hasAutoStarted else { return }
        hasAutoStarted = true
        refreshStatus()
    }

    /// Query the bridge `status` command off the main thread, then publish.
    /// Guarded so overlapping calls can't open the presage store concurrently.
    public func refreshStatus() {
        guard !isRefreshing else { return }
        isRefreshing = true
        linkState = .connecting
        statusDetail = "Contacting the Signal engine…"
        let path = socketPath
        Task.detached {
            let client = BridgeClient(path: path)
            var newState: QuillSignalLinkState = .notConnected
            var detail = "Signal engine not running. Start quill-signal-bridge, then Retry."
            if let line = try? client.request("{\"cmd\":\"status\"}") {
                if line.contains("\"registered\":true") {
                    newState = .linked
                    detail = "Linked."
                } else {
                    newState = .unlinked
                    detail = client.decode(line)?.msg ?? "This device isn't linked yet."
                }
            }
            let resolvedState = newState
            let resolvedDetail = detail
            Self.log("bridge status -> \(resolvedState): \(resolvedDetail)")
            await MainActor.run {
                self.linkState = resolvedState
                self.statusDetail = resolvedDetail
                self.isRefreshing = false
            }
        }
    }

    /// Begin device linking. The bridge streams a real `sgnl://linkdevice` URL,
    /// then blocks awaiting the phone scan — so this runs on a dedicated thread.
    public func beginLink(deviceName: String = "QuillOS") {
        guard !isLinking else { return }
        isLinking = true
        linkURL = nil
        statusDetail = "Requesting a link code from Signal…"
        let path = socketPath
        let cmd = "{\"cmd\":\"link-begin\",\"device_name\":\"\(deviceName)\"}"
        Thread.detachNewThread {
            let client = BridgeClient(path: path)
            try? client.stream(cmd, timeoutSeconds: 180) { line in
                guard let msg = client.decode(line) else { return true }
                switch msg.event {
                case "link-url":
                    if let url = msg.url {
                        Self.log("link URL -> \(url)")
                        Task { @MainActor in
                            self.linkURL = url
                            self.statusDetail = "Scan this in Signal → Settings → Linked Devices."
                        }
                    }
                    return true
                case "linked":
                    Task { @MainActor in
                        self.linkState = .linked
                        self.isLinking = false
                        self.statusDetail = "Linked."
                    }
                    return false
                case "link-error":
                    Task { @MainActor in
                        self.statusDetail = msg.msg ?? "Linking failed."
                        self.isLinking = false
                    }
                    return false
                default:
                    return true
                }
            }
            Task { @MainActor in self.isLinking = false }
        }
    }
}

// MARK: - View

@MainActor
public struct QuillSignalContentView: View {
    @StateObject private var model = QuillSignalModel()
    @State private var conversations: [Conversation]
    @State private var selectedID: Conversation.ID?
    @State private var draft: String

    public init() {
        let conversations = QuillSignalFixtures.conversations
        _conversations = State(initialValue: conversations)
        _selectedID = State(initialValue: QuillSignalInitialSelection.selectedConversationID(in: conversations) ?? conversations.first?.id)
        _draft = State(initialValue: "")
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            content
                .onAppear { model.startOnce() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.linkState {
        case .connecting:
            infoPanel(title: "Connecting to the Signal engine…", detail: model.statusDetail, retry: false)
        case .notConnected:
            infoPanel(title: "Signal engine not running", detail: model.statusDetail, retry: true)
        case .unlinked:
            linkPanel
        case .linked:
            ChatSplitShell(
                title: "Quill Signal",
                threads: conversations,
                selectedID: $selectedID,
                draft: $draft,
                placeholder: "Select a conversation",
                onSend: send
            )
        }
    }

    @ViewBuilder private func infoPanel(title: String, detail: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3).bold()
            Text(detail).font(.caption)
            if retry {
                Button(action: { model.refreshStatus() }) {
                    Text("Retry").font(.headline)
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private var linkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link this device to Signal").font(.title3).bold()
            Text("On your phone: Signal → Settings → Linked Devices → Link New Device, then scan or open this URL.")
                .font(.caption)
            if let url = model.linkURL {
                Text(url).font(.caption)
            } else if model.isLinking {
                Text(model.statusDetail).font(.caption)
            }
            Button(action: { model.beginLink() }) {
                Text(model.isLinking ? "Linking…" : "Link this device").font(.headline)
            }
            Spacer()
        }
        .padding(24)
    }

    private func send() {
        ChatDraft.sendMessage(
            from: &draft,
            toID: selectedID,
            in: &conversations
        ) { body in
            Message(sender: "Me", body: body, fromSelf: true)
        }
    }
}

public enum QuillSignalInitialSelection {
    public static let environmentKeys = [
        "QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START",
        ChatInitialSelection.sharedEnvironmentKey
    ]

    public static func selectedConversationID(
        in conversations: [Conversation],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Conversation.ID? {
        ChatInitialSelection.selectedID(
            in: conversations,
            environmentKeys: environmentKeys,
            environment: environment
        )
    }
}

// MARK: - Fixture model (chat shell, until the bridge serves conversations)

public struct Message: ChatMessage {
    public let id: UUID
    public let sender: String
    public let body: String
    public let fromSelf: Bool
    public let timestamp: Date?

    public init(
        id: UUID = UUID(),
        sender: String,
        body: String,
        fromSelf: Bool,
        timestamp: Date? = Date()
    ) {
        self.id = id
        self.sender = sender
        self.body = body
        self.fromSelf = fromSelf
        self.timestamp = timestamp
    }
}

public struct Conversation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var messages: [Message]

    public init(id: UUID = UUID(), name: String, messages: [Message]) {
        self.id = id
        self.name = name
        self.messages = messages
    }
}

extension Conversation: ChatThread {
    public var title: String { name }
    public var preview: String { messages.last?.body ?? "" }
}

public enum QuillSignalFixtures {
    public static let conversations: [Conversation] = [
        Conversation(
            name: "Family",
            messages: [
                Message(sender: "Mom", body: "Don't forget Sunday dinner.", fromSelf: false),
                Message(sender: "Me", body: "I'll bring dessert.", fromSelf: true),
                Message(sender: "Mom", body: "❤️", fromSelf: false),
            ]
        ),
        Conversation(
            name: "Coworker",
            messages: [
                Message(sender: "Jamie", body: "PR ready for review.", fromSelf: false),
                Message(sender: "Me", body: "Looking now.", fromSelf: true),
            ]
        ),
        Conversation(
            name: "Notes To Self",
            messages: [
                Message(sender: "Me", body: "Pick up groceries on the way home.", fromSelf: true),
            ]
        ),
    ]
}
