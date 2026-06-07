// Minimal Linux shim for kean/Nuke — the image surface DesignSystem uses.
#if os(Linux)
import Foundation
import SwiftUI

public protocol ImageProcessing {}

public enum ImageProcessors {
    public struct Resize: ImageProcessing {
        public let size: CGSize
        public init(size: CGSize) { self.size = size }
    }
}

extension ImageProcessing where Self == ImageProcessors.Resize {
    public static func resize(size: CGSize) -> ImageProcessors.Resize { .init(size: size) }
}

public enum ImageType: Equatable, Sendable {
    case gif, jpeg, png, webp, heic, other
}

public struct ImageContainer {
    public var image: Image
    public var type: ImageType?
    public var data: Data?
    public init(image: Image, type: ImageType? = nil, data: Data? = nil) {
        self.image = image; self.type = type; self.data = data
    }
}

public struct ImageRequest {
    public var url: URL?
    public var processors: [any ImageProcessing]
    public init(url: URL?, processors: [any ImageProcessing] = []) {
        self.url = url; self.processors = processors
    }
}
#endif
