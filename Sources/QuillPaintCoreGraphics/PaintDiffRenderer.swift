import Foundation

#if canImport(CoreGraphics)
import CoreGraphics

/// Renders a diagnostic visual diff for two same-sized CoreGraphics images.
///
/// Matching pixels preserve the reference RGB while halving the reference
/// alpha, keeping the original image visible as context. Differing pixels are
/// rendered as solid red.
public struct PaintDiffRenderer {
    public init() {}

    public func renderDiff(
        reference: CGImage,
        candidate: CGImage,
        tolerance: UInt8
    ) -> CGImage {
        precondition(
            reference.width == candidate.width && reference.height == candidate.height,
            "PaintDiffRenderer requires images with identical dimensions."
        )

        let width = reference.width
        let height = reference.height
        let byteCount = width * height * 4
        let referenceBytes = Self.rawRGBA(from: reference)
        let candidateBytes = Self.rawRGBA(from: candidate)
        var outputBytes = [UInt8](repeating: 0, count: byteCount)
        let tolerance = Int(tolerance)

        referenceBytes.withUnsafeBytes { referenceRaw in
            candidateBytes.withUnsafeBytes { candidateRaw in
                outputBytes.withUnsafeMutableBytes { outputRaw in
                    guard let referencePtr = referenceRaw.bindMemory(to: UInt8.self).baseAddress,
                          let candidatePtr = candidateRaw.bindMemory(to: UInt8.self).baseAddress,
                          let outputPtr = outputRaw.bindMemory(to: UInt8.self).baseAddress else {
                        return
                    }

                    var offset = 0
                    while offset < byteCount {
                        let redDelta = Self.absDiff(referencePtr[offset], candidatePtr[offset])
                        let greenDelta = Self.absDiff(referencePtr[offset + 1], candidatePtr[offset + 1])
                        let blueDelta = Self.absDiff(referencePtr[offset + 2], candidatePtr[offset + 2])
                        let alphaDelta = Self.absDiff(referencePtr[offset + 3], candidatePtr[offset + 3])
                        let pixelDelta = max(max(redDelta, greenDelta), max(blueDelta, alphaDelta))

                        if pixelDelta > tolerance {
                            outputPtr[offset] = 255
                            outputPtr[offset + 1] = 0
                            outputPtr[offset + 2] = 0
                            outputPtr[offset + 3] = 255
                        } else {
                            outputPtr[offset] = referencePtr[offset]
                            outputPtr[offset + 1] = referencePtr[offset + 1]
                            outputPtr[offset + 2] = referencePtr[offset + 2]
                            outputPtr[offset + 3] = Self.halfAlpha(referencePtr[offset + 3])
                        }

                        offset += 4
                    }
                }
            }
        }

        return Self.makeImage(width: width, height: height, bytes: outputBytes)
    }

    private static func rawRGBA(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Failed to create RGBA bitmap context.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private static func makeImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            preconditionFailure("Failed to create diff image data provider.")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            preconditionFailure("Failed to create diff CGImage.")
        }
        return image
    }

    private static func halfAlpha(_ alpha: UInt8) -> UInt8 {
        UInt8((UInt16(alpha) + 1) / 2)
    }

    private static func absDiff(_ a: UInt8, _ b: UInt8) -> Int {
        a > b ? Int(a) - Int(b) : Int(b) - Int(a)
    }
}

#endif
