import Foundation
import Testing
@testable import QuillEnchantedCore

@Suite("Core compatibility contract matrix")
struct CoreContractMatrixTests {
    @Test("compacts titles without whitespace or newlines", arguments: titleInputs)
    func titleCompactionContracts(input: String) {
        let title = input.quillTitle(maxLength: 32)

        #expect(!title.isEmpty)
        #expect(!title.contains("\n"))
        #expect(!title.contains("\r"))
        #expect(title == title.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(title.count <= 32)
    }

    @Test("cleans inline markdown markers", arguments: inlineCases)
    func inlineMarkdownContracts(testCase: TextCase) {
        #expect(MarkdownParser.cleanInline(testCase.input) == testCase.expected)
    }

    @Test("parses first structural markdown block", arguments: blockCases)
    func structuralMarkdownContracts(testCase: BlockCase) {
        let block = MarkdownParser.parse(testCase.markdown).first

        #expect(block?.kind == testCase.kind)
        #expect(block?.text == testCase.text)
    }

    @Test("parses Ollama stream content chunks", arguments: streamContentCases)
    func ollamaContentContracts(testCase: TextCase) throws {
        #expect(try OllamaStreamParser.parseLine(testCase.input) == .content(testCase.expected))
    }

    @Test("formats byte counts", arguments: byteCountCases)
    func byteCountContracts(testCase: ByteCountCase) {
        #expect(PendingImageAttachment.formatByteCount(testCase.byteCount) == testCase.expected)
    }

    @Test("accepts supported image extensions with media types", arguments: imageExtensionCases)
    func imageExtensionContracts(testCase: ImageExtensionCase) throws {
        let url = try temporaryFile(name: "sample.\(testCase.fileExtension)", bytes: [0x01, 0x02, 0x03])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let attachment = try PendingImageAttachment(fileURL: url, id: testCase.fileExtension)

        #expect(attachment.mediaType == testCase.mediaType)
        #expect(attachment.byteCount == 3)
        #expect(attachment.filename == "sample.\(testCase.fileExtension)")
    }

    @Test("rejects unsupported image extensions", arguments: unsupportedImageExtensions)
    func unsupportedImageExtensionContracts(fileExtension: String) throws {
        let url = try temporaryFile(name: "sample.\(fileExtension)", bytes: [0x01])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: ImageAttachmentError.unsupportedFileType("sample.\(fileExtension)")) {
            try PendingImageAttachment(fileURL: url)
        }
    }

    @Test("normalizes attachment paths", arguments: pathCases)
    func pathNormalizationContracts(testCase: PathCase) throws {
        let url = try #require(PendingImageAttachment.fileURL(from: testCase.rawPath))

        #expect(url.path.hasSuffix(testCase.expectedSuffix))
    }

    private func temporaryFile(name: String, bytes: [UInt8]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }
}

struct TextCase: Sendable {
    var input: String
    var expected: String
}

struct BlockCase: Sendable {
    var markdown: String
    var kind: MarkdownBlockKind
    var text: String
}

struct ByteCountCase: Sendable {
    var byteCount: Int64
    var expected: String
}

struct ImageExtensionCase: Sendable {
    var fileExtension: String
    var mediaType: String
}

struct PathCase: Sendable {
    var rawPath: String
    var expectedSuffix: String
}

private let titleInputs: [String] = [
    "",
    "   ",
    "\n\n",
    "Short title",
    "  Padded title  ",
    "First line\nSecond line",
    "First line\r\nSecond line",
    "A very long prompt that should be shortened into a compact conversation title",
    "Symbols !@#$%^&*() stay readable",
    "中文 title remains nonempty"
] + (0..<90).map { index in
    "  Generated title case \(index)\nwith continuation text that is intentionally long enough to trim  "
}

private let inlineCases: [TextCase] = [
    TextCase(input: "**bold**", expected: "bold"),
    TextCase(input: "__strong__", expected: "strong"),
    TextCase(input: "`code`", expected: "code"),
    TextCase(input: "~~gone~~", expected: "gone"),
    TextCase(input: "[QuillUI](https://example.com)", expected: "QuillUI (https://example.com)"),
    TextCase(input: "mix **bold** and `code`", expected: "mix bold and code"),
    TextCase(input: "  spaced **text**  ", expected: "spaced text"),
    TextCase(input: "[Docs](https://example.com/docs) **ship**", expected: "Docs (https://example.com/docs) ship")
] + (0..<62).map { index in
    TextCase(input: "**Generated \(index)** with `inline` markers", expected: "Generated \(index) with inline markers")
}

