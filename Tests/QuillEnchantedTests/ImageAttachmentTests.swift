import Foundation
import Testing
@testable import QuillEnchantedCore

@Suite("Image attachments")
struct ImageAttachmentTests {
    @Test("accepts supported image files and base64 encodes them")
    func acceptsSupportedImages() throws {
        let url = try temporaryFile(name: "sample.png", bytes: [0x89, 0x50, 0x4E, 0x47])
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try PendingImageAttachment(fileURL: url, id: "image-1")

        #expect(attachment.filename == "sample.png")
        #expect(attachment.mediaType == "image/png")
        #expect(attachment.formattedByteCount == "4 bytes")
        #expect(try attachment.base64EncodedContent() == "iVBORw==")
    }

    @Test("rejects unsupported file types")
    func rejectsUnsupportedFiles() throws {
        let url = try temporaryFile(name: "notes.txt", bytes: [0x41])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImageAttachmentError.unsupportedFileType("notes.txt")) {
            try PendingImageAttachment(fileURL: url)
        }
    }

    @Test("normalizes file URLs and home-relative paths")
    func normalizesPaths() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/example.png")
        #expect(PendingImageAttachment.fileURL(from: fileURL.absoluteString) == fileURL)

        let homeURL = try #require(PendingImageAttachment.fileURL(from: "~/example.png"))
        #expect(homeURL.path.hasSuffix("/example.png"))
        #expect(homeURL.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    @Test("splits attachment path lists from composer input")
    func splitsAttachmentPathListsFromComposerInput() throws {
        let first = "/tmp/first.png"
        let second = URL(fileURLWithPath: "/tmp/second.jpg").absoluteString
        let third = "~/third.webp"
        let rawPaths = " \(first)\n\n\(second); \(third) "

        #expect(PendingImageAttachment.attachmentPathCandidates(from: rawPaths) == [first, second, third])
        #expect(PendingImageAttachment.attachmentPathCandidates(from: " ; \n ; \r\n ") == [])

        let urls = PendingImageAttachment.fileURLs(from: rawPaths)
        #expect(urls.map(\.path) == [
            "/tmp/first.png",
            "/tmp/second.jpg",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("third.webp").path
        ])
    }

    @Test("builds display content with attachment summary")
    func buildsDisplayContent() throws {
        let url = try temporaryFile(name: "diagram.webp", bytes: [0x52, 0x49, 0x46, 0x46])
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try PendingImageAttachment(fileURL: url, id: "diagram")
        let content = PendingImageAttachment.displayContent(prompt: "Explain this", attachments: [attachment])

        #expect(content == """
        Explain this

        [Attached images]
        - diagram.webp (4 bytes)
        """)
    }

    @Test("chooses default prompt from attachment count")
    func choosesDefaultPromptFromAttachmentCount() throws {
        let firstURL = try temporaryFile(name: "first.png", bytes: [0x01])
        let secondURL = try temporaryFile(name: "second.jpg", bytes: [0x02])
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        let first = try PendingImageAttachment(fileURL: firstURL, id: "first")
        let second = try PendingImageAttachment(fileURL: secondURL, id: "second")

        #expect(PendingImageAttachment.defaultPrompt(for: [first]) == "Describe this image.")
        #expect(PendingImageAttachment.defaultPrompt(for: [first, second]) == "Describe these images.")
    }

    @Test("stages imported files before sending")
    func stagesImportedFiles() throws {
        let url = try temporaryFile(name: "picked.jpg", bytes: [0xFF, 0xD8, 0xFF])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let stagingDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        let attachment = try PendingImageAttachment.stagedCopy(
            from: url,
            id: "picked",
            stagingDirectory: stagingDirectory
        )

        #expect(attachment.id == "picked")
        #expect(attachment.filename.hasSuffix("picked.jpg"))
        #expect(attachment.mediaType == "image/jpeg")
        #expect(attachment.fileURL != url.standardizedFileURL)
        #expect(try attachment.base64EncodedContent() == "/9j/")
    }

    @Test("stages dropped image data with a supported fallback name")
    func stagesDroppedData() throws {
        let stagingDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        let attachment = try PendingImageAttachment.stagedData(
            Data([0x89, 0x50]),
            suggestedFilename: "clipboard",
            stagingDirectory: stagingDirectory
        )

        #expect(attachment.filename.hasSuffix("dropped-image.png"))
        #expect(attachment.mediaType == "image/png")
        #expect(try attachment.base64EncodedContent() == "iVA=")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func temporaryFile(name: String, bytes: [UInt8]) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }
}
