// QuillAppKitPasteboardDemo
// =========================
// Linux runtime demo proving NSPasteboard.general actually round-trips
// real data through QuillAppKit's Phase B backing. Writes a string
// with setString(_:forType:), reads it back, and reports the change
// count. On macOS this hits Apple's real NSPasteboard so it works
// identically. On Linux it goes through the wl-copy / xclip / file-
// backed tier picked at runtime.

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

        if !ok || !dataOK { exit(1) }
    }
}
