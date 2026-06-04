// quill-signal-decode-check — a standalone assertion harness that locks the
// quill-signal-bridge wire protocol: every line the Rust bridge emits must decode
// into QuillSignalKit's `BridgeMessage`. Foundation-only (no GTK), so it builds
// and runs fast as its own product. Exits 0 if all checks pass, 1 otherwise.
//
//   swift build --product quill-signal-decode-check
//   .build/.../quill-signal-decode-check   # EXIT=0 means the contract holds
import Foundation
import QuillSignalKit

final class Checker {
    var failures = 0
    func check(_ name: String, _ ok: Bool) {
        if ok {
            print("ok   - \(name)")
        } else {
            print("FAIL - \(name)")
            failures += 1
        }
    }
    func decode(_ json: String) -> BridgeMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BridgeMessage.self, from: data)
    }
    func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Tiny element type for exercising MessageDedup.unseen.
struct TS { let id: Int; let ts: UInt64? }

let c = Checker()

// 1. ping -> pong response
if let m = c.decode(#"{"ok":true,"cmd":"ping","msg":"pong"}"#) {
    c.check("ping ok==true", m.ok == true)
    c.check("ping cmd==ping", m.cmd == "ping")
    c.check("ping msg==pong", m.msg == "pong")
    c.check("ping has no event", m.event == nil)
} else {
    c.check("ping decodes", false)
}

// 2. status (unlinked) — the embedded data object is ignored by BridgeMessage
if let m = c.decode(#"{"ok":true,"cmd":"status","msg":"not registered","data":{"registered":false}}"#) {
    c.check("status ok==true", m.ok == true)
    c.check("status cmd==status", m.cmd == "status")
    c.check("status msg has text", m.msg?.contains("not registered") == true)
} else {
    c.check("status decodes", false)
}

// 3. link-url event
if let m = c.decode(#"{"event":"link-url","url":"sgnl://linkdevice?uuid=abc&pub_key=def","device_name":"QuillOS"}"#) {
    c.check("link-url event", m.event == "link-url")
    c.check("link-url url prefix", m.url?.hasPrefix("sgnl://linkdevice") == true)
} else {
    c.check("link-url decodes", false)
}

// 4. link-qr event — the key qr_png_path -> qrPngPath CodingKey mapping
if let m = c.decode(#"{"event":"link-qr","qr":"block-art","qr_png_path":"/tmp/quill-signal-qr.png"}"#) {
    c.check("link-qr event", m.event == "link-qr")
    c.check("link-qr qr present", m.qr == "block-art")
    c.check("link-qr qr_png_path maps to qrPngPath", m.qrPngPath == "/tmp/quill-signal-qr.png")
} else {
    c.check("link-qr decodes", false)
}

// 4b. link-qr without a png path (older bridge) — qrPngPath stays nil, no crash
if let m = c.decode(#"{"event":"link-qr","qr":"block-art"}"#) {
    c.check("link-qr without png -> qrPngPath nil", m.qrPngPath == nil)
    c.check("link-qr without png -> qr present", m.qr == "block-art")
} else {
    c.check("link-qr (no png) decodes", false)
}

// 5. linked event
if let m = c.decode(#"{"event":"linked","ok":true,"whoami":"ServiceIds"}"#) {
    c.check("linked event", m.event == "linked")
    c.check("linked ok==true", m.ok == true)
} else {
    c.check("linked decodes", false)
}

// 6. link-error event
if let m = c.decode(#"{"event":"link-error","ok":false,"msg":"link timed out"}"#) {
    c.check("link-error event", m.event == "link-error")
    c.check("link-error ok==false", m.ok == false)
    c.check("link-error msg", m.msg == "link timed out")
} else {
    c.check("link-error decodes", false)
}

// 7. send response
if let m = c.decode(#"{"ok":true,"cmd":"send","msg":"sent","data":{"timestamp":1700000000000}}"#) {
    c.check("send ok==true", m.ok == true)
    c.check("send cmd==send", m.cmd == "send")
    c.check("send msg==sent", m.msg == "sent")
} else {
    c.check("send decodes", false)
}

// 8. bad-request error envelope
if let m = c.decode(#"{"ok":false,"cmd":"?","msg":"bad request: trailing"}"#) {
    c.check("bad-request ok==false", m.ok == false)
    c.check("bad-request msg prefix", m.msg?.hasPrefix("bad request") == true)
} else {
    c.check("bad-request decodes", false)
}

// 9. forward-compat: unknown / extra keys are ignored, not fatal
if let m = c.decode(#"{"ok":true,"cmd":"status","msg":"x","future_field":123,"nested":{"a":1}}"#) {
    c.check("ignores unknown keys", m.cmd == "status" && m.ok == true)
} else {
    c.check("unknown-keys decodes", false)
}

