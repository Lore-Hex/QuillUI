import SwiftUI

public struct GIFImage: View {
    public init(url: URL?) {}
    public var body: some View { EmptyView() }
}

@MainActor
public final class GIFImageView: UIImageView {
    public init() {
        super.init(image: nil)
    }

    public func prepareForAnimation(withGIFData data: Data) {
        _ = data
    }

    public func startAnimatingGIF() {}
    public func stopAnimatingGIF() {}
}
