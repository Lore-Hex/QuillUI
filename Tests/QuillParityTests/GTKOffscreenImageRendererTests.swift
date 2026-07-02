#if os(Linux)
import Foundation
import Testing
import SwiftUI
@_spi(QuillTesting) import QuillUI

@Suite("GTK offscreen ImageRenderer")
struct GTKOffscreenImageRendererTests {
    @Test(
        "GTK offscreen renderer produces PNG bytes for Text content",
        .disabled(
            if: ProcessInfo.processInfo.environment["QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER"] != "1",
            "Set QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1 under xvfb / Wayland to exercise the GTK offscreen renderer."
        )
    )
    @MainActor
    func gtkOffscreenRendererProducesPNGBytesForTextContent() async {
        quillInstallGTKImageRendererBackend()

        let renderer = ImageRenderer(content: Text("Quill"))
        guard let data = renderer.nsImage?.data else {
            Issue.record("GTK offscreen ImageRenderer should produce PNG bytes for Text content")
            return
        }

        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == pngMagic)
        #expect(data.count > pngMagic.count)
    }
}
#endif
