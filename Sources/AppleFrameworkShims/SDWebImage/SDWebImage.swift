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

/// `SDAnimatedImage: UIImage`. Adds no stored properties, so it inherits all of
/// RSImage's initializers (including the failable `init?(data:)` SSK calls) --
/// which yields a placeholder image on Linux (no frames are actually decoded).
open class SDAnimatedImage: UIImage {
}
