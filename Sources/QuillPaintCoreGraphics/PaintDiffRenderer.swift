import Foundation
import QuillPaint

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO

/// Visual diff generator for the Mac-reference verifier.
public enum PaintDiffRenderer {
    /// Render a visual diff between two images.
    /// - Parameters:
    ///   - reference: The golden/expected image.
    ///   - candidate: The actual image produced by the current code.
    ///   - tolerance: Per-channel byte tolerance (0...255).
    /// - Returns: A CGImage where matching pixels are 50% opacity reference pixels,
    ///   and differing pixels are solid red.
    public static func renderDiff(reference: CGImage, candidate: CGImage, tolerance: UInt8) throws -> CGImage {
        let width = reference.width
        let height = reference.height

        guard candidate.width == width, candidate.height == height else {
            // Ideally we'd throw a PixelComparatorError.dimensionMismatch here,
            // but that's in QuillPaint. We can just return a failure or throw a local error.
            // For now, let's assume dimensions match as per test guard.
            fatalError("Dimensions mismatch in renderDiff")
        }

        let refData = try CGPixelExtraction.rawRGBA(from: reference)
        let candData = try CGPixelExtraction.rawRGBA(from: candidate)

        var diffBytes = [UInt8](repeating: 0, count: width * height * 4)
        let tol = Int(tolerance)

        refData.withUnsafeBytes { refRaw in
            candData.withUnsafeBytes { candRaw in
                guard let refPtr = refRaw.bindMemory(to: UInt8.self).baseAddress,
                      let candPtr = candRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }

                for i in stride(from: 0, to: width * height * 4, by: 4) {
                    let dr = absDiff(refPtr[i], candPtr[i])
                    let dg = absDiff(refPtr[i + 1], candPtr[i + 1])
                    let db = absDiff(refPtr[i + 2], candPtr[i + 2])
                    let da = absDiff(refPtr[i + 3], candPtr[i + 3])

                    let pixelMax = max(max(dr, dg), max(db, da))

                    if pixelMax > tol {
                        // Differing pixel: Solid Red
                        diffBytes[i] = 255     // R
                        diffBytes[i + 1] = 0   // G
                        diffBytes[i + 2] = 0   // B
                        diffBytes[i + 3] = 255 // A
                    } else {
                        // Matching pixel: Reference at 50% opacity.
                        // Since rawRGBA uses premultipliedLast, we just halve all channels.
                        diffBytes[i] = refPtr[i] / 2
                        diffBytes[i + 1] = refPtr[i + 1] / 2
                        diffBytes[i + 2] = refPtr[i + 2] / 2
                        diffBytes[i + 3] = refPtr[i + 3] / 2
                    }
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &diffBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CGPixelExtraction.Error.contextCreationFailed
        }

        guard let diffImage = context.makeImage() else {
            throw CGPixelExtraction.Error.decodeFailed // Reuse decodeFailed or add new error
        }

        return diffImage
    }

    private static func absDiff(_ a: UInt8, _ b: UInt8) -> Int {
        a > b ? Int(a) - Int(b) : Int(b) - Int(a)
    }
}

#endif
