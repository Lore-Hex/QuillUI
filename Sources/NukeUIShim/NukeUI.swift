// Minimal Linux shim for kean/NukeUI — LazyImage backed by SwiftOpenUI AsyncImage.
#if os(Linux)
import Foundation
import SwiftUI
import SwiftOpenUI
import Nuke

public struct LazyImageState {
    public var image: Image?
    public var imageContainer: ImageContainer?
    public init(image: Image? = nil, imageContainer: ImageContainer? = nil) {
        self.image = image; self.imageContainer = imageContainer
    }
}

public struct LazyImage<Content: View>: View {
    private let url: URL?
    private let content: (LazyImageState) -> Content

    public init(url: URL?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.url = url; self.content = content
    }
    public init(request: ImageRequest?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.url = request?.url; self.content = content
    }

    public var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                content(LazyImageState(image: image, imageContainer: ImageContainer(image: image, type: nil)))
            default:
                content(LazyImageState(image: nil, imageContainer: nil))
            }
        }
    }

    // Processors are applied by the real Nuke pipeline; on Linux AsyncImage
    // loads the image directly, so this is a no-op that preserves the chain.
    public func processors(_ processors: [any ImageProcessing]) -> LazyImage { self }
}
#endif
