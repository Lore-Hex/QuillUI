import Foundation
import Testing
import QuillPaint
@testable import QuillPaintCoreGraphics

#if canImport(CoreGraphics) && canImport(ImageIO) && !os(Linux)
import CoreGraphics

@Suite("Mac reference renderer (CoreGraphics backend)")
struct MacReferenceRendererTests {
    @Test("renderImage produces a CGImage at the requested pixel dimensions")
    func renderImageDimensions() throws {
        let renderer = MacReferenceRenderer(margin: 8, scale: 2.0)
        let size = PaintSize(width: 80, height: 22)
        let image = try renderer.renderImage(
            control: MacButtonPaint(),
            frame: size,
            state: .normal
        )

        // Canvas = control size + 2 * margin, then * scale.
        let expectedWidth = Int((size.width + 16) * 2.0)
        let expectedHeight = Int((size.height + 16) * 2.0)
        #expect(image.width == expectedWidth)
        #expect(image.height == expectedHeight)
    }

    @Test("renderPNG writes a non-empty PNG file")
    func renderPNGWritesFile() throws {
        let renderer = MacReferenceRenderer()
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacReferenceRendererTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let output = scratch.appendingPathComponent("nested/button.png")
        try renderer.renderPNG(
            control: MacButtonPaint(),
            frame: PaintSize(width: 80, height: 22),
            state: .normal,
            outputURL: output
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let size = attributes[.size] as? Int ?? 0
        #expect(size > 100, "PNG file should have non-trivial content, got \(size) bytes")

        // First 8 bytes of a PNG: 89 50 4E 47 0D 0A 1A 0A
        let data = try Data(contentsOf: output)
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let actualPrefix = Array(data.prefix(8))
        #expect(actualPrefix == pngSignature)
    }

    @Test("Default vs normal buttons produce different pixel data")
    func defaultDiffersFromNormal() throws {
        let renderer = MacReferenceRenderer()
        let normal = try renderer.renderImage(
            control: MacButtonPaint(),
            frame: PaintSize(width: 80, height: 22),
            state: .normal
        )
        let defaultBtn = try renderer.renderImage(
            control: MacButtonPaint(),
            frame: PaintSize(width: 80, height: 22),
            state: PaintControlState(isDefault: true)
        )

        let normalData = Self.rawRGBA(from: normal)
        let defaultData = Self.rawRGBA(from: defaultBtn)
        #expect(normalData != defaultData)
    }

    @Test("Focus ring extends beyond the button frame within the margin")
    func focusRingFitsInsideMargin() throws {
        let renderer = MacReferenceRenderer(margin: 8, scale: 2.0)
        let size = PaintSize(width: 80, height: 22)
        let focused = try renderer.renderImage(
            control: MacButtonPaint(),
            frame: size,
            state: PaintControlState(isFocused: true)
        )

        // The focus ring fills the corners just inside the margin — the
        // top-left CORNER of the canvas (pixel 0,0) should still be fully
        // transparent because the ring is a stroke, not a fill, and the
        // ring is inset by `margin - focusRingOutset`.
        let data = Self.rawRGBA(from: focused)
        // Pixel (0,0) RGBA — should be transparent (alpha 0).
        // Bitmap is premultiplied RGBA; alpha is the 4th byte.
        let cornerAlpha = data[3]
        #expect(cornerAlpha == 0, "Top-left corner should be transparent; ring is contained in the margin")
    }

    static func rawRGBA(from image: CGImage) -> Data {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(bytes)
    }
}

@Suite("CGPaintContext primitives")
struct CGPaintContextTests {
    @Test("CGPaintContext fillRoundedRect actually fills opaque pixels")
    func fillRoundedRectFillsPixels() throws {
        let renderer = MacReferenceRenderer(margin: 0, scale: 1.0)
        // Single solid red fillRect via a no-op control wrapper.
        struct SolidFill: PaintControl {
            func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
                context.fillRect(frame, color: PaintColor(red: 1, green: 0, blue: 0, alpha: 1))
            }
        }
        let image = try renderer.renderImage(
            control: SolidFill(),
            frame: PaintSize(width: 4, height: 4),
            state: .normal
        )
        #expect(image.width == 4)
        #expect(image.height == 4)
        // Read the pixel data and confirm at least one pixel is red.
        let data = MacReferenceRendererTests.rawRGBA(from: image)
        var foundRed = false
        var idx = 0
        while idx + 3 < data.count {
            let red = data[idx]
            let green = data[idx + 1]
            let blue = data[idx + 2]
            let alpha = data[idx + 3]
            if red > 200 && green < 50 && blue < 50 && alpha > 200 {
                foundRed = true
                break
            }
            idx += 4
        }
        #expect(foundRed, "Solid red fill should produce a red pixel in the bitmap")
    }

    @Test("CGPaintContext drawText paints non-transparent pixels")
    func drawTextPaintsPixels() throws {
        let renderer = MacReferenceRenderer(margin: 0, scale: 2.0)
        struct TextOnly: PaintControl {
            func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
                context.drawText(
                    "OK",
                    at: PaintPoint(x: 0, y: 0),
                    font: MacFonts.controlLabel,
                    color: MacColors.controlText
                )
            }
        }

        let image = try renderer.renderImage(
            control: TextOnly(),
            frame: PaintSize(width: 40, height: 20),
            state: .normal
        )
        let data = MacReferenceRendererTests.rawRGBA(from: image)
        var foundInk = false
        var idx = 3
        while idx < data.count {
            if data[idx] > 0 {
                foundInk = true
                break
            }
            idx += 4
        }
        #expect(foundInk, "Core Text drawing should place visible glyph pixels into the bitmap")
    }
}

#endif
