import Foundation
import Testing
@testable import QuillFoundation

@Suite("QuillFoundation FileManager app group clone")
struct FileManagerAppGroupTests {
    @Test("Linux app-group containers are stable writable directories")
    func linuxAppGroupContainersAreStableWritableDirectories() throws {
        #if os(Linux)
        let group = "group.quillui.tests.\(UUID().uuidString)"
        let fileManager = FileManager.default

        let firstURL = try #require(fileManager.containerURL(forSecurityApplicationGroupIdentifier: group))
        let secondURL = try #require(fileManager.containerURL(forSecurityApplicationGroupIdentifier: group))
        defer { try? fileManager.removeItem(at: firstURL) }

        #expect(firstURL == secondURL)
        #expect(firstURL.lastPathComponent.hasPrefix("group.quillui.tests."))

        var isDirectory = ObjCBool(false)
        #expect(fileManager.fileExists(atPath: firstURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let marker = firstURL.appendingPathComponent("marker.txt")
        try Data("ok".utf8).write(to: marker)
        #expect(try String(contentsOf: marker) == "ok")
        #else
        #expect(Bool(true))
        #endif
    }
}
