#if os(Linux)
import AppKit
import CCairo
import QuillFoundation
import Testing
@testable import QuillAppKitGTK

@Suite("Cairo CGContext backend")
struct CairoCGContextBackendTests {
    @Test("Cairo CGContext backend applies line dash")
    func lineDashSkipsStrokeSegments() throws {
        let width: Int32 = 8
        let height: Int32 = 1
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height) else {
            Issue.record("Failed to create Cairo image surface")
            return
        }
        defer { cairo_surface_destroy(surface) }

        guard let cr = cairo_create(surface) else {
            Issue.record("Failed to create Cairo context")
            return
        }
        defer { cairo_destroy(cr) }

        let context = CGContext(quillBackend: CairoCGContextBackend(cr: cr))
        context.setShouldAntialias(false)
        context.setStrokeColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [2, 1])
        context.move(to: CGPoint(x: 0, y: 0.5))
        context.addLine(to: CGPoint(x: 8, y: 0.5))
        context.strokePath()
        cairo_surface_flush(surface)

        guard let raw = cairo_image_surface_get_data(surface) else {
            Issue.record("Failed to read Cairo surface data")
            return
        }
        let stride = Int(cairo_image_surface_get_stride(surface))

        func alphaAt(x: Int) -> UInt8 {
            raw.advanced(by: x * 4)[3]
        }

        #expect(alphaAt(x: 0) == 255)
        #expect(alphaAt(x: 1) == 255)
        #expect(alphaAt(x: 2) == 0)
        #expect(alphaAt(x: 3) == 255)
        #expect(stride >= Int(width) * 4)
    }

    @Test("Cairo CGContext backend shadow blur spreads alpha")
    func shadowBlurSpreadsAlpha() throws {
        let width: Int32 = 7
        let height: Int32 = 3
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height) else {
            Issue.record("Failed to create Cairo image surface")
            return
        }
        defer { cairo_surface_destroy(surface) }

        guard let cr = cairo_create(surface) else {
            Issue.record("Failed to create Cairo context")
            return
        }
        defer { cairo_destroy(cr) }

        let context = CGContext(quillBackend: CairoCGContextBackend(cr: cr))
        context.setShadow(
            offset: .zero,
            blur: 1,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        )
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 3, y: 1, width: 1, height: 1))
        cairo_surface_flush(surface)

        guard let raw = cairo_image_surface_get_data(surface) else {
            Issue.record("Failed to read Cairo surface data")
            return
        }
        let stride = Int(cairo_image_surface_get_stride(surface))

        func alphaAt(x: Int, y: Int) -> UInt8 {
            raw.advanced(by: y * stride + x * 4)[3]
        }

        #expect(alphaAt(x: 3, y: 1) == 255)
        #expect(alphaAt(x: 2, y: 1) > 0)
        #expect(alphaAt(x: 4, y: 1) > 0)
        #expect(alphaAt(x: 0, y: 1) == 0)
    }
}
#endif
