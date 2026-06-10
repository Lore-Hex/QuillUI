import Foundation

public final class ImagePipeline: @unchecked Sendable {
    public static let shared = ImagePipeline()

    public let cache = ImageCache()

    public init() {}
}

public final class ImageCache: @unchecked Sendable {
    public init() {}

    public func cachedData(for request: ImageRequest) -> Data? {
        _ = request
        return nil
    }

    public func removeAll() {}
}

public struct ImageRequest {
    public let url: URL?
    public let processors: [ImageProcessors.Resize]

    public init(url: URL?, processors: [ImageProcessors.Resize] = []) {
        self.url = url
        self.processors = processors
    }
}

public enum ImageProcessors {
    public struct Resize: Sendable {
        public let size: CGSize
        public init(size: CGSize) {
            self.size = size
        }

        public static func resize(size: CGSize) -> Resize {
            Resize(size: size)
        }
    }

    public static func resize(size: CGSize) -> Resize {
        Resize(size: size)
    }
}