// 10. list-conversations envelope (contacts with type/uuid/name; null name)
if let r = c.decode(ConversationsResponse.self, #"{"ok":true,"cmd":"list-conversations","msg":"ok","data":{"conversations":[{"type":"contact","uuid":"11111111-1111-1111-1111-111111111111","name":"Alice"},{"type":"contact","uuid":"22222222-2222-2222-2222-222222222222","name":null}]}}"#),
   let convos = r.data?.conversations {
    c.check("conversations count==2", convos.count == 2)
    c.check("conversation type==contact", convos.first?.type == "contact")
    c.check("conversation uuid", convos.first?.uuid == "11111111-1111-1111-1111-111111111111")
    c.check("conversation name==Alice", convos.first?.name == "Alice")
    c.check("conversation null name -> nil", convos.last?.name == nil)
} else {
    c.check("list-conversations decodes", false)
}

// 10b. list-conversations empty (unlinked)
if let r = c.decode(ConversationsResponse.self, #"{"ok":true,"cmd":"list-conversations","msg":"not registered","data":{"conversations":[]}}"#) {
    c.check("conversations empty list", r.data?.conversations.isEmpty == true)
} else {
    c.check("list-conversations empty decodes", false)
}

// 10c. list-conversations with a group entry (type:"group", uuid, name)
if let r = c.decode(ConversationsResponse.self, #"{"ok":true,"cmd":"list-conversations","data":{"conversations":[{"type":"group","uuid":"44444444-4444-4444-4444-444444444444","name":"Weekend Trip"}]}}"#),
   let g = r.data?.conversations.first {
    c.check("group entry type==group", g.type == "group")
    c.check("group entry uuid", g.uuid == "44444444-4444-4444-4444-444444444444")
    c.check("group entry name", g.name == "Weekend Trip")
} else {
    c.check("group conversation decodes", false)
}

// 11. list-messages envelope — from_self true / false / missing(nil)
if let r = c.decode(MessagesResponse.self, #"{"ok":true,"cmd":"list-messages","msg":"ok","data":{"messages":[{"body":"hi","timestamp":1700000000000,"sender":"aaa","from_self":true},{"body":"yo","timestamp":1700000001000,"sender":"bbb","from_self":false},{"body":"old","timestamp":1700000002000,"sender":"ccc"}]}}"#),
   let msgs = r.data?.messages {
    c.check("messages count==3", msgs.count == 3)
    c.check("message body", msgs.first?.body == "hi")
    c.check("message timestamp", msgs.first?.timestamp == 1_700_000_000_000)
    c.check("message sender", msgs.first?.sender == "aaa")
    c.check("from_self:true -> fromSelf==true", msgs[0].fromSelf == true)
    c.check("from_self:false -> fromSelf==false", msgs[1].fromSelf == false)
    c.check("missing from_self -> fromSelf==nil", msgs[2].fromSelf == nil)
    c.check("no attachment_path -> attachmentPath==nil", msgs[0].attachmentPath == nil)
} else {
    c.check("list-messages decodes", false)
}

// 11b. list-messages with attachment_path — present maps to attachmentPath, absent is nil
if let r = c.decode(MessagesResponse.self, #"{"ok":true,"cmd":"list-messages","msg":"ok","data":{"messages":[{"body":"pic","timestamp":1700000004000,"sender":"ddd","from_self":false,"attachment_path":"/tmp/qs-att-deadbeef.png"},{"body":"text only","timestamp":1700000005000,"sender":"eee","from_self":false}]}}"#),
   let msgs = r.data?.messages {
    c.check("attachment_path -> attachmentPath set", msgs[0].attachmentPath == "/tmp/qs-att-deadbeef.png")
    c.check("missing attachment_path -> attachmentPath nil", msgs[1].attachmentPath == nil)
} else {
    c.check("list-messages attachment_path decodes", false)
}

// 11c. AttachmentMarker — the bridge marker that drives live-receive image backfill
c.check("marker: text + marker -> true", AttachmentMarker.isPresent(in: "look\n[attachment: a.png]"))
c.check("marker: bare marker -> true", AttachmentMarker.isPresent(in: "[attachment: image/jpeg]"))
c.check("marker: plain text -> false", !AttachmentMarker.isPresent(in: "just a message"))
c.check("marker: nil body -> false", !AttachmentMarker.isPresent(in: nil))

// 12. whoami — registered with number
if let r = c.decode(WhoamiResponse.self, #"{"ok":true,"cmd":"whoami","msg":"ok","data":{"registered":true,"number":"+15551234567"}}"#) {
    c.check("whoami registered==true", r.data?.registered == true)
    c.check("whoami number", r.data?.number == "+15551234567")
} else {
    c.check("whoami decodes", false)
}

// 12b. whoami — unregistered (no number)
if let r = c.decode(WhoamiResponse.self, #"{"ok":true,"cmd":"whoami","msg":"not registered","data":{"registered":false}}"#) {
    c.check("whoami registered==false", r.data?.registered == false)
    c.check("whoami no number -> nil", r.data?.number == nil)
} else {
    c.check("whoami unregistered decodes", false)
}

// 13. incoming receive-stream message event (fields + from_self + sender_name)
if let m = c.decode(IncomingMessage.self, #"{"event":"message","thread":"33333333-3333-3333-3333-333333333333","sender":"33333333-3333-3333-3333-333333333333","sender_name":"Alice","body":"incoming hi","timestamp":1700000003000,"from_self":false}"#) {
    c.check("incoming event==message", m.event == "message")
    c.check("incoming thread", m.thread == "33333333-3333-3333-3333-333333333333")
    c.check("incoming sender", m.sender == "33333333-3333-3333-3333-333333333333")
    c.check("incoming sender_name -> senderName==Alice", m.senderName == "Alice")
    c.check("incoming body", m.body == "incoming hi")
    c.check("incoming timestamp", m.timestamp == 1_700_000_003_000)
    c.check("incoming from_self:false -> fromSelf==false", m.fromSelf == false)
} else {
    c.check("incoming message decodes", false)
}
// 13c. incoming with sender_name null -> senderName nil
if let m = c.decode(IncomingMessage.self, #"{"event":"message","thread":"t","sender":"t","sender_name":null,"body":"x","timestamp":1}"#) {
    c.check("incoming sender_name:null -> senderName==nil", m.senderName == nil)
} else {
    c.check("incoming (null sender_name) decodes", false)
}
// 13d. receive-error event decodes (event + msg detail)
if let m = c.decode(IncomingMessage.self, #"{"event":"receive-error","ok":false,"msg":"not registered"}"#) {
    c.check("receive-error event", m.event == "receive-error")
    c.check("receive-error msg", m.msg == "not registered")
} else {
    c.check("receive-error decodes", false)
}

// 13b. incoming from_self:true (own message synced from another device)
if let m = c.decode(IncomingMessage.self, #"{"event":"message","thread":"t","sender":"t","body":"echo","timestamp":1,"from_self":true}"#) {
    c.check("incoming from_self:true -> fromSelf==true", m.fromSelf == true)
} else {
    c.check("incoming (from_self true) decodes", false)
}

// 14. MessageDedup.unseen — drop already-seen + intra-batch dups, keep nils,
// preserve order, mutate the seen set.
do {
    var seen: Set<UInt64> = [100]
    let input = [TS(id: 1, ts: 100), TS(id: 2, ts: 200), TS(id: 3, ts: 200),
                 TS(id: 4, ts: nil), TS(id: 5, ts: 300)]
    let kept = MessageDedup.unseen(input, seen: &seen) { $0.ts }
    c.check("dedup keeps [2,4,5] in order", kept.map { $0.id } == [2, 4, 5])
    c.check("dedup drops already-seen ts(100)", !kept.contains { $0.id == 1 })
    c.check("dedup drops intra-batch dup ts(200)", kept.filter { $0.ts == 200 }.count == 1)
    c.check("dedup keeps nil-timestamp item", kept.contains { $0.id == 4 })
    c.check("dedup seen == {100,200,300}", seen == [100, 200, 300])
}
do {
    var seen: Set<UInt64> = []
    let kept = MessageDedup.unseen([TS(id: 1, ts: 5), TS(id: 2, ts: 5)], seen: &seen) { $0.ts }
    c.check("dedup keeps first of a dup pair", kept.map { $0.id } == [1])
    c.check("dedup nil-only items all kept", MessageDedup.unseen([TS(id: 9, ts: nil)], seen: &seen) { $0.ts }.count == 1)
}

// 15. NotificationFormat.make — own/empty -> nil; title falls back to "Signal".
do {
    c.check("notify fromSelf -> nil", NotificationFormat.make(sender: "Mom", body: "hi", fromSelf: true) == nil)
    c.check("notify nil body -> nil", NotificationFormat.make(sender: "Mom", body: nil, fromSelf: false) == nil)
    c.check("notify empty body -> nil", NotificationFormat.make(sender: "Mom", body: "", fromSelf: false) == nil)
    if let n = NotificationFormat.make(sender: "Mom", body: "dinner?", fromSelf: false) {
        c.check("notify title == name", n.title == "Mom")
        c.check("notify body passthrough", n.body == "dinner?")
    } else {
        c.check("notify present case", false)
    }
    c.check("notify nil name -> Signal", NotificationFormat.make(sender: nil, body: "x", fromSelf: false)?.title == "Signal")
    c.check("notify blank name -> Signal", NotificationFormat.make(sender: "  ", body: "x", fromSelf: false)?.title == "Signal")
    c.check("notify nil fromSelf is not-self", NotificationFormat.make(sender: "A", body: "y", fromSelf: nil)?.body == "y")
}

print("")
if c.failures == 0 {
    print("PASS: all bridge decode-contract checks ok")
    exit(0)
} else {
    print("FAILED: \(c.failures) check(s) did not hold")
    exit(1)
}