private let blockCases: [BlockCase] = [
    BlockCase(markdown: "# Heading", kind: .heading(level: 1), text: "Heading"),
    BlockCase(markdown: "## Heading", kind: .heading(level: 2), text: "Heading"),
    BlockCase(markdown: "###### Heading", kind: .heading(level: 6), text: "Heading"),
    BlockCase(markdown: "- Item", kind: .unorderedListItem, text: "Item"),
    BlockCase(markdown: "* Item", kind: .unorderedListItem, text: "Item"),
    BlockCase(markdown: "+ Item", kind: .unorderedListItem, text: "Item"),
    BlockCase(markdown: "1. Item", kind: .orderedListItem(number: 1), text: "Item"),
    BlockCase(markdown: "42. Item", kind: .orderedListItem(number: 42), text: "Item"),
    BlockCase(markdown: "> Quoted", kind: .quote, text: "Quoted"),
    BlockCase(markdown: "Plain paragraph", kind: .paragraph, text: "Plain paragraph")
] + (0..<40).map { index in
    BlockCase(markdown: "\(index + 1). Generated item \(index)", kind: .orderedListItem(number: index + 1), text: "Generated item \(index)")
}

private let streamContentCases: [TextCase] = (0..<70).map { index in
    let content = "chunk-\(index)"
    return TextCase(
        input: #"{"message":{"role":"assistant","content":"\#(content)"},"done":false}"#,
        expected: content
    )
}

private let byteCountCases: [ByteCountCase] = [
    ByteCountCase(byteCount: 0, expected: "0 bytes"),
    ByteCountCase(byteCount: 1, expected: "1 bytes"),
    ByteCountCase(byteCount: 1023, expected: "1023 bytes"),
    ByteCountCase(byteCount: 1024, expected: "1.0 KB"),
    ByteCountCase(byteCount: 1536, expected: "1.5 KB"),
    ByteCountCase(byteCount: 1_048_576, expected: "1.0 MB"),
    ByteCountCase(byteCount: 1_572_864, expected: "1.5 MB"),
    ByteCountCase(byteCount: 1_073_741_824, expected: "1.0 GB")
] + (1...32).map { index in
    ByteCountCase(byteCount: Int64(index * 1024), expected: "\(index).0 KB")
}

private let imageExtensionCases: [ImageExtensionCase] = [
    ImageExtensionCase(fileExtension: "gif", mediaType: "image/gif"),
    ImageExtensionCase(fileExtension: "heic", mediaType: "image/heic"),
    ImageExtensionCase(fileExtension: "jpeg", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "jpg", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "png", mediaType: "image/png"),
    ImageExtensionCase(fileExtension: "webp", mediaType: "image/webp"),
    ImageExtensionCase(fileExtension: "GIF", mediaType: "image/gif"),
    ImageExtensionCase(fileExtension: "HEIC", mediaType: "image/heic"),
    ImageExtensionCase(fileExtension: "JPEG", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "JPG", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "PNG", mediaType: "image/png"),
    ImageExtensionCase(fileExtension: "WEBP", mediaType: "image/webp")
]

private let unsupportedImageExtensions = [
    "txt", "pdf", "svg", "bmp", "tga", "mp4", "mov", "json", "xml", "html",
    "md", "csv", "zip", "tar", "gz", "swift", "heif", "avif", "ico", "psd"
]

private let pathCases: [PathCase] = [
    PathCase(rawPath: "/tmp/image.png", expectedSuffix: "/tmp/image.png"),
    PathCase(rawPath: " /tmp/spaced.jpg ", expectedSuffix: "/tmp/spaced.jpg"),
    PathCase(rawPath: "file:///tmp/file-url.webp", expectedSuffix: "/tmp/file-url.webp"),
    PathCase(rawPath: "~/picture.gif", expectedSuffix: "/picture.gif")
] + (0..<26).map { index in
    PathCase(rawPath: "/tmp/generated-\(index).png", expectedSuffix: "/tmp/generated-\(index).png")
}
