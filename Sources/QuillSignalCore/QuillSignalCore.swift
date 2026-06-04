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

// The bridge wire-protocol response types (BridgeConversation,
// ConversationsResponse, BridgeStoredMessage, MessagesResponse, WhoamiResponse,
// …) now live in QuillSignalKit/BridgeProtocol.swift as the single public source
// of truth shared with the decode-contract check.

/// Thread-safe link-attempt tracker. The detached link thread compares its
/// generation against the current one to detect cancellation or supersession by
/// a newer attempt; `cancel()` and `start()` bump the generation so a stale
/// thread's late events (and its `isLinking` cleanup) are ignored.
final class LinkSession: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    func start() -> Int { lock.lock(); defer { lock.unlock() }; generation += 1; return generation }
    func cancel() { lock.lock(); generation += 1; lock.unlock() }
    func isCurrent(_ gen: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == gen }
}

@MainActor
public final class QuillSignalModel: ObservableObject {
    @Published public var linkState: QuillSignalLinkState = .connecting
    @Published public var statusDetail: String = ""
    @Published public var linkURL: String?
    @Published public var linkQR: String?
    @Published public var linkQRPath: String?
    @Published public var isLinking: Bool = false
    @Published public var conversations: [Conversation] = []
    @Published public var accountNumber: String?
    /// A transient, dismissible error shown above the chat (e.g. a failed send).
    @Published public var transientError: String?
    private var isRefreshing = false
    private var hasAutoStarted = false
    private var isReceiving = false
    /// Consecutive receive-stream restarts with no message, for escalating backoff.
    private var receiveBackoff = 0
    /// Per-thread set of seen Signal timestamps (millis), keyed by lowercased
    /// thread uuid, to drop duplicate messages from send/receive/reload.
    private var seenTimestamps: [String: Set<UInt64>] = [:]
    /// Tracks the active link attempt so Cancel (and re-link) can invalidate a
    /// still-running link thread. nonisolated: read from the detached thread.
    nonisolated private let linkSession = LinkSession()

    private let socketPath: String

