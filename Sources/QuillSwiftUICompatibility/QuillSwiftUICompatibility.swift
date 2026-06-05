@_exported import SwiftOpenUI
import QuillFoundation

#if os(Linux)
/// Canonical Linux image type exposed through the SwiftUI shim.
///
/// SwiftOpenUI keeps its renderer image as a byte-backed value type, but the
/// lowered AppKit/UIKit compatibility layers use `RSImage` for `NSImage` and
/// `UIImage`. Exporting `PlatformImage` as `RSImage` keeps genuine SwiftUI
/// source like `return ImageRenderer(content: view).nsImage` type-compatible
/// with app code that returns `NSImage?` / `PlatformImage?`.
public typealias PlatformImage = RSImage

/// SwiftUI-compatible image renderer that bridges SwiftOpenUI's rendered bytes
/// into QuillFoundation's canonical app image container.
public final class ImageRenderer<Content: View> {
    private let renderer: SwiftOpenUI.ImageRenderer<Content>

    public var content: Content {
        get { renderer.content }
        set { renderer.content = newValue }
    }

    public var scale: CGFloat {
        get { renderer.scale }
        set { renderer.scale = newValue }
    }

    public var proposedSize: CGSize? {
        get { renderer.proposedSize }
        set { renderer.proposedSize = newValue }
    }

    public init(content: Content) {
        self.renderer = SwiftOpenUI.ImageRenderer(content: content)
    }

    public var platformImage: PlatformImage? {
        bridge(renderer.platformImage)
    }

    public var nsImage: PlatformImage? {
        bridge(renderer.nsImage)
    }

    public var uiImage: PlatformImage? {
        bridge(renderer.uiImage)
    }

    public var cgImage: PlatformImage? {
        bridge(renderer.cgImage)
    }

    private func bridge(_ image: SwiftOpenUI.PlatformImage?) -> PlatformImage? {
        guard let image else { return nil }
        return PlatformImage(platformImage: image)
    }
}

public extension RSImage {
    convenience init?(platformImage: SwiftOpenUI.PlatformImage) {
        guard let data = platformImage.data else { return nil }
        self.init(data: data)
    }
}

// Upstream SwiftUI exposes `Font.Weight` as a nested type. SwiftOpenUI
// uses a top-level `FontWeight`, so expose the spelling from one shared
// module that both `QuillUI` and the Linux `SwiftUI` shadow can re-export.
public extension Font {
    typealias Weight = FontWeight
}

// SwiftOpenUI currently provides top/center/bottom alignment only.
// Downgrade baseline-relative alignments to the closest visual
// approximation until backend text metrics can drive true baselines.
public extension VerticalAlignment {
    static var firstTextBaseline: VerticalAlignment { .top }
    static var lastTextBaseline: VerticalAlignment { .bottom }
}
#endif
