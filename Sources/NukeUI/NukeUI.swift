import SwiftUI

/// A functional NukeUI shim using native AsyncImage for Linux parity.
public struct LazyImage<Content: View>: View {
    private let url: URL?
    
    public init(url: URL?) {
        self.url = url
    }
    
    public var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentValue: .fill)
            case .failure(_):
                Color.gray.overlay(Image(systemName: "photo"))
            case .empty:
                ProgressView()
            @unknown default:
                EmptyView()
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
    func processors(_ processors: [Any]) -> Self { self }
    func priority(_ priority: Any) -> Self { self }
    func onStart(_ handler: @escaping (Any) -> Void) -> Self { self }
    func onCompletion(_ handler: @escaping (Any) -> Void) -> Self { self }
}