    public init(socketPath: String = BridgeClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Diagnostic line to stderr (visible in headless/smoke runs).
    nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data(("[QuillSignal] " + message + "\n").utf8))
    }

    /// Ensure the presage bridge daemon is running so the app is self-contained.
    /// If the unix socket is absent, spawn the bridge binary (env
    /// QUILL_SIGNAL_BRIDGE_BIN, else next to the app, else /usr/local/bin) with the
    /// socket as argv[1] and a persistent QSIGNAL_DB, then poll up to ~5s for the
    /// socket. Idempotent: a present socket means a daemon is already up -> reuse it.
    /// Blocking (spawn + poll) — call from a background task, never the main thread.
    nonisolated static func ensureDaemon(socketPath: String) {
        let fm = FileManager.default
        // Connect-probe rather than just checking the file: a stale socket (the
        // daemon crashed but left the file behind) must NOT be reused — spawn a
        // fresh daemon, which remove_file()s the stale socket on startup.
        if BridgeClient(path: socketPath).probe() {
            log("bridge daemon already listening -> reusing")
            return
        }
        if fm.fileExists(atPath: socketPath) {
            log("stale bridge socket (no listener) -> spawning fresh daemon")
        }
        let env = ProcessInfo.processInfo.environment
        let binPath = env["QUILL_SIGNAL_BRIDGE_BIN"] ?? defaultBridgeBin()
        guard fm.fileExists(atPath: binPath) else {
            log("bridge binary not found at \(binPath) — set QUILL_SIGNAL_BRIDGE_BIN")
            return
        }
        let dbPath = env["QSIGNAL_DB"] ?? defaultDBPath()
        try? fm.createDirectory(atPath: (dbPath as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binPath)
        proc.arguments = [socketPath]
        var penv = env
        penv["QSIGNAL_DB"] = dbPath
        proc.environment = penv
        do {
            try proc.run()
            log("spawned bridge daemon pid \(proc.processIdentifier) bin=\(binPath) db=\(dbPath)")
        } catch {
            log("failed to spawn bridge daemon: \(error)")
            return
        }
        for _ in 0..<50 {
            if BridgeClient(path: socketPath).probe() {
                log("bridge socket up")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        log("bridge socket did not appear within timeout")
    }

    /// Default bridge binary: next to the app binary, else a conventional install path.
    nonisolated static func defaultBridgeBin() -> String {
        let appPath = CommandLine.arguments.first ?? ""
        let dir = (appPath as NSString).deletingLastPathComponent
        let sibling = dir.isEmpty ? "quill-signal-bridge" : dir + "/quill-signal-bridge"
        if FileManager.default.fileExists(atPath: sibling) { return sibling }
        return "/usr/local/bin/quill-signal-bridge"
    }

    /// Default account DB: XDG data dir, else ~/.local/share, else /tmp.
    nonisolated static func defaultDBPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let xdg = env["XDG_DATA_HOME"], !xdg.isEmpty {
            return xdg + "/quill-signal/qs.db"
        }
        if let home = env["HOME"], !home.isEmpty {
            return home + "/.local/share/quill-signal/qs.db"
        }
        return "/tmp/quill-signal.db"
    }

    /// Kick off the first status query. Idempotent — `.onAppear` can fire on
    /// every render, and we must not re-query (concurrent presage store opens
    /// race on the sqlite migrations).
    public func startOnce() {
        guard !hasAutoStarted else { return }
        hasAutoStarted = true
        let env = ProcessInfo.processInfo.environment
        // Test hook (off by default): render the linked chat shell from fixtures —
        // no daemon, no account touched — so the conversation UI can be screenshot.
        if env["QUILLUI_SIGNAL_FAKELINKED"] == "1" {
            accountNumber = "+1 555 0100"
            conversations = QuillSignalFixtures.conversations
            if env["QUILLUI_SIGNAL_FAKEEMPTY"] == "1" {
                conversations = []   // linked but no conversations yet
            }
            if env["QUILLUI_SIGNAL_FAKEERROR"] == "1" {
                transientError = "Message not sent. Check your connection."
            }
            linkState = .linked
            return
        }
        // Each entry point (refreshStatus / beginLink) ensures the daemon in its
        // own background context, so just dispatch here. Test hook (off by
        // default): go straight to linking so a headless smoke can verify the
        // device-link flow (URL + QR) without a human clicking.
        if env["QUILLUI_SIGNAL_AUTOLINK"] == "1" {
            linkState = .unlinked   // show the link panel so the QR is visible
            beginLink()
        } else {
            refreshStatus()
        }
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
            // Re-ensure the daemon first, so Retry recovers from a crashed daemon
            // (respawns) or a stale socket — not just a never-started one.
            Self.ensureDaemon(socketPath: path)
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
                if resolvedState == .linked {
                    self.onBecameLinked()
                }
            }
        }
    }

    /// Everything to start once the device is linked — load the conversation
    /// list + account identity and begin the receive stream. Idempotent
    /// (loadConversations/whoami refetch; startReceiving is guarded), so it's
    /// safe to call from both the status path and an in-app link completion.
    private func onBecameLinked() {
        loadConversations()
        loadWhoami()
        startReceiving()
    }

    /// Load the conversation list from the bridge. Empty until linked; the real
    /// Signal contacts once linked. (Messages/send are later bridge commands.)
    public func loadConversations() {
        let path = socketPath
        Task.detached {
            let client = BridgeClient(path: path)
            var loaded: [Conversation] = []
            if let line = try? client.request("{\"cmd\":\"list-conversations\"}"),
               let bytes = line.data(using: .utf8),
               let resp = try? JSONDecoder().decode(ConversationsResponse.self, from: bytes),
               let items = resp.data?.conversations {
                loaded = items.map { item in
                    let title = (item.name.flatMap { $0.isEmpty ? nil : $0 }) ?? item.uuid ?? "Unknown"
                    // Use the bridge thread uuid as the Conversation id so a
                    // selection maps straight back to list-messages.
                    let id = item.uuid.flatMap { UUID(uuidString: $0) } ?? UUID()
                    return Conversation(id: id, name: title, messages: [])
                }
                Self.log("loaded \(loaded.count) conversations")
            }
            let result = loaded
            await MainActor.run { self.conversations = result }
        }
    }

    /// Load the messages for a selected conversation thread (its uuid) from the
    /// bridge and set them on the matching conversation. Empty until linked.
    /// (fromSelf is a placeholder until whoami/the bridge marks own messages.)
    public func loadMessages(for threadUuid: String) {
        let path = socketPath
        Task.detached {
            let client = BridgeClient(path: path)
            var loaded: [Message] = []
            var stamps: Set<UInt64> = []
            let cmd = "{\"cmd\":\"list-messages\",\"thread\":\"\(threadUuid)\"}"
            if let line = try? client.request(cmd),
               let bytes = line.data(using: .utf8),
               let resp = try? JSONDecoder().decode(MessagesResponse.self, from: bytes),
               let items = resp.data?.messages {
                // Dedup the loaded batch by timestamp and seed the per-thread seen set.
                let deduped = MessageDedup.unseen(items, seen: &stamps) { $0.timestamp }
                loaded = deduped.map { m in
                    Message(
                        sender: m.sender ?? "",
                        body: m.body ?? "",
                        fromSelf: m.fromSelf ?? false,
                        timestamp: m.timestamp.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                        attachmentImagePath: m.attachmentPath,
                        attachmentKind: m.attachmentKind
                    )
                }
                Self.log("loaded \(loaded.count) messages for \(threadUuid)")
            }
            let result = loaded
            let resultStamps = stamps
            await MainActor.run {
                self.seenTimestamps[threadUuid.lowercased()] = resultStamps
                if let idx = self.conversations.firstIndex(where: {
                    $0.id.uuidString.caseInsensitiveCompare(threadUuid) == .orderedSame
                }) {
                    self.conversations[idx].messages = result
                }
            }
        }
    }

    /// Load the linked account identity (phone number) from the bridge.
    public func loadWhoami() {
        let path = socketPath
        Task.detached {
            let client = BridgeClient(path: path)
            var number: String? = nil
            if let line = try? client.request("{\"cmd\":\"whoami\"}"),
               let bytes = line.data(using: .utf8),
               let resp = try? JSONDecoder().decode(WhoamiResponse.self, from: bytes),
               resp.data?.registered == true {
                number = resp.data?.number
            }
            let result = number
            await MainActor.run { self.accountNumber = result }
        }
    }

    /// Start the long-lived receive stream: the bridge pushes a {event:"message"}
    /// line per incoming message; append each to its conversation. Auto-started
    /// once linked (correct product behavior); guarded so only one stream runs.
    public func startReceiving() {
        guard !isReceiving else { return }
        isReceiving = true
        let path = socketPath
        Thread.detachNewThread {
            // Ensure the daemon is up before connecting (covers a restart after a
            // daemon crash, like beginLink does).
            Self.ensureDaemon(socketPath: path)
            let client = BridgeClient(path: path)
            try? client.stream("{\"cmd\":\"receive\"}", timeoutSeconds: 0) { line in
                guard let data = line.data(using: .utf8),
                      let msg = try? JSONDecoder().decode(IncomingMessage.self, from: data) else { return true }
                if msg.event == "receive-error" {
                    let detail = msg.msg
                    Self.log("receive-error -> \(detail ?? "")")
                    Task { @MainActor in
                        self.transientError = detail ?? "Couldn't receive messages. Reconnecting…"
                    }
                    return true
                }
                guard msg.event == "message",
                      let thread = msg.thread, let body = msg.body else { return true }
                let ts = msg.timestamp
                let name = msg.senderName
                let m = Message(
                    sender: msg.sender ?? "",
                    body: body,
                    fromSelf: msg.fromSelf ?? false,
                    timestamp: ts.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                    attachmentKind: msg.attachmentKind
                )
                Task { @MainActor in self.appendIncoming(thread: thread, message: m, timestampMillis: ts, senderName: name) }
                return true
            }
            Task { @MainActor in
                self.isReceiving = false
                // Auto-restart while still linked (recovers from an engine
                // crash/restart) with an escalating backoff (5,10,20,40,60s…) so a
                // persistently-down engine doesn't tight-loop; reset on a message.
                if self.linkState == .linked {
                    let secs = min(60, 5 * (1 << min(self.receiveBackoff, 4)))
                    self.receiveBackoff += 1
                    try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
                    if self.linkState == .linked { self.startReceiving() }
                }
            }
        }
    }

    /// Append a pushed message to its thread (create the conversation if the
    /// sender isn't a known contact yet).
    private func appendIncoming(thread: String, message: Message, timestampMillis: UInt64?, senderName: String?) {
        receiveBackoff = 0   // a live message -> the stream is healthy
        let key = thread.lowercased()
        if let ts = timestampMillis {
            if seenTimestamps[key]?.contains(ts) == true { return } // already shown
            seenTimestamps[key, default: []].insert(ts)
        }
        let resolvedName = senderName.flatMap { $0.isEmpty ? nil : $0 }
        let idx = conversations.firstIndex(where: {
            $0.id.uuidString.caseInsensitiveCompare(thread) == .orderedSame
        })
        // Display name: a known conversation's name, else the resolved contact name.
        let displayName = idx.map { conversations[$0].name } ?? resolvedName
        if let idx {
            conversations[idx].messages.append(message)
        } else if let id = UUID(uuidString: thread) {
            // New conversation from an unknown thread — use the contact name if known.
            conversations.append(Conversation(id: id, name: resolvedName ?? thread, messages: [message]))
        }
        // A received attachment can't be downloaded inside the receive stream (it
        // holds the manager mutably), so re-pull the thread: list-messages
        // downloads the image and it backfills into the bubble. The bridge's
        // digest cache makes already-shown images a no-op, so only the new
        // attachment actually fetches. loadMessages never re-enters appendIncoming,
        // so there is no trigger loop.
        if AttachmentMarker.isPresent(in: message.body) {
            loadMessages(for: thread)
        }
        // Desktop notification for a fresh, incoming (non-self) message.
        if let n = NotificationFormat.make(sender: displayName, body: message.body, fromSelf: message.fromSelf) {
            let title = n.title, toast = n.body
            Task.detached { Self.notify(title: title, body: toast) }
        }
    }

    /// Fire a desktop notification via notify-send (env QUILL_SIGNAL_NOTIFY_BIN,
    /// else PATH lookup). Best-effort: if the binary isn't found, skip silently.
    nonisolated static func notify(title: String, body: String) {
        Self.log("notify -> \(title): \(body)")
        let bin = ProcessInfo.processInfo.environment["QUILL_SIGNAL_NOTIFY_BIN"] ?? "notify-send"
        guard let path = resolveExecutable(bin) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [title, body]
        try? proc.run()
    }

    /// Resolve an executable name to a path: an existing path with a slash, else
    /// search PATH. Returns nil if not found/executable.
    nonisolated static func resolveExecutable(_ bin: String) -> String? {
        let fm = FileManager.default
        if bin.contains("/") {
            return fm.isExecutableFile(atPath: bin) ? bin : nil
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(bin)"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Send a text message to a thread via the bridge. Optimistically appends a
    /// from-self message for instant feedback, then fires the bridge `send`
    /// command off the main thread. ONLY invoked from an explicit user action
    /// (the composer's send button) — never automatically; reaches the real
    /// account only once linked.
    public func send(to threadUuid: String, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // One client-generated timestamp shared by the optimistic echo, the seen
        // set, and the bridge — so the stored/echoed copy dedups exactly.
        let ts = UInt64(Date().timeIntervalSince1970 * 1000)
        if let idx = conversations.firstIndex(where: {
            $0.id.uuidString.caseInsensitiveCompare(threadUuid) == .orderedSame
        }) {
            conversations[idx].messages.append(
                Message(sender: "Me", body: trimmed, fromSelf: true,
                        timestamp: Date(timeIntervalSince1970: Double(ts) / 1000.0))
            )
            seenTimestamps[threadUuid.lowercased(), default: []].insert(ts)
        }
        // Build the command with proper JSON escaping (body is arbitrary text).
        // JSONSerialization needs Int, not UInt64, for the number.
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "cmd": "send", "thread": threadUuid, "body": trimmed, "timestamp": Int(ts),
        ]), let cmd = String(data: data, encoding: .utf8) else { return }
        let path = socketPath
        Task.detached {
            let client = BridgeClient(path: path)
            if let line = try? client.request(cmd) {
                Self.log("send -> \(line)")
                let ok = client.decode(line)?.ok ?? false
                await MainActor.run {
                    self.transientError = ok ? nil : "Message not sent. Check your connection."
                }
            } else {
                Self.log("send failed: no response from bridge")
                await MainActor.run {
                    self.transientError = "Message not sent. Check your connection."
                }
            }
        }
    }

    /// Begin device linking. The bridge streams a real `sgnl://linkdevice` URL,
    /// then blocks awaiting the phone scan — so this runs on a dedicated thread.
    public func beginLink(deviceName: String = "QuillOS") {
        guard !isLinking else { return }
        isLinking = true
        linkURL = nil
        linkQR = nil
        linkQRPath = nil
        statusDetail = "Requesting a link code from Signal…"
        let path = socketPath
        let myGen = linkSession.start()
        let cmd = "{\"cmd\":\"link-begin\",\"device_name\":\"\(deviceName)\"}"
        Thread.detachNewThread {
            // Ensure the daemon is up before the link stream (covers a cold start
            // or a crashed daemon when the user links before a status query).
            Self.ensureDaemon(socketPath: path)
            let client = BridgeClient(path: path)
            try? client.stream(cmd, timeoutSeconds: 180) { line in
                // Stop if this attempt was cancelled or superseded by a newer one.
                if !self.linkSession.isCurrent(myGen) { return false }
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
                case "link-qr":
                    if let qr = msg.qr {
                        Self.log("link QR -> \(qr.count) chars")
                        Task { @MainActor in self.linkQR = qr }
                    }
                    if let qrPath = msg.qrPngPath {
                        Self.log("link QR png -> \(qrPath)")
                        Task { @MainActor in self.linkQRPath = qrPath }
                    }
                    return true
                case "linked":
                    Task { @MainActor in
                        self.linkState = .linked
                        self.isLinking = false
                        self.statusDetail = "Linked."
                        // Load conversations/account + start receiving now, so the
                        // in-app link lands on a populated, live chat (not empty).
                        self.onBecameLinked()
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
            Task { @MainActor in if self.linkSession.isCurrent(myGen) { self.isLinking = false } }
        }
    }

    /// Cancel an in-flight link attempt. Bumps the link generation so the still-
    /// running link thread's late events (and cleanup) are ignored, and resets
    /// the panel back to its pre-link state immediately. (The orphaned thread,
    /// blocked awaiting the phone scan, exits on its socket timeout.)
    public func cancelLink() {
        guard isLinking else { return }
        linkSession.cancel()
        isLinking = false
        linkURL = nil
        linkQR = nil
        linkQRPath = nil
        statusDetail = "Linking cancelled. Tap Link this device to try again."
        Self.log("link cancelled by user")
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
            VStack(spacing: 0) {
                if let err = model.transientError {
                    errorBanner(err)
                }
                ChatSplitShell(
                    title: model.accountNumber.map { "Quill Signal — \($0)" } ?? "Quill Signal",
                    threads: model.conversations,
                    selectedID: Binding(
                        get: { selectedID },
                        set: { newID in
                            selectedID = newID
                            if let id = newID { model.loadMessages(for: id.uuidString) }
                        }
                    ),
                    draft: $draft,
                    placeholder: model.conversations.isEmpty
                        ? "No conversations yet. New messages will appear here."
                        : "Select a conversation",
                    onSend: send
                )
            }
        }
    }

    /// A dismissible error bar shown above the chat (e.g. a failed send).
    @ViewBuilder private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message).font(.caption)
            Spacer()
            Button(action: { model.transientError = nil }) {
                Text("Dismiss").font(.caption)
            }
        }
        .padding(8)
        .background(Color.red.opacity(0.18))
        .onTapGesture { model.transientError = nil }
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
            Text("On your phone: Signal → Settings → Linked Devices → Link New Device, then scan this QR.")
                .font(.caption)
            if let qrPath = model.linkQRPath, FileManager.default.fileExists(atPath: qrPath) {
                // Crisp bitmap QR (square modules, no font-leading seams).
                Image(filePath: qrPath).resizable().frame(width: 260, height: 260)
            } else if let qr = model.linkQR {
                // Fallback: the Unicode-block QR as monospace text.
                Text(qr).font(.system(size: 9, design: .monospaced))
            }
            if let url = model.linkURL {
                Text(url).font(.caption)
            } else if model.isLinking {
                Text(model.statusDetail).font(.caption)
            }
            HStack(spacing: 12) {
                Button(action: { model.beginLink() }) {
                    Text(model.isLinking ? "Linking…" : "Link this device").font(.headline)
                }
                if model.isLinking {
                    Button(action: { model.cancelLink() }) {
                        Text("Cancel").font(.headline)
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let id = selectedID else { return }
        // Real send goes through the model -> bridge -> presage. Only fires on an
        // explicit press of the composer's send button (never automatically).
        model.send(to: id.uuidString, body: body)
        draft = ""
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
    public let attachmentImagePath: String?
    public let attachmentKind: String?

    public init(
        id: UUID = UUID(),
        sender: String,
        body: String,
        fromSelf: Bool,
        timestamp: Date? = Date(),
        attachmentImagePath: String? = nil,
        attachmentKind: String? = nil
    ) {
        self.id = id
        self.sender = sender
        self.body = body
        self.fromSelf = fromSelf
        self.timestamp = timestamp
        self.attachmentImagePath = attachmentImagePath
        self.attachmentKind = attachmentKind
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
    public var lastActivity: Date? { messages.last?.timestamp }
}

public enum QuillSignalFixtures {
    public static let conversations: [Conversation] = [
        Conversation(
            name: "Family",
            messages: [
                // Spread across the relative-stamp ranges so a FAKELINKED screenshot
                // exercises weekday / Yesterday / minutes formatting in one view.
                Message(sender: "Mom", body: "Don't forget Sunday dinner.", fromSelf: false,
                        timestamp: Date(timeIntervalSinceNow: -3 * 86400)),
                Message(sender: "Me", body: "I'll bring dessert.", fromSelf: true,
                        timestamp: Date(timeIntervalSinceNow: -3 * 86400 + 120)),
                Message(sender: "Mom", body: "❤️", fromSelf: false,
                        timestamp: Date(timeIntervalSinceNow: -86400)),
                // An image attachment renders in the bubble when the file exists
                // (a FAKELINKED screenshot writes one to this path; nil/absent => text only).
                // A non-image attachment renders as a typed FILE-tag chip.
                Message(sender: "Mom", body: "[attachment: recipe.pdf]", fromSelf: false,
                        timestamp: Date(timeIntervalSinceNow: -540),
                        attachmentKind: "file"),
                Message(sender: "Mom", body: "Look at the cake!", fromSelf: false,
                        timestamp: Date(timeIntervalSinceNow: -480),
                        attachmentImagePath: "/tmp/qs-fixture-image.png"),
            ]
        ),
        Conversation(
            name: "Coworker",
            messages: [
                Message(sender: "Jamie", body: "PR ready for review.", fromSelf: false,
                        timestamp: Date(timeIntervalSinceNow: -2 * 86400)),
                Message(sender: "Me", body: "Looking now.", fromSelf: true,
                        timestamp: Date(timeIntervalSinceNow: -2700)),
            ]
        ),
        Conversation(
            name: "Notes To Self",
            messages: [
                Message(sender: "Me", body: "Pick up groceries on the way home.", fromSelf: true,
                        timestamp: Date(timeIntervalSinceNow: -90000)),
            ]
        ),
    ]
}
