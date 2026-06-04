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

    @Test("End-to-end: real NSLayoutConstraints solve via QuillAutoLayout and apply to Qt frames")
    func constraintSolveAndApply() {
        guard QuillQt.ensureInitialized() else { return }

        // A KeyValueRow built purely from NSView + NSLayoutConstraint: a
        // fixed-width name label and a value field stretching to the trailing
        // edge, both vertically centered.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 44))
        let name = NSView(frame: .zero)
        let value = NSView(frame: .zero)
        root.addSubviewQt(name)
        root.addSubviewQt(value)

        let constraints = [
            name.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            name.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            name.widthAnchor.constraint(equalToConstant: 80),
            name.heightAnchor.constraint(equalToConstant: 17),
            value.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            value.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            value.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            value.heightAnchor.constraint(equalToConstant: 22),
        ]
        NSLayoutConstraint.activate(constraints)
        defer { NSLayoutConstraint.deactivate(constraints) }

        root.layoutQtSubtree(width: 300, height: 44)

        // name: x=16, w=80, h=17; centerY=22 → y=13.5 → 14
        let n = name.qtGeometry
        #expect(n.x == 16 && n.width == 80 && n.height == 17 && n.y == 14)
        // value: x = name.trailing(96)+8 = 104; trailing = 300-16 = 284 → w=180;
        // h=22, centerY=22 → y=11
        let v = value.qtGeometry
        #expect(v.x == 104 && v.width == 180 && v.height == 22 && v.y == 11)
    }

    @Test("NSControl family: NSButton/NSTextField back onto Qt widgets with their text + lay out")
    func controlBacking() {
        guard QuillQt.ensureInitialized() else { return }

        let button = NSButton(title: "Import", target: nil, action: nil)
        button.ensureQtWidget()
        #expect(button.qtButtonTitle == "Import")   // created with the title
        button.title = "Save"
        button.syncQtTitle()
        #expect(button.qtButtonTitle == "Save")

        let label = NSTextField(labelWithString: "Public key:")
        label.ensureQtWidget()
        #expect(label.qtLabelText == "Public key:")

        // A control lays out via constraints like any NSView.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        root.addSubviewQt(button)
        let cs = [
            button.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            button.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 24),
        ]
        NSLayoutConstraint.activate(cs)
        defer { NSLayoutConstraint.deactivate(cs) }
        root.layoutQtSubtree(width: 200, height: 50)

        let g = button.qtGeometry
        #expect(g.x == 10 && g.y == 5 && g.width == 80 && g.height == 24)
    }

    @Test("NSView intrinsicContentSize / noIntrinsicMetric / prepareForReuse are overridable (KeyValueRow needs them)")
    func intrinsicContentSizeAPI() {
        // Mirrors EditableKeyValueRow, which overrides intrinsicContentSize to
        // NSSize(width: NSView.noIntrinsicMetric, height: ...) and prepareForReuse.
        final class Row: NSView {
            var reused = false
            override var intrinsicContentSize: NSSize {
                NSSize(width: NSView.noIntrinsicMetric, height: 34)
            }
            override func prepareForReuse() { reused = true }
        }
        #expect(NSView.noIntrinsicMetric == -1)
        let row = Row(frame: .zero)
        #expect(row.intrinsicContentSize.height == 34)
        #expect(row.intrinsicContentSize.width == NSView.noIntrinsicMetric)
        row.prepareForReuse()
        #expect(row.reused)
    }

    @Test("NSLayoutConstraint.Priority arithmetic + content-resistance API (KeyValueRow needs them)")
    func priorityAPI() {
        #expect(NSLayoutConstraint.Priority.defaultHigh.rawValue == 750)
        #expect((NSLayoutConstraint.Priority.defaultHigh + 1).rawValue == 751)
        #expect(NSLayoutConstraint.Priority.required.rawValue == 1000)

        let a = NSView(frame: .zero)
        let b = NSView(frame: .zero)
        let c = a.widthAnchor.constraint(equalToConstant: 150)
        c.priority = .defaultHigh + 1
        #expect(c.priority.rawValue == 751)

        // The content-resistance API (used by EditableKeyValueRow) compiles + runs.
        a.setContentHuggingPriority(.defaultLow, for: .horizontal)
        b.setContentCompressionResistancePriority(.defaultHigh + 2, for: .horizontal)
    }

    @Test("NSTextField.font is settable (real KeyValueRow sets keyLabel.font = NSFont.boldSystemFont)")
    func textFieldFont() {
        let label = NSTextField(labelWithString: "Key:")
        #expect(label.font == nil)
        label.font = NSFont.boldSystemFont(ofSize: 0)
        #expect(label.font != nil)
    }

    @Test("Solve honors constraint priority: a strong constraint beats a weaker one regardless of order")
    func prioritySolve() {
        guard QuillQt.ensureInitialized() else { return }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
        let box = NSView(frame: .zero)
        root.addSubviewQt(box)

        // Low priority listed FIRST, high SECOND: without priority mapping both
        // would be `required`, conflict, and the first (200) would win → 200.
        // With mapping, the strong 100 wins regardless of order → 100.
        let low = box.widthAnchor.constraint(equalToConstant: 200); low.priority = .defaultLow
        let high = box.widthAnchor.constraint(equalToConstant: 100); high.priority = .defaultHigh
        let cs = [
            box.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            box.topAnchor.constraint(equalTo: root.topAnchor),
            box.heightAnchor.constraint(equalToConstant: 10),
            low, high,
        ]
        NSLayoutConstraint.activate(cs)
        defer { NSLayoutConstraint.deactivate(cs) }
        root.layoutQtSubtree(width: 300, height: 50)
        #expect(box.qtGeometry.width == 100)
    }

    @Test("NSViewController subclass: init() needs no override + loadView/view work (AppKit init model)")
    func viewControllerInitModel() {
        // Mirrors how real ViewControllers (e.g. ButtonedDetailViewController) are
        // written: a designated init() that calls super.init(nibName:bundle:), with
        // NO `override` (because NSViewController.init() is now convenience).
        final class TestVC: NSViewController {
            var loaded = false
            init() { super.init(nibName: nil, bundle: nil) }
            required init?(coder: NSCoder) { fatalError("not implemented") }
            override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10)); loaded = true }
        }
        let vc = TestVC()
        vc.loadView()
        #expect(vc.loaded)
        #expect(vc.view.frame.width == 10)
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

    @Test("NSView.leftAnchor/rightAnchor solve as leading/trailing (LTR) — WireGuard VCs pin to them")
    func leftRightAnchors() {
        guard QuillQt.ensureInitialized() else { return }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let box = NSView(frame: .zero)
        root.addSubviewQt(box)
        let cs = [
            box.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 12),
            box.rightAnchor.constraint(equalTo: root.rightAnchor, constant: -8),
            box.topAnchor.constraint(equalTo: root.topAnchor),
            box.heightAnchor.constraint(equalToConstant: 10),
        ]
        NSLayoutConstraint.activate(cs)
        defer { NSLayoutConstraint.deactivate(cs) }
        root.layoutQtSubtree(width: 200, height: 40)
        let g = box.qtGeometry
        // left=12, right=200-8=192 → width=180
        #expect(g.x == 12 && g.width == 180)
    }

    @Test("NSStackView.addView(_:in:)/setViews(_:in:) manage arranged subviews (gravity-area API)")
    func stackViewGravityAPI() {
        let stack = NSStackView()
        let a = NSView(frame: .zero)
        let b = NSView(frame: .zero)
        stack.addView(a, in: .leading)
        stack.addView(b, in: .trailing)
        #expect(stack.arrangedSubviews.count == 2)
        #expect(stack.subviews.count == 2)

        let c = NSView(frame: .zero)
        stack.setViews([c], in: .leading)
        #expect(stack.arrangedSubviews.count == 1)
        #expect(stack.arrangedSubviews.first === c)
    }
}
