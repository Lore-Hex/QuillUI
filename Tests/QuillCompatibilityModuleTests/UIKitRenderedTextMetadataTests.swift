#if os(Linux)
import Testing
import UIKit

@MainActor
struct UIKitRenderedTextMetadataTests {

    @Test func customDrawnTextMetadataRoundTripsOnUIView() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 44))

        #expect(view.quillRenderedText == nil)
        #expect(view.quillRenderedTextColor == nil)
        #expect(view.quillRenderedTextPointSize == 17)
        #expect(view.quillRenderedTextAlignment == .natural)
        #expect(view.quillRenderedTextNumberOfLines == 0)

        view.quillRenderedText = "Signal body text"
        view.quillRenderedTextColor = .label
        view.quillRenderedTextPointSize = 15
        view.quillRenderedTextAlignment = .center
        view.quillRenderedTextNumberOfLines = 2

        #expect(view.quillRenderedText == "Signal body text")
        #expect(view.quillRenderedTextColor != nil)
        #expect(view.quillRenderedTextPointSize == 15)
        #expect(view.quillRenderedTextAlignment == .center)
        #expect(view.quillRenderedTextNumberOfLines == 2)

        view.quillRenderedText = nil
        #expect(view.quillRenderedText == nil)
    }

    @Test func imageRendererReturnsBitmapCGImagePixels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1), format: format)

        let image = renderer.image { context in
            context.cgContext.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0.5, y: 0, width: 1, height: 1))
        }

        let cgImage = try #require(image.cgImage)
        #expect(image.size == CGSize(width: 2, height: 1))
        #expect(image.scale == 2)
        #expect(cgImage.width == 4)
        #expect(cgImage.height == 2)
        #expect(pixel(in: cgImage, x: 0, y: 0) == [0, 0, 0, 0])
        #expect(pixel(in: cgImage, x: 1, y: 0) == [0, 255, 0, 255])
        #expect(pixel(in: cgImage, x: 2, y: 1) == [0, 255, 0, 255])
        #expect(pixel(in: cgImage, x: 3, y: 0) == [0, 0, 0, 0])
    }

    @Test func legacyImageContextReturnsBitmapCGImagePixels() throws {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 2, height: 1), false, 1)
        defer { UIGraphicsEndImageContext() }

        let context = try #require(UIGraphicsGetCurrentContext())
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.translateBy(x: 1, y: 0)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))

        let image = try #require(UIGraphicsGetImageFromCurrentImageContext())
        let cgImage = try #require(image.cgImage)
        #expect(image.size == CGSize(width: 2, height: 1))
        #expect(cgImage.width == 2)
        #expect(cgImage.height == 1)
        #expect(pixel(in: cgImage, x: 0, y: 0) == [0, 0, 0, 0])
        #expect(pixel(in: cgImage, x: 1, y: 0) == [0, 0, 255, 255])
    }

    @Test func imageRendererSupportsUIKitFillAndImageDraw() throws {
        let sourceCGImage = CGImage()
        sourceCGImage.width = 1
        sourceCGImage.height = 1
        sourceCGImage.quillBytesPerRow = 4
        sourceCGImage.quillBGRAPixels = [255, 0, 0, 255]
        let sourceImage = UIImage(cgImage: sourceCGImage, size: CGSize(width: 1, height: 1))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 1))
        let image = renderer.image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 3, height: 1))
            sourceImage.draw(in: CGRect(x: 1, y: 0, width: 1, height: 1))
        }

        let cgImage = try #require(image.cgImage)
        #expect(UIGraphicsGetCurrentContext() == nil)
        #expect(pixel(in: cgImage, x: 0, y: 0) == [0, 0, 255, 255])
        #expect(pixel(in: cgImage, x: 1, y: 0) == [255, 0, 0, 255])
        #expect(pixel(in: cgImage, x: 2, y: 0) == [0, 0, 255, 255])
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> [UInt8]? {
        guard let pixels = image.quillBGRAPixels,
              x >= 0, y >= 0, x < image.width, y < image.height,
              image.quillBytesPerRow >= image.width * 4
        else {
            return nil
        }
        let offset = y * image.quillBytesPerRow + x * 4
        guard offset + 3 < pixels.count else {
            return nil
        }
        return Array(pixels[offset..<(offset + 4)])
    }
}
#endif
