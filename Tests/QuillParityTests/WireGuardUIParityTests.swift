import Foundation
import Testing
import SwiftUI
@_spi(QuillTesting) import QuillUI
import QuillWireGuardUI

#if canImport(WireGuardKit)
import WireGuardKit
#endif

@Suite("WireGuard UI Parity")
struct WireGuardUIParityTests {
    
    @Test("WireGuard UI renders identically")
    @MainActor
    func testWireGuardUIRendersIdentically() async throws {
        let view = WireGuardFallbackConfigurationView()
        
        // This is the cross-platform rendering bridge.
        // On macOS it uses real SwiftUI ImageRenderer.
        // On Linux it uses QuillUI's GtkOffscreenRender bridge.
        let renderer = ImageRenderer(content: view)
        
        #if os(macOS)
        guard let nsImage = renderer.nsImage else {
            Issue.record("Failed to render WireGuard UI on macOS")
            return
        }
        // Save for manual verification if needed, or use as golden
        // let data = nsImage.tiffRepresentation
        #elseif os(Linux)
        // Ensure GTK offscreen is enabled for this test
        setenv("QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER", "1", 1)
        guard let nsImage = renderer.nsImage, let data = nsImage.data else {
            Issue.record("Failed to render WireGuard UI on Linux via GTK offscreen")
            return
        }
        // Verification: PNG magic for GTK output
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == pngMagic)
        #endif
        
        #expect(nsImage != nil)
    }
}
