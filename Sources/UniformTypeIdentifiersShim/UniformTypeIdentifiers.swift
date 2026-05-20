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

    public init?(filenameExtension: String) {
        let filenameExtension = filenameExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard let type = Self.typesByFilenameExtension[filenameExtension] else { return nil }
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
    public static let tiff = UTType("public.tiff")!
    public static let movie = UTType("public.movie")!
    public static let mpeg4Movie = UTType("public.mpeg-4")!
    public static let audio = UTType("public.audio")!
    public static let mp3 = UTType("public.mp3")!
    public static let pdf = UTType("com.adobe.pdf")!

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
        UTType.movie.identifier: [UTType.data.identifier],
        UTType.mpeg4Movie.identifier: [UTType.movie.identifier],
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
        "mp3": .mp3
    ]
}
#endif
