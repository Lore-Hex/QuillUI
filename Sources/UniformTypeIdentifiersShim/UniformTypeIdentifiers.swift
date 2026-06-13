// Linux UTI shim. Real UniformTypeIdentifiers ships on Apple SDKs.
#if os(macOS) || os(iOS) || os(visionOS)
@_exported import UniformTypeIdentifiers
#else
import Foundation

public struct UTType: Hashable, Sendable {
    public var identifier: String

    public init?(_ identifier: String) {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }
        self.identifier = identifier
    }

    public init?(filenameExtension: String, conformingTo supertype: UTType? = nil) {
        guard
            let filenameExtension = Self.normalizedFilenameExtension(filenameExtension),
            let type = Self.typesByFilenameExtension[filenameExtension]
        else { return nil }

        if let supertype, !type.conforms(to: supertype) {
            return nil
        }

        self = type
    }

    /// Best-effort MIME-type -> UTType lookup over the known type table (used by
    /// MimeTypeUtil.utiTypeForMimeType). Not the full UTI MIME database; covers the
    /// types SSK references. Returns nil for unknown MIME strings, matching Apple.
    public init?(mimeType: String, conformingTo supertype: UTType? = nil) {
        guard
            let mimeType = Self.normalizedMIMEType(mimeType),
            let type = Self.typesByMIMEType[mimeType]
        else { return nil }

        if let supertype, !type.conforms(to: supertype) {
            return nil
        }

        self = type
    }

    public static let item = UTType("public.item")!
    public static let content = UTType("public.content")!
    public static let data = UTType("public.data")!
    public static let text = UTType("public.text")!
    public static let plainText = UTType("public.plain-text")!
    public static let utf8PlainText = UTType("public.utf8-plain-text")!
    public static let rtf = UTType("public.rtf")!
    public static let html = UTType("public.html")!
    public static let xml = UTType("public.xml")!
    public static let json = UTType("public.json")!
    public static let url = UTType("public.url")!
    public static let fileURL = UTType("public.file-url")!
    public static let directory = UTType("public.directory")!
    public static let folder = UTType("public.folder")!
    public static let image = UTType("public.image")!
    public static let png = UTType("public.png")!
    public static let jpeg = UTType("public.jpeg")!
    public static let dng = UTType("com.adobe.raw-image")!
    public static let tiff = UTType("public.tiff")!
    public static let gif = UTType("com.compuserve.gif")!
    public static let heic = UTType("public.heic")!
    public static let heif = UTType("public.heif")!
    public static let webP = UTType("org.webmproject.webp")!
    public static let jpegxl = UTType("public.jpeg-xl")!
    public static let vCard = UTType("public.vcard")!
    public static let movie = UTType("public.movie")!
    public static let video = UTType("public.video")!
    public static let mpeg4Movie = UTType("public.mpeg-4")!
    public static let quickTimeMovie = UTType("com.apple.quicktime-movie")!
    public static let audio = UTType("public.audio")!
    public static let mp3 = UTType("public.mp3")!
    public static let pdf = UTType("com.adobe.pdf")!

    public var preferredFilenameExtension: String? {
        Self.preferredFilenameExtensionsByIdentifier[identifier]
    }

    public var preferredMIMEType: String? {
        Self.preferredMIMETypesByIdentifier[identifier]
    }

    public var localizedDescription: String? {
        Self.localizedDescriptionsByIdentifier[identifier]
    }

    public func conforms(to other: UTType) -> Bool {
        if self == other { return true }

        var pending = Array(Self.parentIdentifiersByIdentifier[identifier] ?? [])
        var visited = Set<String>()
        while let candidate = pending.popLast() {
            if candidate == other.identifier { return true }
            guard visited.insert(candidate).inserted else { continue }
            pending.append(contentsOf: Self.parentIdentifiersByIdentifier[candidate] ?? [])
        }
        return false
    }

    private static let parentIdentifiersByIdentifier: [String: Set<String>] = [
        UTType.content.identifier: [UTType.item.identifier],
        UTType.data.identifier: [UTType.content.identifier],
        UTType.text.identifier: [UTType.data.identifier],
        UTType.plainText.identifier: [UTType.text.identifier],
        UTType.utf8PlainText.identifier: [UTType.plainText.identifier],
        UTType.rtf.identifier: [UTType.text.identifier],
        UTType.html.identifier: [UTType.text.identifier],
        UTType.xml.identifier: [UTType.text.identifier],
        UTType.json.identifier: [UTType.text.identifier],
        UTType.url.identifier: [UTType.data.identifier],
        UTType.fileURL.identifier: [UTType.url.identifier],
        UTType.directory.identifier: [UTType.item.identifier],
        UTType.folder.identifier: [UTType.directory.identifier],
        UTType.image.identifier: [UTType.data.identifier],
        UTType.png.identifier: [UTType.image.identifier],
        UTType.jpeg.identifier: [UTType.image.identifier],
        UTType.tiff.identifier: [UTType.image.identifier],
        UTType.gif.identifier: [UTType.image.identifier],
        UTType.heic.identifier: [UTType.image.identifier],
        UTType.heif.identifier: [UTType.image.identifier],
        UTType.webP.identifier: [UTType.image.identifier],
        UTType.movie.identifier: [UTType.data.identifier],
        UTType.video.identifier: [UTType.movie.identifier],
        UTType.mpeg4Movie.identifier: [UTType.video.identifier],
        UTType.quickTimeMovie.identifier: [UTType.video.identifier],
        UTType.audio.identifier: [UTType.data.identifier],
        UTType.mp3.identifier: [UTType.audio.identifier],
        UTType.pdf.identifier: [UTType.data.identifier]
    ]

    private static let typesByFilenameExtension: [String: UTType] = [
        "png": .png,
        "jpeg": .jpeg,
        "jpg": .jpeg,
        "tiff": .tiff,
        "tif": .tiff,
        "gif": .gif,
        "heic": .heic,
        "heif": .heif,
        "webp": .webP,
        "html": .html,
        "htm": .html,
        "txt": .plainText,
        "text": .plainText,
        "rtf": .rtf,
        "xml": .xml,
        "url": .url,
        "pdf": .pdf,
        "json": .json,
        "mp4": .mpeg4Movie,
        "mov": .quickTimeMovie,
        "mp3": .mp3
    ]

    private static let preferredFilenameExtensionsByIdentifier: [String: String] = [
        UTType.plainText.identifier: "txt",
        UTType.utf8PlainText.identifier: "txt",
        UTType.rtf.identifier: "rtf",
        UTType.html.identifier: "html",
        UTType.xml.identifier: "xml",
        UTType.json.identifier: "json",
        UTType.url.identifier: "url",
        UTType.png.identifier: "png",
        UTType.jpeg.identifier: "jpeg",
        UTType.tiff.identifier: "tiff",
        UTType.gif.identifier: "gif",
        UTType.heic.identifier: "heic",
        UTType.heif.identifier: "heif",
        UTType.webP.identifier: "webp",
        UTType.mpeg4Movie.identifier: "mp4",
        UTType.quickTimeMovie.identifier: "mov",
        UTType.mp3.identifier: "mp3",
        UTType.pdf.identifier: "pdf"
    ]

    private static let preferredMIMETypesByIdentifier: [String: String] = [
        UTType.plainText.identifier: "text/plain",
        UTType.utf8PlainText.identifier: "text/plain",
        UTType.rtf.identifier: "application/rtf",
        UTType.html.identifier: "text/html",
        UTType.xml.identifier: "application/xml",
        UTType.json.identifier: "application/json",
        UTType.png.identifier: "image/png",
        UTType.jpeg.identifier: "image/jpeg",
        UTType.tiff.identifier: "image/tiff",
        UTType.gif.identifier: "image/gif",
        UTType.heic.identifier: "image/heic",
        UTType.heif.identifier: "image/heif",
        UTType.webP.identifier: "image/webp",
        UTType.mpeg4Movie.identifier: "video/mp4",
        UTType.quickTimeMovie.identifier: "video/quicktime",
        UTType.mp3.identifier: "audio/mpeg",
        UTType.pdf.identifier: "application/pdf"
    ]

    private static let localizedDescriptionsByIdentifier: [String: String] = [
        UTType.item.identifier: "item",
        UTType.content.identifier: "content",
        UTType.data.identifier: "data",
        UTType.text.identifier: "text",
        UTType.plainText.identifier: "plain text",
        UTType.utf8PlainText.identifier: "UTF-8 plain text",
        UTType.rtf.identifier: "rich text",
        UTType.html.identifier: "HTML",
        UTType.xml.identifier: "XML",
        UTType.json.identifier: "JSON",
        UTType.url.identifier: "URL",
        UTType.fileURL.identifier: "file URL",
        UTType.directory.identifier: "directory",
        UTType.folder.identifier: "folder",
        UTType.image.identifier: "image",
        UTType.png.identifier: "PNG image",
        UTType.jpeg.identifier: "JPEG image",
        UTType.tiff.identifier: "TIFF image",
        UTType.gif.identifier: "GIF image",
        UTType.heic.identifier: "HEIC image",
        UTType.heif.identifier: "HEIF image",
        UTType.webP.identifier: "WebP image",
        UTType.movie.identifier: "movie",
        UTType.video.identifier: "video",
        UTType.mpeg4Movie.identifier: "MPEG-4 movie",
        UTType.quickTimeMovie.identifier: "QuickTime movie",
        UTType.audio.identifier: "audio",
        UTType.mp3.identifier: "MP3 audio",
        UTType.pdf.identifier: "PDF"
    ]

    private static let typesByMIMEType: [String: UTType] = [
        "text/plain": .plainText,
        "application/rtf": .rtf,
        "text/html": .html,
        "application/xml": .xml,
        "text/xml": .xml,
        "application/json": .json,
        "image/png": .png,
        "image/jpeg": .jpeg,
        "image/jpg": .jpeg,
        "image/tiff": .tiff,
        "image/gif": .gif,
        "image/heic": .heic,
        "image/heif": .heif,
        "image/webp": .webP,
        "video/mp4": .mpeg4Movie,
        "audio/mpeg": .mp3,
        "audio/mp3": .mp3,
        "application/pdf": .pdf
    ]

    private static func normalizedFilenameExtension(_ filenameExtension: String) -> String? {
        let normalized = filenameExtension.lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedMIMEType(_ mimeType: String) -> String? {
        // Strip any parameters (e.g. "text/plain; charset=utf-8") then normalize.
        let base = mimeType.split(separator: ";", maxSplits: 1).first.map(String.init) ?? mimeType
        let normalized = base.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
#endif
