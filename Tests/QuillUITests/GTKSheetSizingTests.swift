#if os(Linux)
@testable import BackendGTK4
import Testing

@Suite("GTK sheet sizing")
struct GTKSheetSizingTests {
    @Test("Sheet width is clamped before its first frame")
    func clampsToHostWidth() {
        #expect(
            gtkClampedSheetPanelDimension(
                preferred: 900,
                hostSize: 810,
                margins: 32
            ) == 778
        )
    }

    @Test("Sheet height is clamped before its first frame")
    func clampsToHostHeight() {
        #expect(
            gtkClampedSheetPanelDimension(
                preferred: 650,
                hostSize: 656,
                margins: 32
            ) == 624
        )
    }

    @Test("An unallocated host keeps the preferred size")
    func unallocatedHostKeepsPreferredSize() {
        #expect(
            gtkClampedSheetPanelDimension(
                preferred: 900,
                hostSize: 0,
                margins: 32
            ) == 900
        )
    }

    @Test("A host smaller than its margins remains valid")
    func tinyHostUsesMinimumSize() {
        #expect(
            gtkClampedSheetPanelDimension(
                preferred: 900,
                hostSize: 16,
                margins: 32
            ) == 1
        )
    }

    @Test("The presentation root wins over an oversized overlay layer")
    func presentationRootWinsOverParent() {
        #expect(
            gtkSheetPanelHostDimension(
                presentationRootSize: 810,
                windowRootSize: 810,
                parentSize: 900,
                panelSize: 868
            ) == 810
        )
    }

    @Test("The window root is used before an oversized overlay layer")
    func windowRootWinsWhenPresentationRootIsUnallocated() {
        #expect(
            gtkSheetPanelHostDimension(
                presentationRootSize: 0,
                windowRootSize: 810,
                parentSize: 900,
                panelSize: 868
            ) == 810
        )
    }

    @Test("The overlay layer is the fallback when roots are unallocated")
    func parentIsFallbackForUnallocatedRoots() {
        #expect(
            gtkSheetPanelHostDimension(
                presentationRootSize: 0,
                windowRootSize: -1,
                parentSize: 720,
                panelSize: 680
            ) == 720
        )
    }

    @Test("The panel is the final sizing fallback")
    func panelIsFinalFallback() {
        #expect(
            gtkSheetPanelHostDimension(
                presentationRootSize: 0,
                windowRootSize: 0,
                parentSize: 0,
                panelSize: 640
            ) == 640
        )
    }
}
#endif
