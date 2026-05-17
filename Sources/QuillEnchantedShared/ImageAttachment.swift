import Foundation
import QuillEnchantedData

public enum ImageAttachmentError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedFileType(String)
    case unreadableFile(String)
    case fileTooLarge(String, Int64)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let name):
            return "\(name) is not a supported image attachment."
        case .unreadableFile(let path):
            return "Could not read image attachment at \(path)."
        case .fileTooLarge(let name, let byteCount):
            return "\(name) is too large to attach (\(PendingImageAttachment.formatByteCount(byteCount)))."
        }
    }
}

public struct PendingImageAttachment: Identifiable, Hashable, Sendable {
    public static let maxByteCount: Int64 = 20 * 1024 * 1024
    public static let supportedExtensions: Set<String> = ["gif", "heic", "jpeg", "jpg", "png", "tif", "tiff", "webp"]

    public var id: String
    public var fileURL: URL
    public var filename: String
    public var byteCount: Int64
    public var mediaType: String

    public init(fileURL: URL, id: String = UUID().uuidString) throws {
        let resolvedURL = fileURL.standardizedFileURL
        let filename = resolvedURL.lastPathComponent
        let fileExtension = resolvedURL.pathExtension.lowercased()

        guard Self.supportedExtensions.contains(fileExtension) else {
            throw ImageAttachmentError.unsupportedFileType(filename.isEmpty ? resolvedURL.path : filename)
        }

        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedURL.path),
            let byteCount = attributes[.size] as? NSNumber
        else {
            throw ImageAttachmentError.unreadableFile(resolvedURL.path)
        }

        let size = byteCount.int64Value
        guard size <= Self.maxByteCount else {
            throw ImageAttachmentError.fileTooLarge(filename, size)
        }

        self.id = id
        self.fileURL = resolvedURL
        self.filename = filename
        self.byteCount = size
        self.mediaType = Self.mediaType(forExtension: fileExtension)
    }

    public var formattedByteCount: String {
        Self.formatByteCount(byteCount)
    }

    public func base64EncodedContent() throws -> String {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImageAttachmentError.unreadableFile(fileURL.path)
        }
        return data.base64EncodedString()
    }

    public static func stagedCopy(
        from sourceURL: URL,
        id: String = UUID().uuidString,
        stagingDirectory: URL? = nil
    ) throws -> PendingImageAttachment {
        let candidate = try PendingImageAttachment(fileURL: sourceURL, id: id)
        let destination = try stagedURL(for: candidate.filename, stagingDirectory: stagingDirectory)
        do {
            try FileManager.default.copyItem(at: candidate.fileURL, to: destination)
        } catch {
            throw ImageAttachmentError.unreadableFile(candidate.fileURL.path)
        }
        return try PendingImageAttachment(fileURL: destination, id: id)
    }

    public static func stagedData(
        _ data: Data,
        suggestedFilename: String = "dropped-image.png",
        id: String = UUID().uuidString,
        stagingDirectory: URL? = nil
    ) throws -> PendingImageAttachment {
        let filename = normalizedSupportedFilename(suggestedFilename)
        guard data.count <= maxByteCount else {
            throw ImageAttachmentError.fileTooLarge(filename, Int64(data.count))
        }

        let destination = try stagedURL(for: filename, stagingDirectory: stagingDirectory)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ImageAttachmentError.unreadableFile(destination.path)
        }
        return try PendingImageAttachment(fileURL: destination, id: id)
    }

    public static func attachmentPathCandidates(from rawPaths: String) -> [String] {
        rawPaths
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ";")))
            .compactMap(\.quillTrimmedNonEmpty)
    }

    public static func fileURLs(from rawPaths: String) -> [URL] {
        attachmentPathCandidates(from: rawPaths).compactMap(fileURL(from:))
    }

    public static func fileURL(from rawPath: String) -> URL? {
        guard let trimmed = rawPath.quillTrimmedNonEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }

        let expandedPath: String
        if trimmed == "~" {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
        } else if trimmed.hasPrefix("~/") {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .path
        } else {
            expandedPath = trimmed
        }

        return URL(fileURLWithPath: expandedPath)
    }

    public static func attachmentSummary(for attachments: [PendingImageAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        let lines = attachments.map { "- \($0.filename) (\($0.formattedByteCount))" }
        return "[Attached images]\n" + lines.joined(separator: "\n")
    }

    public static func displayContent(prompt: String, attachments: [PendingImageAttachment]) -> String {
        guard !attachments.isEmpty else { return prompt }
        return [prompt, attachmentSummary(for: attachments)]
            .compactMap(\.quillTrimmedNonEmpty)
            .joined(separator: "\n\n")
    }

    public static func defaultPrompt(for attachments: [PendingImageAttachment]) -> String {
        attachments.count == 1 ? "Describe this image." : "Describe these images."
    }

    public static func formatByteCount(_ byteCount: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var value = Double(byteCount)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(byteCount) bytes"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    private static func mediaType(forExtension fileExtension: String) -> String {
        switch fileExtension {
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "jpeg", "jpg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "tif", "tiff":
            return "image/tiff"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }

    private static func stagedURL(for filename: String, stagingDirectory: URL? = nil) throws -> URL {
        let directory = try attachmentsDirectory(override: stagingDirectory)
        let safeFilename = filename
            .split(separator: "/")
            .last
            .map(String.init) ?? "image.png"
        return directory.appendingPathComponent("\(UUID().uuidString)-\(safeFilename)")
    }

    private static func attachmentsDirectory(override: URL? = nil) throws -> URL {
        let directory = override ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quillui", isDirectory: true)
            .appendingPathComponent("enchanted", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func normalizedSupportedFilename(_ filename: String) -> String {
        let fallback = "dropped-image.png"
        let candidate = filename.quillTrimmedNonEmpty ?? fallback
        let url = URL(fileURLWithPath: candidate)
        return supportedExtensions.contains(url.pathExtension.lowercased()) ? url.lastPathComponent : fallback
    }
}
