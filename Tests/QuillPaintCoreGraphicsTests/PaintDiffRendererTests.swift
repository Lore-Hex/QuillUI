import Foundation
import Testing
@testable import QuillPaintCoreGraphics

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics

@Suite("PaintDiffRenderer")
struct PaintDiffRendererTests {
    @Test("Identical inputs produce a diff with no red pixels")
    func identicalInputsHaveNoRedPixels() throws {
        let image = try Self.image(
            width: 2,
            height: 1,
            rgba: [
                255, 0, 0, 255,
                20, 30, 40, 255
            ]
        )

        let diff = PaintDiffRenderer().renderDiff(
            reference: image,
            candidate: image,
            tolerance: 0
        )

        #expect(Self.solidRedPixelCount(in: diff) == 0)
    }

    @Test("One differing input pixel produces exactly one red diff pixel")
    func oneDifferingPixelProducesOneRedPixel() throws {
        let reference = try Self.image(
            width: 2,
            height: 1,
            rgba: [
                10, 20, 30, 255,
                40, 50, 60, 255
            ]
        )
        let candidate = try Self.image(
            width: 2,
            height: 1,
            rgba: [
                10, 20, 30, 255,
                41, 50, 60, 255
            ]
        )

        let diff = PaintDiffRenderer().renderDiff(
            reference: reference,
            candidate: candidate,
            tolerance: 0
        )

        #expect(Self.solidRedPixelCount(in: diff) == 1)
    }

    private static func image(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        #expect(rgba.count == width * height * 4)
        let data = Data(rgba)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        return try #require(image)
    }

    private static func solidRedPixelCount(in image: CGImage) -> Int {
        let bytes = rawRGBA(from: image)
        var count = 0
        var offset = 0
        while offset + 3 < bytes.count {
            if bytes[offset] == 255,
               bytes[offset + 1] == 0,
               bytes[offset + 2] == 0,
               bytes[offset + 3] == 255 {
                count += 1
            }
            offset += 4
        }
        return count
    }

    private static func rawRGBA(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}

#endif
