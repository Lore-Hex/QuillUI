//
// Bridge.swift -- data layer for signal-chat.
//
// Talks to quill-signal-bridge (presage + libsignal, real Signal protocol)
// over its unix-socket line-delimited-JSON protocol. One short-lived
// connection per request command, plus one long-lived connection streaming
// `receive` events. All socket work happens on background threads; the UI
// polls `snapshot()` off a Timer and re-renders when `generation` moves.
//
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

enum BridgeError: Error { case socket, connect(Int32), badPath }

/// Minimal unix-socket client for the bridge's line-delimited-JSON protocol.
/// (Adapted from QuillSignalKit's Phase-5a BridgeClient, validated on aarch64.)
final class BridgeClient {
    private let path: String
    init(path: String) { self.path = path }

    private func makeSocket() -> Int32 {
        #if canImport(Glibc)
        return socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        return socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
    }

    private func openConnection() throws -> Int32 {
        let fd = makeSocket()
        guard fd >= 0 else { throw BridgeError.socket }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < cap else { close(fd); throw BridgeError.badPath }
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: cap) { c in
                for (i, b) in bytes.enumerated() { c[i] = CChar(bitPattern: b) }
                c[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else { let e = errno; close(fd); throw BridgeError.connect(e) }
        return fd
    }

    private func sendLine(_ line: String, on fd: Int32) {
        var out = line
        if !out.hasSuffix("\n") { out += "\n" }
        out.withCString { _ = write(fd, $0, strlen($0)) }
    }

    private func readLine(on fd: Int32) -> String? {
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n <= 0 { return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self) }
            if byte == 0x0A { break }
            buf.append(byte)
        }
        return String(decoding: buf, as: UTF8.self)
    }

    /// One request line -> one response line, decoded as a JSON object.
    func request(_ obj: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8),
              let fd = try? openConnection() else { return nil }
        defer { close(fd) }
        sendLine(line, on: fd)
        guard let resp = readLine(on: fd), let rd = resp.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: rd) as? [String: Any]
        else { return nil }
        return parsed
    }

    /// Send one command, then stream every event line to `onLine` until EOF
    /// or `onLine` returns false.
    func stream(_ obj: [String: Any], onLine: ([String: Any]) -> Bool) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8),
              let fd = try? openConnection() else { return }
        defer { close(fd) }
        sendLine(line, on: fd)
        while let l = readLine(on: fd) {
            guard let ld = l.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: ld) as? [String: Any]
            else { continue }
            if !onLine(parsed) { break }
        }
    }
}

// MARK: - Models

struct Conversation: Identifiable {
    let id: String      // thread id: contact ACI or derived group uuid
    let name: String
    let isGroup: Bool
}

struct ChatMessage: Identifiable {
    let id: String
    let body: String
    let timestamp: UInt64    // ms since epoch
    let sender: String       // ACI
    let senderName: String?  // resolved name (receive events only)
    let fromSelf: Bool
    let attachmentPath: String?
    let attachmentKind: String?
}

// MARK: - Store

/// Thread-safe snapshot store fed by background bridge calls; the UI polls
/// `generation` and copies the snapshot when it moves.
final class ChatStore {
    static let shared = ChatStore()
    private let lock = NSLock()
    private let client: BridgeClient

    private(set) var generation = 0
    private var conversations: [Conversation] = []
    private var messages: [String: [ChatMessage]] = [:]
    private var status = "connecting to bridge…"

    private init() {
        let sock = ProcessInfo.processInfo.environment["QSIGNAL_SOCK"] ?? "/tmp/quill-signal.sock"
        client = BridgeClient(path: sock)
    }

    func snapshot() -> (gen: Int, convos: [Conversation], messages: [String: [ChatMessage]], status: String) {
        lock.lock(); defer { lock.unlock() }
        return (generation, conversations, messages, status)
    }

    private func mutate(_ f: () -> Void) {
        lock.lock(); f(); generation += 1; lock.unlock()
    }

    // MARK: lifecycle

    private var started = false
    private var uiPolling = false

