import Foundation
import Testing
@testable import QuillSourceLowering

/// Covers the file-walk path that the `quill-lower-appkit` CLI drives
/// (`AppKitLowering.lowerInPlace`). Kept in its own file so it doesn't collide
/// with the unit/generation suite while related lowering PRs are in flight.
@Suite("AppKit lowering — in-place file walk (quill-lower-appkit CLI path)")
struct AppKitLoweringInPlaceTests {
    @Test("lowerInPlace rewrites .swift files and reports the count")
    func lowerInPlaceRewrites() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-lower-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let swiftFile = tmp.appendingPathComponent("VC.swift")
        try "class VC { @objc func tap() {} }".write(to: swiftFile, atomically: true, encoding: .utf8)
        // A non-Swift file must be left untouched.
        let other = tmp.appendingPathComponent("notes.txt")
        try "@objc keep me".write(to: other, atomically: true, encoding: .utf8)

        let visited = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        #expect(visited == 1)

        let lowered = try String(contentsOf: swiftFile, encoding: .utf8)
        #expect(!lowered.contains("@objc"))

        let untouched = try String(contentsOf: other, encoding: .utf8)
        #expect(untouched == "@objc keep me")
    }

    @Test("lowerInPlace is a no-op (no write) when a file needs no lowering")
    func lowerInPlaceNoOpUnchanged() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-lower-noop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let swiftFile = tmp.appendingPathComponent("Plain.swift")
        let original = "struct Plain { let x = 1 }\n"
        try original.write(to: swiftFile, atomically: true, encoding: .utf8)

        let visited = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        #expect(visited == 1)
        #expect(try String(contentsOf: swiftFile, encoding: .utf8) == original)
    }
}
