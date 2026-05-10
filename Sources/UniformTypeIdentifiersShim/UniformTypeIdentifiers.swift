// Linux UTI shim. Real UniformTypeIdentifiers ships on Apple SDKs.
#if os(macOS) || os(iOS) || os(visionOS)
@_exported import UniformTypeIdentifiers
#else
import Foundation

public struct UTType: Hashable, Sendable {
    public var identifier: String
    public init?(_ identifier: String) { self.identifier = identifier }
    public init(filenameExtension: String) { self.identifier = filenameExtension }

    public static let png = UTType("public.png")!
    public static let jpeg = UTType("public.jpeg")!
    public static let html = UTType("public.html")!
    public static let plainText = UTType("public.plain-text")!
    public static let url = UTType("public.url")!
    public static let image = UTType("public.image")!
    public static let movie = UTType("public.movie")!
    public static let audio = UTType("public.audio")!
    public static let pdf = UTType("com.adobe.pdf")!
    public static let json = UTType("public.json")!
}
#endif
