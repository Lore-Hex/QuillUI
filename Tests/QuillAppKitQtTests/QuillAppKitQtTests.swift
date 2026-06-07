import Testing
import AppKit
import QuillUIKit
@testable import QuillAppKitQt
#if canImport(QuillButtonedDetailConformance)
// The VERBATIM upstream WireGuard VC, compiled into the qt graph when the
// .upstream checkout is present (purist render path). Internal type → @testable.
@testable import QuillButtonedDetailConformance
#endif
#if canImport(QuillUnusableTunnelDetailConformance)
@testable import QuillUnusableTunnelDetailConformance
#endif

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

    @Test("Target-action dispatch: a control's fired action calls quillPerform on its target")
    func targetActionDispatch() {
        // Mirrors exactly what AppKitLowering generates: the app class conforms
        // to QuillActionDispatching with a switch over selector.name. No Qt
        // widget needed — this exercises the pure Swift dispatch contract.
        final class Recorder: QuillActionDispatching {
            var fired: [String] = []
            weak var lastSender: AnyObject?
            func quillPerform(_ selector: Selector, with sender: Any?) {
                lastSender = sender as AnyObject?
                switch selector.name {
                case "save": fired.append("save")
                case "cancel": fired.append("cancel")
                default: break
                }
            }
        }
        let target = Recorder()
        let button = NSButton(title: "Save", target: target, action: Selector("save"))

        button.performClick(nil)
        #expect(target.fired == ["save"])
        // The firing control is handed to the action as sender (AppKit contract).
        #expect(target.lastSender === button)

        // sendAction with an explicit selector + receiver also dispatches.
        button.sendAction(Selector("cancel"), to: target)
        #expect(target.fired == ["save", "cancel"])

        // A disabled control fires nothing.
        button.isEnabled = false
        button.performClick(nil)
        #expect(target.fired == ["save", "cancel"])

        // An unknown selector is a safe no-op (default protocol impl path / no case).
        button.isEnabled = true
        button.sendAction(Selector("unknownAction"), to: target)
        #expect(target.fired == ["save", "cancel"])
    }

    // M-render slice (issue #231): the first END-TO-END proof that unmodified
    // AppKit code RENDERS on Qt — build an NSWindow with a content view, a label
    // and a button, solve Auto Layout, and grab the live QWidget tree to a PNG.
    // This is the foundation for AppKit↔macOS visual parity (diff this PNG vs a
    // macOS screenshot). Headless via QT_QPA_PLATFORM=offscreen.
    @Test("A real AppKit window (label + button, Auto-Layout'd) renders to a non-empty PNG via Qt")
    func rendersRealAppKitWindowToPNG() throws {
        guard QuillQt.ensureInitialized() else { return }

        // Built exactly as unmodified AppKit source would — no Qt symbols here.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask: .titled, backing: .buffered, defer: false
        )
        window.title = "WireGuard"

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
        let label = NSTextField(labelWithString: "Add an empty tunnel or import one")
        let button = NSButton(title: "Import Tunnels", target: nil, action: nil)
        label.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubviewQt(label)
        content.addSubviewQt(button)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            label.widthAnchor.constraint(equalToConstant: 240),
            label.heightAnchor.constraint(equalToConstant: 20),
            button.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 18),
            button.widthAnchor.constraint(equalToConstant: 160),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])

        window.contentView = content
        content.layoutQtSubtree(width: 360, height: 140)
        window.showAsQtWindowWithContent()

        let out = "/tmp/quillappkitqt-wireguard-render.png"
        #expect(window.grabQtWindowPNG(to: out))
        // A real rendered 360×140 window is several KB of PNG, not an empty file.
        let size = ((try? FileManager.default.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
        #expect(size > 500)

        window.closeQtWindow()
    }

    // M-render: render a real NSViewController whose view is built in loadView()
    // (the shape of WireGuard's ButtonedDetailViewController empty state — a
    // centered button). Exercises the new NSViewController lazy `.view` →
    // loadView() path + realizeQtSubtree() (realizing a plain-addSubview tree
    // into Qt). The literal conformance VC is the identical shape; rendering it
    // verbatim needs the WireGuard conformance + a Qt backend in one graph (the
    // next rung — they're currently in separate build graphs).
    @Test("A loadView()-built NSViewController (empty-state shape) renders via Qt")
    func rendersViewControllerToPNG() throws {
        guard QuillQt.ensureInitialized() else { return }

        final class EmptyStateVC: NSViewController {
            let button = NSButton()
            override func loadView() {
                let v = NSView()
                button.title = "Import tunnels"
                v.addSubview(button) // plain addSubview, exactly like the real VC
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                    button.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                    button.widthAnchor.constraint(equalToConstant: 150),
                    button.heightAnchor.constraint(equalToConstant: 30),
                ])
                self.view = v
            }
        }

        let vc = EmptyStateVC()
        #expect(!vc.isViewLoaded)
        let content = vc.view          // triggers loadView() (the new lazy path)
        #expect(vc.isViewLoaded)
        #expect(content.subviews.count == 1) // the button is in the loaded tree

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: .titled, backing: .buffered, defer: false
        )
        window.title = "WireGuard"
        window.contentView = content
        content.realizeQtSubtree()              // realize the loadView-built tree into Qt
        content.layoutQtSubtree(width: 360, height: 160)
        window.showAsQtWindowWithContent()

        let out = "/tmp/quillappkitqt-vc-render.png"
        #expect(window.grabQtWindowPNG(to: out))
        let size = ((try? FileManager.default.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
        #expect(size > 500)
        window.closeQtWindow()
    }

    // M-render (purist path): render the LITERAL upstream WireGuard
    // ButtonedDetailViewController — the VERBATIM .upstream source file compiled
    // into QuillButtonedDetailConformance, NOT a hand-written twin — through
    // QuillAppKit→Qt. The real VC pins its button by center only (no width/height
    // constraint), so this also exercises the intrinsic-size fallback in the Qt
    // layout pass: the button must solve to a non-zero size, not collapse to 0×0.
    @Test("The LITERAL upstream ButtonedDetailViewController renders to a non-empty PNG via Qt")
    func rendersLiteralButtonedDetailVCToPNG() throws {
        #if canImport(QuillButtonedDetailConformance)
        guard QuillQt.ensureInitialized() else { return }

        let vc = ButtonedDetailViewController()   // the VERBATIM upstream type
        vc.setButtonTitle("Import tunnels")        // real upstream API
        #expect(!vc.isViewLoaded)
        let content = vc.view                      // triggers the real loadView()
        #expect(vc.isViewLoaded)
        #expect(content.subviews.count == 1)       // the button is in the loaded tree

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160), // ≥ the VC's 320×120 min
            styleMask: .titled, backing: .buffered, defer: false
        )
        window.title = "WireGuard"
        window.contentView = content
        content.realizeQtSubtree()                 // realize the loadView-built tree into Qt
        content.layoutQtSubtree(width: 360, height: 160)

        // The teeth of the rung: the center-pinned button (no size constraint of
        // its own) must get a real, non-zero solved size from the intrinsic-size
        // fallback — a blank window can still exceed the byte threshold.
        let button = content.subviews[0]
        #expect(button.frame.width > 0)
        #expect(button.frame.height > 0)

        window.showAsQtWindowWithContent()
        let out = "/tmp/quillappkitqt-buttoned-detail.png"
        #expect(window.grabQtWindowPNG(to: out))
        let size = ((try? FileManager.default.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
        #expect(size > 500)
        window.closeQtWindow()
        #endif
    }

    // Rung A (toward rendering the literal UnusableTunnelDetailViewController and
    // most remaining stacked VCs): NSTextField must size to its text so labels in
    // an NSStackView don't collapse to 0×0 in the Qt layout pass.
    @Test("NSTextField sizes to its text: single-line + wrapping intrinsicContentSize")
    func textFieldIntrinsicContentSize() {
        let label = NSTextField(labelWithString: "Public key:")
        #expect(label.intrinsicContentSize.width > 0)
        #expect(label.intrinsicContentSize.height == 17)

        // A wrapping label with a long string + a bounded width grows to multiple
        // lines (height > one line) and stays within the bound.
        let wrap = NSTextField(wrappingLabelWithString: String(repeating: "wide ", count: 40))
        wrap.preferredMaxLayoutWidth = 100
        #expect(wrap.intrinsicContentSize.width <= 100)
        #expect(wrap.intrinsicContentSize.height > 17)
    }

    // Rung A: NSStackView must emit real child-positioning constraints so its
    // arranged subviews solve to separated, non-zero frames via the Qt Auto
    // Layout pass — the shadow's addArrangedSubview only records the views.
    @Test("NSStackView synthesizes child constraints: arranged subviews solve to separated, non-zero frames")
    func stackViewLaysOutArrangedSubviews() {
        guard QuillQt.ensureInitialized() else { return }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let title = NSTextField(labelWithString: "Title")
        let subtitle = NSTextField(labelWithString: "Subtitle goes here")
        let action = NSButton(title: "Action", target: nil, action: nil)
        let stack = NSStackView(views: [title, subtitle, action])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        root.addSubviewQt(stack)

        // Pin the stack's position + cross size; leave its main-axis (vertical)
        // size to derive from the synthesized child chain — the stack has no
        // intrinsic size of its own.
        let pins = [
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ]
        NSLayoutConstraint.activate(pins)
        defer { NSLayoutConstraint.deactivate(pins) }

        root.realizeQtSubtree()
        root.layoutQtSubtree(width: 300, height: 200)

        let children = stack.arrangedSubviews
        #expect(children.count == 3)
        // Every arranged subview got a real, non-zero size from the synthesized
        // constraints (cross-axis fill) + intrinsic-size fallback (heights).
        for c in children {
            #expect(c.frame.width > 0)
            #expect(c.frame.height > 0)
        }
        // Cross-axis fill: children span the stack width (300 − 12 − 12 = 276),
        // NOT just their ~intrinsic text width — proves the stack pinned them.
        #expect(children[0].frame.width > 200)
        // Stacked vertically with strictly increasing y — not overlapping at 0,0.
        #expect(children[1].frame.minY > children[0].frame.minY)
        #expect(children[2].frame.minY > children[1].frame.minY)
    }

    // Rung B: render the LITERAL upstream UnusableTunnelDetailViewController — the
    // VERBATIM .upstream source (VC + LocalizationHelper, via the symlink-dir
    // conformance target), NOT a twin — through QuillAppKit→Qt. First literal VC
    // with a real NSStackView of multiple controls (bold label + wrapping label +
    // button), exercising Rung A's stack synthesis + label intrinsic sizing on the
    // real file, including its setCustomSpacing(30, after: infoLabel).
    @Test("The LITERAL upstream UnusableTunnelDetailViewController renders to a non-empty PNG via Qt")
    func rendersLiteralUnusableTunnelDetailVCToPNG() throws {
        #if canImport(QuillUnusableTunnelDetailConformance)
        guard QuillQt.ensureInitialized() else { return }

        let vc = UnusableTunnelDetailViewController()   // the VERBATIM upstream type
        #expect(!vc.isViewLoaded)
        let content = vc.view                            // triggers the real loadView()
        #expect(vc.isViewLoaded)
        #expect(content.subviews.count == 1)             // the stackView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320), // ≥ the VC's 420×240 min
            styleMask: .titled, backing: .buffered, defer: false
        )
        window.title = "WireGuard"
        window.contentView = content
        content.realizeQtSubtree()
        content.layoutQtSubtree(width: 460, height: 320)

        // The teeth: the stack's 3 arranged children (bold label, wrapping label,
        // button) each solved to a real, non-zero size AND are vertically stacked
        // (not overlapping at the origin) — proving Rung A's NSStackView synthesis +
        // NSTextField intrinsic size carry a real multi-control VC verbatim.
        let stack = content.subviews[0]
        let rows = stack.subviews
        #expect(rows.count == 3)
        for r in rows {
            #expect(r.frame.width > 0)
            #expect(r.frame.height > 0)
        }
        #expect(rows[1].frame.minY > rows[0].frame.minY)
        #expect(rows[2].frame.minY > rows[1].frame.minY)

        window.showAsQtWindowWithContent()
        let out = "/tmp/quillappkitqt-unusable-tunnel.png"
        #expect(window.grabQtWindowPNG(to: out))
        let size = ((try? FileManager.default.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
        #expect(size > 500)
        window.closeQtWindow()
        #endif
    }
}
