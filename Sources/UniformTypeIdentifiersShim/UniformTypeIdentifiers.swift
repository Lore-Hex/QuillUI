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

    public static let png = UTType("public.png")!
    public static let jpeg = UTType("public.jpeg")!
    public static let tiff = UTType("public.tiff")!
    public static let html = UTType("public.html")!
    public static let plainText = UTType("public.plain-text")!
    public static let url = UTType("public.url")!
    public static let image = UTType("public.image")!
    public static let movie = UTType("public.movie")!
    public static let audio = UTType("public.audio")!
    public static let pdf = UTType("com.adobe.pdf")!
    public static let json = UTType("public.json")!

    public func conforms(to other: UTType) -> Bool {
        if self == other { return true }
        return Self.parentIdentifiersByIdentifier[identifier]?.contains(other.identifier) == true
    }

    private static let parentIdentifiersByIdentifier: [String: Set<String>] = [
        UTType.png.identifier: [UTType.image.identifier],
        UTType.jpeg.identifier: [UTType.image.identifier],
        UTType.tiff.identifier: [UTType.image.identifier]
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
        "url": .url,
        "pdf": .pdf,
        "json": .json
    ]
}
#endif
