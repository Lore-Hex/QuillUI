import Testing
import QuillPaint
@testable import QuillPaintCairo

#if canImport(CCairo)
import CCairo

@Suite("CairoPaintContext Tests")
struct CairoPaintContextTests {
    @Test("Basic drawing on ImageSurface")
    func testBasicDrawing() {
        let width = 100
        let height = 100
        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height))
        defer { cairo_surface_destroy(surface) }
        
        let cr = cairo_create(surface)
        defer { cairo_destroy(cr) }
        
        let context = CairoPaintContext(pointer: cr!)
        
        // Just verify it doesn't crash and we can call methods
        context.fillRoundedRect(PaintRect(x: 10, y: 10, width: 80, height: 80), cornerRadius: 5, color: .white)
        context.strokeLine(from: PaintPoint(x: 0, y: 0), to: PaintPoint(x: 100, y: 100), color: .black, lineWidth: 1)
        
        let status = cairo_status(cr)
        #expect(status == CAIRO_STATUS_SUCCESS)
    }
}
#endif
