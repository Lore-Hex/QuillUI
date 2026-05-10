// QuillAppKitPasteboardDemo
// =========================
// Linux runtime demo proving Phase B AppKit backings actually flow
// real data on Linux:
//
//   • NSPasteboard.general — round-trips a string and binary data.
//     Tier picked at runtime: wl-copy/wl-paste on Wayland, xclip on
//     X11, file-backed at \$XDG_RUNTIME_DIR otherwise.
//   • NSWorkspace.shared — xdg-open detection via xdg-mime.
//   • NSSound.beep() — terminal bell.
//
// On macOS the real frameworks win via the SDK and this demo target
// isn't built (it's gated to `os(Linux)` in Package.swift).

import AppKit
import Foundation

@main
struct PasteboardDemo {
    static func main() {
        let pb = NSPasteboard.general
        let initialChange = pb.changeCount

        let payload = "Hello from QuillAppKit @ \(Date()) — pid \(ProcessInfo.processInfo.processIdentifier)"
        print("[write] \(payload)")
        _ = pb.clearContents()
        _ = pb.setString(payload, forType: .string)

        let readBack = pb.string(forType: .string)
        print("[read]  \(readBack ?? "<nil>")")
        print("[change] \(initialChange) → \(pb.changeCount)")

        let ok = readBack == payload
        let typeCount = pb.types()?.count ?? 0
        print("[types] \(typeCount) recorded types")
        print("[result] \(ok ? "✅ round-trip succeeded" : "❌ round-trip mismatch")")

        // Also exercise data path
        let bytes = Data("binary-payload".utf8)
        _ = pb.setData(bytes, forType: NSPasteboard.PasteboardType(rawValue: "com.quill.test"))
        let bytesBack = pb.data(forType: NSPasteboard.PasteboardType(rawValue: "com.quill.test"))
        let dataOK = bytesBack == bytes
        print("[binary] \(dataOK ? "✅ data round-trip" : "❌ data mismatch")")

        // NSWorkspace tier-2 check: just probe that the API doesn't
        // explode and that xdg-open detection runs. We don't actually
        // dispatch a browser open because there's no display in the VM.
        let ws = NSWorkspace.shared
        let appURL = ws.urlForApplication(toOpen: URL(string: "https://example.com")!)
        print("[workspace] urlForApplication(https) → \(appURL?.lastPathComponent ?? "<nil>")")

        // NSSound.beep — emits BEL to stderr. Harmless; just prove the
        // call executes without crashing.
        NSSound.beep()
        print("[sound] NSSound.beep() emitted")

        if !ok || !dataOK { exit(1) }
    }
}
