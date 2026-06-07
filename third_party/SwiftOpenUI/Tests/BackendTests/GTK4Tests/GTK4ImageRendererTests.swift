import XCTest
import Foundation
import SwiftOpenUI
@testable import BackendGTK4
import CGTK

final class GTK4ImageRendererTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
        installGTK4ImageRendererBackend()
    }

    func testImageRendererRendersColoredViewToPNGBytes() throws {
        try requireGTK()

        let renderer = ImageRenderer(content: Color.red.frame(width: 24, height: 16))
        renderer.proposedSize = CGSize(width: 24, height: 16)

        guard let data = renderer.nsImage?.data else {
            XCTFail("Expected GTK ImageRenderer to produce PNG bytes")
            return
        }

        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(data.prefix(8)), pngMagic)
        XCTAssertGreaterThan(data.count, 32)
        XCTAssertNotNil(renderer.cgImage?.data)
    }
}

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if gtk_is_initialized() == 0, gtk_init_check() == 0 {
        throw XCTSkip("GTK display is unavailable", file: file, line: line)
    }
}
