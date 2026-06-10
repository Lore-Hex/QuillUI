import SwiftUI
import Nuke

public enum ImageContainerType: Sendable {
    case gif
    case image
}

public struct ImageContainer: Sendable {
    public let type: ImageContainerType
    public let data: Data?

    public init(type: ImageContainerType = .image, data: Data? = nil) {
        self.type = type
        self.data = data
    }
}

public struct LazyImageState {
    public let image: Image?
    public let imageContainer: ImageContainer?
    public let error: (any Error)?
    public let isLoading: Bool

    public init(
        image: Image? = nil,
        imageContainer: ImageContainer? = nil,
        error: (any Error)? = nil,
        isLoading: Bool = true
    ) {
        self.image = image
        self.imageContainer = imageContainer
        self.error = error
        self.isLoading = isLoading
    }
}

/// A functional NukeUI shim using native AsyncImage for Linux parity.
public struct LazyImage<Content: View>: View {
    private let url: URL?
    private let content: (LazyImageState) -> Content
    
    public init(url: URL?) where Content == AnyView {
        self.url = url
        self.content = { state in
            if let image = state.image {
                return AnyView(image.resizable().aspectRatio(contentValue: .fill))
            }
            if state.error != nil {
                return AnyView(Color.gray.overlay(Image(systemName: "photo")))
            }
            return AnyView(ProgressView())
        }
    }

    public init(url: URL?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.url = url
        self.content = content
    }

    public init(
        url: URL?,
        transaction: Transaction,
        @ViewBuilder content: @escaping (LazyImageState) -> Content
    ) {
        _ = transaction
        self.url = url
        self.content = content
    }

    public init(request: ImageRequest, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.url = request.url
        self.content = content
    }
    
    public var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                content(LazyImageState(image: image, imageContainer: ImageContainer(type: .image), isLoading: false))
            case .failure(_):
                content(LazyImageState(error: phase.error, isLoading: false))
            case .empty:
                content(LazyImageState())
            @unknown default:
                content(LazyImageState())
            }
        }
    }
}

private extension Image {
    func aspectRatio(contentValue: ContentMode) -> some View {
        self.resizable().aspectRatio(contentMode: contentValue)
    }
}

public extension LazyImage {
    func processors(_ processors: [ImageProcessors.Resize]) -> Self { self }
    func priority(_ priority: Any) -> Self { self }
    func onStart(_ handler: @escaping (Any) -> Void) -> Self { self }
    func onCompletion(_ handler: @escaping (Any) -> Void) -> Self { self }
}
