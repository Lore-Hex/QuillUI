import QuillInteractionSmokeSupport
import QuillUI
import Testing

@Suite("Backend interaction smoke configuration")
struct InteractionSmokeConfigurationTests {
    @Test("GTK and Qt smoke surfaces are visually identical")
    func backendParitySurfaceKeepsVisibleFieldsIdentical() {
        let gtk = QuillInteractionSmokeConfiguration.backendParitySurface(for: .gtk)
        let qt = QuillInteractionSmokeConfiguration.backendParitySurface(for: .qt)

        #expect(gtk.backend == .gtk)
        #expect(qt.backend == .qt)
        #expect(gtk.windowTitle == qt.windowTitle)
        #expect(gtk.title == qt.title)
        #expect(gtk.clickTargetTitle == qt.clickTargetTitle)
        #expect(gtk.panelMessage == qt.panelMessage)
        #expect(gtk.width == qt.width)
        #expect(gtk.height == qt.height)

        let visibleText = [
            gtk.windowTitle,
            gtk.title,
            gtk.clickTargetTitle,
            gtk.panelMessage
        ].joined(separator: " ").lowercased()

        #expect(!visibleText.contains("gtk"))
        #expect(!visibleText.contains("qt"))
    }
}
