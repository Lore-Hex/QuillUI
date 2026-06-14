//
// QuillUI Linux shim for `SDWebImage`.
//
// SignalServiceKit uses `SDAnimatedImage` to decode animated/WebP attachments
// (it's a UIImage subclass on Apple). SDWebImage is unavailable on Linux, so
// this is INERT: `SDAnimatedImage(data:)` produces a placeholder UIImage with no
// decoded frames. Animated/WebP rendering needs a real decoder (libwebp via a
// Linux backend) -- deferred. HONEST STATUS: WebP/animated images do not decode.
//
import Foundation
import QuillFoundation  // UIImage (RSImage), which SDAnimatedImage subclasses
import QuillUIKit

/// `SDAnimatedImage: UIImage`. Adds no stored properties, so it inherits all of
/// RSImage's initializers (including the failable `init?(data:)` SSK calls) --
/// which yields a placeholder image on Linux (no frames are actually decoded).
open class SDAnimatedImage: UIImage {
}

/// `SDAnimatedImageView: UIImageView`. Inert display wrapper for SignalUI's
/// animated image views; frame decoding/rendering is deferred with
/// `SDAnimatedImage`.
@MainActor open class SDAnimatedImageView: UIImageView {
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    // UIImageView declares `required init?(coder:)`; the own designated init
    // above suppresses inheritance, so restate it.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

/// The coder registry. INERT: registered coders are ignored on Linux (no real
/// SDWebImage decode pipeline). `addCoder` takes `Any` so callers can register
/// the WebP coders (from SDWebImageWebPCoder) without this shim depending on it.
public final class SDImageCodersManager: @unchecked Sendable {
    public static let shared = SDImageCodersManager()
    public init() {}
    public func addCoder(_ coder: Any) {}
    public func removeCoder(_ coder: Any) {}
}
