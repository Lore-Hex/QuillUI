import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `FileManager` folder helpers against a real temp
/// directory: `isFolder(atPath:)` (folder vs file vs missing), and
/// `filenames` / `filePaths` listing a folder's contents.
@Suite("QuillRSCoreShim — FileManager+RSCore (folder helpers)")
struct FileManagerRSCoreTests {

    @Test("isFolder distinguishes folders, files, and missing paths")
    func isFolder() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("qrs-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let file = dir.appendingPathComponent("a.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)

        #expect(fm.isFolder(atPath: dir.path))
        #expect(!fm.isFolder(atPath: file.path))
        #expect(!fm.isFolder(atPath: dir.appendingPathComponent("nope").path))
    }

    @Test("filenames and filePaths list a folder's contents")
    func listing() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("qrs-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let sub = dir.appendingPathComponent("subdir")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)

        #expect(fm.filenames(inFolder: dir.path)?.sorted() == ["a.txt", "subdir"])

        let paths = fm.filePaths(inFolder: dir.path)
        #expect(paths?.count == 2)
        #expect(paths?.contains(file.path) == true)
        #expect(paths?.contains(sub.path) == true)
    }
}
