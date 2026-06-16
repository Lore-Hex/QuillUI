#if !(os(macOS) || os(iOS) || os(visionOS))
import Foundation

public extension URLResourceKey {
    static let contentTypeKey = URLResourceKey("NSURLContentTypeKey")
}

public extension URLResourceValues {
    var contentType: UTType? {
        get { nil }
        set { _ = newValue }
    }
}
#endif
