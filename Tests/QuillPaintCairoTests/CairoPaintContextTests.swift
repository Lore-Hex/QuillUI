import Testing
import Foundation
import QuillPaint
@testable import QuillPaintCairo

#if canImport(CCairo)
import CCairo
#if os(Linux) && canImport(CGdkPixbuf)
import CGdkPixbuf
#endif

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

    #if os(Linux) && canImport(CGdkPixbuf)
    @Test(
        "Linux button regions match Mac reference fixtures with tolerance 6",
        arguments: buttonReferenceCases
    )
    func linuxButtonRegionsMatchMacReference(testCase: ButtonReferenceCase) throws {
        let candidate = try Self.renderButtonRegion(state: testCase.state)
        let reference = try Self.loadPixbufRGBA(from: try Self.locateFixtureURL(name: testCase.fixtureName))

        #expect(reference.width == candidate.width)
        #expect(reference.height == candidate.height)
        guard reference.width == candidate.width, reference.height == candidate.height else {
            return
        }

        let result = try PixelComparator(tolerance: 6).compare(
            reference: reference.rgba,
            candidate: candidate.rgba,
            width: reference.width,
            height: reference.height
        )

        #expect(
            result.matchRatio >= 0.90,
            "\(testCase.fixtureName) match ratio \(result.matchRatio) below 0.90; maxChannelDelta=\(result.maxChannelDelta), differingPixels=\(result.differingPixels)/\(result.totalPixels)"
        )
    }

    private static let buttonReferenceCases = [
        ButtonReferenceCase(
            fixtureName: "button-default.png",
            state: PaintControlState(isDefault: true)
        ),
        ButtonReferenceCase(
            fixtureName: "button-normal.png",
            state: .normal
        )
    ]

    private static func renderButtonRegion(
        state: PaintControlState,
        size: PaintSize = PaintSize(width: 80, height: 22),
        margin: Double = 8,
        scale: Double = 2
    ) throws -> RGBAImage {
        let canvas = PaintSize(
            width: size.width + 2 * margin,
            height: size.height + 2 * margin
        )
        let pixelWidth = max(1, Int((canvas.width * scale).rounded()))
        let pixelHeight = max(1, Int((canvas.height * scale).rounded()))

        guard let surface = cairo_image_surface_create(
            CAIRO_FORMAT_ARGB32,
            Int32(pixelWidth),
            Int32(pixelHeight)
        ) else {
            throw RenderError.contextCreationFailed
        }
        defer { cairo_surface_destroy(surface) }

        guard let cairo = cairo_create(surface) else {
            throw RenderError.contextCreationFailed
        }
        defer { cairo_destroy(cairo) }

        cairo_set_operator(cairo, CAIRO_OPERATOR_CLEAR)
        cairo_paint(cairo)
        cairo_set_operator(cairo, CAIRO_OPERATOR_OVER)
        cairo_scale(cairo, scale, scale)

        let context = CairoPaintContext(pointer: cairo)
        MacButtonPaint().paint(
            into: context,
            frame: PaintRect(x: margin, y: margin, width: size.width, height: size.height),
            state: state
        )

        return try Self.rgbaImage(fromARGB32Surface: surface, width: pixelWidth, height: pixelHeight)
    }

    private static func rgbaImage(
        fromARGB32Surface surface: OpaquePointer,
        width: Int,
        height: Int
    ) throws -> RGBAImage {
        cairo_surface_flush(surface)
        guard let sourcePixels = cairo_image_surface_get_data(surface) else {
            throw RenderError.pixelExtractionFailed
        }

        let sourceStride = Int(cairo_image_surface_get_stride(surface))
        var rgba = Data(count: width * height * 4)

        rgba.withUnsafeMutableBytes { rawBuffer in
            guard let destination = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            for y in 0..<height {
                let sourceRow = sourcePixels.advanced(by: y * sourceStride)
                let destinationRow = destination.advanced(by: y * width * 4)

                for x in 0..<width {
                    let pixel = UnsafeRawPointer(sourceRow.advanced(by: x * 4)).load(as: UInt32.self)
                    let alpha = (pixel >> 24) & 0xFF
                    let red = (pixel >> 16) & 0xFF
                    let green = (pixel >> 8) & 0xFF
                    let blue = pixel & 0xFF
                    let destinationPixel = destinationRow.advanced(by: x * 4)

                    destinationPixel[0] = unpremultipliedByte(red, alpha: alpha)
                    destinationPixel[1] = unpremultipliedByte(green, alpha: alpha)
                    destinationPixel[2] = unpremultipliedByte(blue, alpha: alpha)
                    destinationPixel[3] = UInt8(alpha)
                }
            }
        }

        return RGBAImage(width: width, height: height, rgba: rgba)
    }

    private static func loadPixbufRGBA(from url: URL) throws -> RGBAImage {
        var error: UnsafeMutablePointer<GError>?
        guard let pixbuf = gdk_pixbuf_new_from_file(url.path, &error) else {
            if let error {
                g_error_free(error)
            }
            throw RenderError.decodeFailed(url.path)
        }
        defer { g_object_unref(gpointer(pixbuf)) }

        let width = Int(gdk_pixbuf_get_width(pixbuf))
        let height = Int(gdk_pixbuf_get_height(pixbuf))
        let rowstride = Int(gdk_pixbuf_get_rowstride(pixbuf))
        let channels = Int(gdk_pixbuf_get_n_channels(pixbuf))
        let hasAlpha = gdk_pixbuf_get_has_alpha(pixbuf) != 0
        guard width > 0, height > 0, channels >= 3, let sourcePixels = gdk_pixbuf_get_pixels(pixbuf) else {
            throw RenderError.decodeFailed(url.path)
        }

        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { rawBuffer in
            guard let destination = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            for y in 0..<height {
                let sourceRow = sourcePixels.advanced(by: y * rowstride)
                let destinationRow = destination.advanced(by: y * width * 4)

                for x in 0..<width {
                    let sourcePixel = sourceRow.advanced(by: x * channels)
                    let destinationPixel = destinationRow.advanced(by: x * 4)
                    destinationPixel[0] = sourcePixel[0]
                    destinationPixel[1] = sourcePixel[1]
                    destinationPixel[2] = sourcePixel[2]
                    destinationPixel[3] = hasAlpha ? sourcePixel[3] : 255
                }
            }
        }

        return RGBAImage(width: width, height: height, rgba: rgba)
    }

    private static func locateFixtureURL(name: String) throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        var current = thisFile.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = current.appendingPathComponent("Tests/Fixtures/MacReference/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            current = current.deletingLastPathComponent()
        }

        let cwdCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/MacReference/\(name)")
        if FileManager.default.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }

        throw RenderError.fixtureNotFound(name)
    }

    private static func unpremultipliedByte(_ component: UInt32, alpha: UInt32) -> UInt8 {
        guard alpha > 0 else { return 0 }
        return UInt8(min(255, (component * 255 + alpha / 2) / alpha))
    }

    struct ButtonReferenceCase: Sendable {
        let fixtureName: String
        let state: PaintControlState
    }

    struct RGBAImage: Equatable, Sendable {
        let width: Int
        let height: Int
        let rgba: Data
    }

    enum RenderError: Error, CustomStringConvertible {
        case contextCreationFailed
        case pixelExtractionFailed
        case fixtureNotFound(String)
        case decodeFailed(String)

        var description: String {
            switch self {
            case .contextCreationFailed:
                return "Failed to create Cairo context."
            case .pixelExtractionFailed:
                return "Failed to extract Cairo ARGB32 pixels."
            case .fixtureNotFound(let name):
                return "Could not locate fixture \(name)."
            case .decodeFailed(let path):
                return "Could not decode PNG fixture at \(path)."
            }
        }
    }
    #endif
}
#endif
