#if os(Linux)
import Foundation
import Testing
import CGdkPixbuf
import QuillPaint
@testable import QuillUIGtk

@Suite("QuillUIGtk Cairo button rendering")
struct QuillGtkCairoButtonRenderTests {
    @Test("Cairo MacButtonPaint output matches the CG reference within tolerance 4")
    func cairoButtonMatchesCGReference() throws {
        guard let candidate = QuillGtkCairoButtonRenderer.renderButtonImage() else {
            Issue.record("Cairo button renderer did not produce an image")
            return
        }

        let fixtureURL = try Self.locateFixtureURL(name: "linux-button-cairo-vs-cg.png")
        let reference = try Self.loadPixbufRGBA(from: fixtureURL)

        #expect(reference.width == candidate.width)
        #expect(reference.height == candidate.height)
        guard reference.width == candidate.width, reference.height == candidate.height else {
            return
        }

        let result = try PixelComparator(tolerance: 4).compare(
            reference: reference.rgba,
            candidate: candidate.rgba,
            width: reference.width,
            height: reference.height
        )

        #expect(
            result.passes,
            "Cairo button drifted from CG fixture: maxChannelDelta=\(result.maxChannelDelta), differingPixels=\(result.differingPixels)/\(result.totalPixels)"
        )
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

        throw FixtureError.notFound(name)
    }

    private static func loadPixbufRGBA(from url: URL) throws -> QuillGtkCairoImage {
        var error: UnsafeMutablePointer<GError>?
        guard let pixbuf = gdk_pixbuf_new_from_file(url.path, &error) else {
            if let error {
                g_error_free(error)
            }
            throw FixtureError.decodeFailed(url.path)
        }
        defer { g_object_unref(gpointer(pixbuf)) }

        let width = Int(gdk_pixbuf_get_width(pixbuf))
        let height = Int(gdk_pixbuf_get_height(pixbuf))
        let rowstride = Int(gdk_pixbuf_get_rowstride(pixbuf))
        let channels = Int(gdk_pixbuf_get_n_channels(pixbuf))
        let hasAlpha = gdk_pixbuf_get_has_alpha(pixbuf) != 0
        guard width > 0, height > 0, channels >= 3, let sourcePixels = gdk_pixbuf_get_pixels(pixbuf) else {
            throw FixtureError.decodeFailed(url.path)
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

        return QuillGtkCairoImage(width: width, height: height, rgba: rgba)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case notFound(String)
        case decodeFailed(String)

        var description: String {
            switch self {
            case .notFound(let name):
                return "Could not locate fixture \(name)"
            case .decodeFailed(let path):
                return "Could not decode PNG fixture at \(path)"
            }
        }
    }
}
#endif
