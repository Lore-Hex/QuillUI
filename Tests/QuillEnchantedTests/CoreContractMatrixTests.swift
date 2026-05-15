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

    @Test("Enchanted Qt native target stays isolated from GTK graph")
    func enchantedQtNativeTargetContracts() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let qtMain = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQt/main.swift"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let sharedPrompts = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedShared/QuillEnchantedShared.swift"),
            encoding: .utf8
        )
        let header = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/include/CQuillQt6WidgetsShim.h"),
            encoding: .utf8
        )
        let nativeShim = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillEnchantedQt6Widgets.cpp"),
            encoding: .utf8
        )
        let nativeSupport = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillQtWidgetsSupport.hpp"),
            encoding: .utf8
        )

        #expect(manifest.contains(".init(product: \"quill-enchanted\", target: \"QuillEnchanted\", qtPath: \"Sources/QuillEnchantedQt\", qtRuntime: .enchantedQtNative)"))
        #expect(manifest.contains("path: \"Sources/QuillEnchantedQt\""))
        #expect(manifest.contains("QuillEnchantedQtNativeRuntime"))
        #expect(manifest.contains("nativeQt: [\"QuillEnchantedQtNativeRuntime\"]"))
        #expect(manifest.contains(".define(\"QUILLUI_ENCHANTED_QT_NATIVE_BACKEND\")"))
        #expect(manifest.contains("name: \"QuillEnchantedShared\""))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"QuillUI\", \"QuillData\", \"QuillFoundation\", \"CSQLite\"]"))
        #expect(manifest.contains("name: \"QuillEnchantedQtNativeRuntime\""))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(qtMain.contains("#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND"))
        #expect(qtMain.contains("QuillEnchantedQtNativeApp.run()"))
        #expect(qtMain.contains("QuillQtApp.run(QuillEnchantedQtApp.self)"))
        #expect(runtime.contains("import QuillEnchantedShared"))
        #expect(runtime.contains("QuillEnchantedQtSnapshot.preview"))
        #expect(runtime.contains("quill_enchanted_qt_run_app_json"))
        #expect(runtime.contains("windowTitle: \"Quill Enchanted\""))
        #expect(runtime.contains("sidebarSubtitle: \"QuillUI Linux preview\""))
        #expect(runtime.contains("selectedModel: \"llama3.1:8b\""))
        #expect(runtime.contains("emptyStateTitle: \"Ask your local model\""))
        #expect(runtime.contains("emptyStateSubtitle: \"This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.\""))
        #expect(runtime.contains("prompts: EnchantedPromptCatalog.emptyConversationTitles"))
        #expect(runtime.contains("var messages: [Message]? = nil"))
        #expect(runtime.contains("messages: attachmentConversationMessages"))
        #expect(runtime.contains("canvasColor: \"#F6F7F2\""))
        for prompt in enchantedEmptyConversationPrompts {
            #expect(sharedPrompts.contains(prompt))
        }
        #expect(header.contains("quill_enchanted_qt_run_app_json"))
        #expect(nativeShim.contains("#include \"QuillQtWidgetsSupport.hpp\""))
        #expect(nativeShim.contains("using PromptAction = std::function<void(const QString &)>;"))
        #expect(nativeShim.contains("QComboBox"))
        #expect(nativeShim.contains("QListWidget"))
        #expect(nativeShim.contains("QPlainTextEdit"))
        #expect(nativeShim.contains("QScrollArea"))
        #expect(nativeShim.contains("styleValue(style, \"canvasColor\", \"#F6F7F2\")"))
        #expect(nativeShim.contains("intValue(style, \"sidebarWidth\", 300)"))
        #expect(nativeShim.contains("selectedConversationMessages("))
        #expect(nativeShim.contains("QString modelStatusText(const QString &selectedModel)"))
        #expect(nativeShim.contains("return QStringLiteral(\"Choose a local model to begin\")"))
        #expect(nativeShim.contains("modelStatusText(stringValue(payload, \"selectedModel\"))"))
        #expect(nativeShim.contains("QString messageRoleTitle(const QString &role)"))
        #expect(nativeShim.contains("return QStringLiteral(\"You\")"))
        #expect(nativeShim.contains("return QStringLiteral(\"Enchanted\")"))
        #expect(nativeShim.contains("return QStringLiteral(\"System\")"))
        #expect(nativeShim.contains("label(messageRoleTitle(role), QStringLiteral(\"messageRole\"))"))
        #expect(!nativeShim.contains("role.toUpper()"))
        #expect(nativeShim.contains("emptyStateTitle"))
        #expect(nativeShim.contains("emptyStateSubtitle"))
        #expect(nativeShim.contains("promptAction(prompt)"))
        #expect(nativeShim.contains("appendUserMessage(promptEditor->toPlainText())"))
        #expect(nativeShim.contains("renderMessageSet(selectedMessages)"))
        #expect(nativeShim.contains("renderMessages("))
        #expect(nativeShim.contains("QObject::connect(sendButton"))
        #expect(nativeSupport.contains("inline void clearLayout(QLayout *layout)"))
        #expect(nativeSupport.contains("inline bool parseJsonObjectPayload("))
        #expect(nativeSupport.contains("inline QByteArray executableNameBytes("))
        #expect(nativeSupport.contains("inline QSize minimumWindowSize("))
        #expect(nativeSupport.contains("inline QSize defaultWindowSize("))
        #expect(nativeSupport.contains("%s: invalid payload JSON at offset %lld: %s\\n"))
        #expect(nativeShim.contains("parseJsonObjectPayload("))
        #expect(nativeShim.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-enchanted-qt\")"))
        #expect(nativeShim.contains("executableName.constData()"))
        #expect(nativeShim.contains("QuillQtWidgets::minimumWindowSize(payload, 980, 680)"))
        #expect(nativeShim.contains("QuillQtWidgets::defaultWindowSize(payload, minimumWindowSize)"))
        #expect(!nativeShim.contains("QSize resolvedMinimumWindowSize"))
        #expect(!nativeShim.contains("QSize resolvedDefaultWindowSize"))
        #expect(nativeShim.contains("clearLayout(messageLayout)"))
        #expect(!nativeShim.contains("void clearLayout(QLayout *layout)"))
    }

    private func temporaryFile(name: String, bytes: [UInt8]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            let sources = directory.appendingPathComponent("Sources")
            if FileManager.default.fileExists(atPath: manifest.path)
                && FileManager.default.fileExists(atPath: sources.path)
            {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CoreContractMatrixTestError.packageRootNotFound
    }
}

private enum CoreContractMatrixTestError: Error {
    case packageRootNotFound
}

private let enchantedEmptyConversationPrompts: [String] = [
    "Summarize the tradeoffs in moving a SwiftUI app to Linux.",
    "Draft a private local assistant workflow for a small team.",
    "Explain how Ollama model selection should work in a desktop app.",
    "Write a checklist for shipping an open-source Swift package."
]

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
