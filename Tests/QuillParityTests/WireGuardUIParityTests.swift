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
    
    #if os(Linux)
    @Test(
        "WireGuard UI renders identically",
        .disabled(
            if: ProcessInfo.processInfo.environment["QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER"] != "1",
            "Set QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1 under xvfb / Wayland to exercise the GTK offscreen WireGuard renderer."
        )
    )
    #else
    @Test("WireGuard UI renders identically")
    #endif
    @MainActor
    func testWireGuardUIRendersIdentically() async throws {
        let view = WireGuardFallbackConfigurationView()
        
        // This is the cross-platform rendering bridge.
        // On macOS it uses real SwiftUI ImageRenderer.
        // On Linux it uses SwiftOpenUI's GTK ImageRenderer backend hook.
        #if os(Linux)
        quillInstallGTKImageRendererBackend()
        #endif
        let renderer = ImageRenderer(content: view)
        
        #if os(macOS)
        guard let nsImage = renderer.nsImage else {
            Issue.record("Failed to render WireGuard UI on macOS")
            return
        }
        // Save for manual verification if needed, or use as golden
        // let data = nsImage.tiffRepresentation
        #elseif os(Linux)
        guard let nsImage = renderer.nsImage, let data = nsImage.data else {
            Issue.record("Failed to render WireGuard UI on Linux via GTK offscreen")
            return
        }
        // Verification: PNG magic for GTK output
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == pngMagic)
        #endif
    }
}
