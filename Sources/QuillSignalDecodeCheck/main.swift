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
}

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

print("")
if c.failures == 0 {
    print("PASS: all BridgeMessage decode-contract checks ok")
    exit(0)
} else {
    print("FAILED: \(c.failures) check(s) did not hold")
    exit(1)
}