    /// Idempotent: the GTK renderer re-fires onAppear on every re-render, so
    /// guard against spawning a receive thread (and duplicate events) per
    /// rebuild.
    func start() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }
        Thread.detachNewThread { [self] in bootstrap() }
        Thread.detachNewThread { [self] in receiveLoop() }
    }

    /// True exactly once — the caller that wins creates the UI poll Timer.
    func beginUIPolling() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if uiPolling { return false }
        uiPolling = true
        return true
    }

    private func bootstrap() {
        var line = "bridge unreachable"
        if let who = client.request(["cmd": "whoami"]),
           let data = who["data"] as? [String: Any] {
            if let number = data["number"] as? String {
                line = "linked · \(number)"
            } else {
                line = "bridge up · not linked"
            }
        }
        let convos = fetchConversations()
        mutate {
            status = line
            conversations = convos
        }
        // Pre-load the first few threads so switching is instant on camera.
        for c in convos.prefix(4) { loadMessages(thread: c.id) }
    }

    private func fetchConversations() -> [Conversation] {
        guard let resp = client.request(["cmd": "list-conversations"]),
              let data = resp["data"] as? [String: Any],
              let arr = data["conversations"] as? [[String: Any]] else { return [] }
        return arr.compactMap { c in
            guard let uuid = c["uuid"] as? String else { return nil }
            let name = (c["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
            return Conversation(id: uuid, name: name, isGroup: (c["type"] as? String) == "group")
        }
    }

    // MARK: messages

    func select(thread: String) {
        Thread.detachNewThread { [self] in loadMessages(thread: thread) }
    }

    private func loadMessages(thread: String) {
        guard let resp = client.request(["cmd": "list-messages", "thread": thread]),
              let data = resp["data"] as? [String: Any],
              let arr = data["messages"] as? [[String: Any]] else { return }
        let msgs: [ChatMessage] = arr.compactMap { m in
            guard let body = m["body"] as? String else { return nil }
            let ts = (m["timestamp"] as? NSNumber)?.uint64Value ?? 0
            let sender = m["sender"] as? String ?? ""
            return ChatMessage(
                id: "\(ts)-\(sender)",
                body: body, timestamp: ts, sender: sender, senderName: nil,
                fromSelf: (m["from_self"] as? Bool) ?? false,
                attachmentPath: m["attachment_path"] as? String,
                attachmentKind: m["attachment_kind"] as? String)
        }
        mutate { messages[thread] = msgs.sorted { $0.timestamp < $1.timestamp } }
    }

    func send(thread: String, body: String) {
        let ts = UInt64(Date().timeIntervalSince1970 * 1000)
        let optimistic = ChatMessage(
            id: "\(ts)-self", body: body, timestamp: ts, sender: "self", senderName: nil,
            fromSelf: true, attachmentPath: nil, attachmentKind: nil)
        mutate { messages[thread, default: []].append(optimistic) }
        Thread.detachNewThread { [self] in
            let resp = client.request(["cmd": "send", "thread": thread, "body": body, "timestamp": ts])
            if let resp, (resp["ok"] as? Bool) != true {
                let why = resp["msg"] as? String ?? "send failed"
                mutate { status = why }
            }
        }
    }

    // MARK: receive stream

    private func receiveLoop() {
        while true {
            client.stream(["cmd": "receive"]) { ev in
                guard (ev["event"] as? String) == "message",
                      let thread = ev["thread"] as? String,
                      let body = ev["body"] as? String else { return true }
                let ts = (ev["timestamp"] as? NSNumber)?.uint64Value ?? 0
                let sender = ev["sender"] as? String ?? ""
                let msg = ChatMessage(
                    id: "\(ts)-\(sender)",
                    body: body, timestamp: ts, sender: sender,
                    senderName: ev["sender_name"] as? String,
                    fromSelf: (ev["from_self"] as? Bool) ?? false,
                    attachmentPath: nil,
                    attachmentKind: ev["attachment_kind"] as? String)
                mutate {
                    var list = messages[thread, default: []]
                    if !list.contains(where: { $0.id == msg.id }) { list.append(msg) }
                    messages[thread] = list
                    if !conversations.contains(where: { $0.id == thread }) {
                        let name = msg.senderName ?? String(sender.prefix(8))
                        conversations.insert(
                            Conversation(id: thread, name: name, isGroup: false), at: 0)
                    }
                }
                return true
            }
            // Bridge restarted or stream dropped: retry quietly.
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
