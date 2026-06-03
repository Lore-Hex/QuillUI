import Testing
import AppKit
import QuillUIKit
@testable import QuillAppKitQt

/// M1 slice 1 (issue #231): prove the AppKit shadow's NSApplication/NSWindow are
/// backed by a real Qt6 widget on Linux — i.e. unmodified `import AppKit` code
/// drives Qt. Run headless with QT_QPA_PLATFORM=offscreen (CI/Docker). Mirrors
/// QuillAppKitGTK's Phase-B round-trip verification.
@Suite("QuillAppKitQt / Qt-backed AppKit (M1)")
@MainActor
struct QuillAppKitQtTests {

    @Test("NSWindow backs onto a real QWidget; title + size round-trip through the bridge")
    func windowRoundTrip() {
        guard QuillQt.ensureInitialized() else {
            // No Qt platform available (e.g. no offscreen plugin) — nothing to
            // assert; matches the headless no-op stub. Don't fail the suite.
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        window.title = "Manage WireGuard Tunnels"
        window.showAsQtWindow()

        // The stub now owns a live QWidget.
        #expect(window.qtWindowHandle != nil)
        // The C-side widget stored exactly what Swift wrote.
        #expect(window.qtWindowTitle == "Manage WireGuard Tunnels")
        let (w, h) = window.qtWindowSize
        #expect(w == 480 && h == 320)

        window.closeQtWindow()
        #expect(window.qtWindowHandle == nil)
    }

    @Test("The run hook is installed so NSApp.run() routes into Qt")
    func runHookInstalled() {
        #expect(QuillAppKitQtAutoInstall.didInstall)
        #expect(NSApplication._runHook != nil)
    }

    @Test("NSView hierarchy backs onto Qt: subviews become child QWidgets")
    func viewHierarchy() {
        guard QuillQt.ensureInitialized() else { return }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let a = NSView(frame: .zero)
        let b = NSView(frame: .zero)
        content.addSubviewQt(a)
        content.addSubviewQt(b)

        #expect(content.qtChildCount == 2)       // real QWidget children
        #expect(content.subviews.count == 2)     // AppKit subview list maintained too

        // Geometry round-trips through the bridge (the Auto Layout pass will
        // drive this in M2 slice 2).
        a.applyQtGeometry(x: 10, y: 20, width: 80, height: 30)
        let g = a.qtGeometry
        #expect(g.x == 10 && g.y == 20 && g.width == 80 && g.height == 30)
    }

    @Test("Auto Layout data model: constraints capture anchor bindings + activate into the global list")
    func constraintDataModel() {
        let a = NSView(frame: .zero)
        let b = NSView(frame: .zero)

        let c = a.leadingAnchor.constraint(equalTo: b.trailingAnchor, constant: 8)
        // Created inactive (matches AppKit); carries its bindings + parameters.
        #expect(c.isActive == false)
        #expect(c.quillConstant == 8)
        #expect(c.quillMultiplier == 1)
        #expect(c.quillFirstAnchor?.quillItem === a)
        #expect(c.quillFirstAnchor?.quillAttribute == .leading)
        #expect(c.quillSecondAnchor?.quillItem === b)
        #expect(c.quillSecondAnchor?.quillAttribute == .trailing)

        NSLayoutConstraint.activate([c])
        #expect(c.isActive == true)
        #expect(NSLayoutConstraint.quillActive.contains { $0 === c })

        // A constant dimension has no second anchor.
        let w = a.widthAnchor.constraint(equalToConstant: 120)
        w.isActive = true
        #expect(w.quillSecondAnchor == nil)
        #expect(w.quillConstant == 120)

        NSLayoutConstraint.deactivate([c, w])
        #expect(!NSLayoutConstraint.quillActive.contains { $0 === c })
        #expect(!NSLayoutConstraint.quillActive.contains { $0 === w })
    }

    @Test("NSWindow.contentView attaches its QWidget into the Qt window")
    func contentViewAttaches() {
        guard QuillQt.ensureInitialized() else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: .titled, backing: .buffered, defer: false
        )
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        let child = NSView(frame: .zero)
        content.addSubviewQt(child)
        window.contentView = content
        window.showAsQtWindowWithContent()

        #expect(window.qtWindowHandle != nil)
        #expect(content.qtChildCount == 1)
    }
}
