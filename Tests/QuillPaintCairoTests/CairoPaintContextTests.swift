import Testing
import QuillPaint
@testable import QuillPaintCairo

#if canImport(CCairo)
import CCairo

@Suite("CairoPaintContext Tests")
struct CairoPaintContextTests {
    @Test("Basic drawing on ImageSurface")
    func testBasicDrawing() throws {
        let width = 100
        let height = 100
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height))
        defer { cairo_surface_destroy(surface) }
        
        let cr = cairo_create(surface)
        defer { cairo_destroy(cr) }
        
        let context = CairoPaintContext(pointer: try #require(cr))
        
        // Just verify it doesn't crash and we can call methods
        context.fillRoundedRect(PaintRect(x: 10, y: 10, width: 80, height: 80), cornerRadius: 5, color: .white)
        context.strokeLine(from: PaintPoint(x: 0, y: 0), to: PaintPoint(x: 100, y: 100), color: .black, lineWidth: 1)
        
        let status = cairo_status(cr)
        #expect(status == CAIRO_STATUS_SUCCESS)
    }

    @Test("GTK-compatible initializer draws the same paint context")
    func gtkCompatibleInitializer() throws {
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 24, 24)
        defer { cairo_surface_destroy(surface) }

        let cr = try #require(cairo_create(surface))
        defer { cairo_destroy(cr) }

        let context = CairoPaintContext(cr: cr)
        context.strokeRoundedRect(
            PaintRect(x: 2, y: 2, width: 20, height: 20),
            cornerRadius: 4,
            color: .black,
            lineWidth: 1
        )

        cairo_surface_flush(surface)
        #expect(cairo_status(cr) == CAIRO_STATUS_SUCCESS)
        #expect(alphaPixelCount(in: surface) > 0)
    }

    @Test("Text rendering resolves mac font tokens and writes pixels")
    func textRenderingWritesPixels() throws {
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 180, 64)
        defer { cairo_surface_destroy(surface) }

        let cr = try #require(cairo_create(surface))
        defer { cairo_destroy(cr) }

        let context = CairoPaintContext(cr: cr)
        context.drawText(
            "Quill",
            at: PaintPoint(x: 12, y: 12),
            font: MacFonts.controlLabelEmphasized,
            color: .black
        )

        cairo_surface_flush(surface)
        #expect(cairo_status(cr) == CAIRO_STATUS_SUCCESS)
        #expect(alphaPixelCount(in: surface) > 0)
    }

    private func alphaPixelCount(in surface: OpaquePointer?) -> Int {
        guard let surface, let raw = cairo_image_surface_get_data(surface) else {
            return 0
        }

        let width = Int(cairo_image_surface_get_width(surface))
        let height = Int(cairo_image_surface_get_height(surface))
        let stride = Int(cairo_image_surface_get_stride(surface))
        var alphaPixels = 0

        for y in 0..<height {
            let row = raw.advanced(by: y * stride)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                if pixel[3] > 0 {
                    alphaPixels += 1
                }
            }
        }

        return alphaPixels
    }
}
#endif
