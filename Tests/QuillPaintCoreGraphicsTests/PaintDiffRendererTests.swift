import Foundation
import Testing
import QuillPaint
@testable import QuillPaintCoreGraphics

#if canImport(CoreGraphics) && !os(Linux)
import CoreGraphics

@Suite("PaintDiffRenderer")
struct PaintDiffRendererTests {

    @Test("Identical images produce a diff with no red pixels")
    func identicalImages() throws {
        let size = 10
        let image = try createTestImage(width: size, height: size, color: [100, 100, 100, 255])
        let diff = try PaintDiffRenderer.renderDiff(reference: image, candidate: image, tolerance: 0)
        
        let diffBytes = try CGPixelExtraction.rawRGBA(from: diff)
        
        // No pixel should be solid red (255, 0, 0, 255)
        for i in stride(from: 0, to: diffBytes.count, by: 4) {
            let isRed = diffBytes[i] == 255 && diffBytes[i+1] == 0 && diffBytes[i+2] == 0 && diffBytes[i+3] == 255
            #expect(!isRed, "Pixel at index \(i/4) should not be red")
        }
    }

    @Test("A 1-pixel-different image produces a diff with exactly one red pixel")
    func onePixelDifferent() throws {
        let size = 10
        let refColor: [UInt8] = [100, 100, 100, 255]
        let refImage = try createTestImage(width: size, height: size, color: refColor)
        
        var candBytes = [UInt8]()
        for _ in 0..<(size * size) {
            candBytes.append(contentsOf: refColor)
        }
        // Change one pixel at (5, 5)
        let diffIndex = (5 * size + 5) * 4
        candBytes[diffIndex] = 200 // R differs
        
        let candImage = try createCGImage(width: size, height: size, bytes: candBytes)
        
        let diff = try PaintDiffRenderer.renderDiff(reference: refImage, candidate: candImage, tolerance: 0)
        let diffBytes = try CGPixelExtraction.rawRGBA(from: diff)
        
        var redPixelCount = 0
        for i in stride(from: 0, to: diffBytes.count, by: 4) {
            let isRed = diffBytes[i] == 255 && diffBytes[i+1] == 0 && diffBytes[i+2] == 0 && diffBytes[i+3] == 255
            if isRed {
                redPixelCount += 1
                #expect(i == diffIndex, "Red pixel should be at the differing index")
            }
        }
        
        #expect(redPixelCount == 1, "Should have exactly one red pixel")
    }

    @Test("Tolerance is respected: small difference within tolerance produces no red pixels")
    func toleranceRespected() throws {
        let size = 10
        let refColor: [UInt8] = [100, 100, 100, 255]
        let refImage = try createTestImage(width: size, height: size, color: refColor)
        
        var candBytes = [UInt8]()
        for _ in 0..<(size * size) {
            candBytes.append(contentsOf: refColor)
        }
        // Change one pixel at (5, 5) by 2 units
        let diffIndex = (5 * size + 5) * 4
        candBytes[diffIndex] = 102
        
        let candImage = try createCGImage(width: size, height: size, bytes: candBytes)
        
        // With tolerance 2, it should be matching (no red)
        let diff = try PaintDiffRenderer.renderDiff(reference: refImage, candidate: candImage, tolerance: 2)
        let diffBytes = try CGPixelExtraction.rawRGBA(from: diff)
        
        for i in stride(from: 0, to: diffBytes.count, by: 4) {
            let isRed = diffBytes[i] == 255 && diffBytes[i+1] == 0 && diffBytes[i+2] == 0 && diffBytes[i+3] == 255
            #expect(!isRed, "Pixel at index \(i/4) should not be red within tolerance")
        }
    }

    private func createTestImage(width: Int, height: Int, color: [UInt8]) throws -> CGImage {
        var bytes = [UInt8]()
        for _ in 0..<(width * height) {
            bytes.append(contentsOf: color)
        }
        return try createCGImage(width: width, height: height, bytes: bytes)
    }

    private func createCGImage(width: Int, height: Int, bytes: [UInt8]) throws -> CGImage {
        var mutableBytes = bytes
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CGPixelExtraction.Error.contextCreationFailed
        }
        guard let image = context.makeImage() else {
            throw CGPixelExtraction.Error.decodeFailed
        }
        return image
    }
}

#endif
