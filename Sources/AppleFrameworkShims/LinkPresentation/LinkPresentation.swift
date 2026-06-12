import Foundation
@_exported import QuillFoundation

public let kUTTypeImage = "public.image"

public final class LPMetadataProvider: NSObject {
    public var shouldFetchSubresources: Bool = false
    private var isCancelled = false

    public override init() {
        super.init()
    }

    public func startFetchingMetadata(for URL: URL, completionHandler: @escaping (LPLinkMetadata?, Error?) -> Void) {
        let metadata = LPLinkMetadata()
        metadata.url = URL
        metadata.originalURL = URL
        metadata.title = URL.host ?? URL.absoluteString
        guard !isCancelled else { return }
        completionHandler(metadata, nil)
    }

    public func cancel() {
        isCancelled = true
    }
}

public final class LPLinkMetadata: NSObject {
    public var url: URL?
    public var originalURL: URL?
    public var title: String?
    public var imageProvider: Any?
}

public final class LPItemProvider: NSObject {
    private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        super.init()
    }

    public func loadFileRepresentation(forTypeIdentifier typeIdentifier: String, completionHandler: @escaping (URL?, Error?) -> Void) {
        _ = typeIdentifier
        completionHandler(fileURL, nil)
    }
}
