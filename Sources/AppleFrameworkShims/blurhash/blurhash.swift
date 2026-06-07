//
// QuillUI Linux shim for `blurhash` (woltapp/blurhash Swift bindings).
//
// blurhash is a compact image-placeholder codec. Its Swift bindings extend
// UIImage with an encoder (image -> hash string) and a decoder initializer (hash
// string -> placeholder image). SignalServiceKit's BlurHash.swift uses both:
//   normalized.blurHash(numberOfComponents: (4, 3))         // encode
//   UIImage(blurHash: blurHash, size: thumbnailSize)        // decode
//
// Both need pixel-level raster work that has no Linux backend yet, so they are
// inert: the encoder returns nil (no hash computed) and the decoder fails (no
// placeholder image). Callers already treat nil as "couldn't compute" and skip
// the blurhash path. HONEST STATUS: blurhash generation/rendering is deferred.
//
// Public (cross-module: this is a separate module BlurHash.swift imports). UIImage
// (= RSImage on Linux) and CGSize come from QuillFoundation, this shim's dep.
//
import Foundation
import QuillFoundation

public extension UIImage {
    /// blurhash ENCODE. Inert on Linux (no pixel sampling) -> nil.
    func blurHash(numberOfComponents components: (Int, Int)) -> String? {
        return nil
    }

    /// blurhash DECODE. Inert on Linux (no raster backend) -> fails.
    convenience init?(blurHash: String, size: CGSize, punch: Float = 1) {
        return nil
    }
}
