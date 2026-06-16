// SolderScopeChromeConformanceTests.swift
//
// Conformance tests for the SwiftUI/AppKit chrome surface exercised by the
// REAL, unmodified SolderScope app (rjwalters/SolderScope). Every call shape
// below is copied from the app's own call sites:
//
//   App/ContentView.swift          — fonts, monospacedDigit, padding, Menu,
//                                    ToolbarButtonStyle, repeatForever
//   App/SolderScopeApp.swift       — WindowGroup + .windowStyle(.hiddenTitleBar)
//   App/SolderScopeCommands.swift  — CommandMenu of Buttons, .keyboardShortcut,
//                                    KeyEquivalent.space
//   Calibration/CalibrationOverlay.swift — addCursorRect in resetCursorRects
//   Recording/SnapshotManager.swift      — NSBitmapImageRep(cgImage:),
//                                    representation(using:properties:),
//                                    TIFFCompression, NSImage(cgImage:size:)
//   Renderer/MicroscopeView.swift  — NSCursor push/pop, .openHand cursor rect
//   Renderer/ScaleBarView.swift    — Button roles, alert actions/message builders
//
// The tests are compile-surface focused: the Linux shims behind these APIs are
// inert, so the runtime assertions are intentionally minimal (self-equality,
// non-nil, Apple-documented raw values). The value of each test is that the
// Apple-exact spelling from the app compiles against QuillUI's shadow modules.
// Each surface gets its own @Test so one regression doesn't mask the rest.
#if os(Linux)
import Glibc
import Testing
import SwiftUI
import SwiftOpenUI

// MARK: - Helpers

/// Forces the value to be constructed at runtime and gives each
/// compile-surface test a real (if minimal) assertion to anchor on.
private func builds<T>(_ value: T) -> Bool {
    !String(describing: value).isEmpty
}

// MARK: - File-scope fixtures (the app declares the same shapes at file scope)

/// Mirrors ContentView.swift's `ToolbarButtonStyle`: a custom `ButtonStyle`
/// conformer spelled with the protocol's bare `Configuration` typealias and
/// the `label` / `isPressed` configuration members.
private struct PressOpacityButtonStyle: SwiftOpenUI.ButtonStyle {
    typealias Configuration = SwiftOpenUI.ButtonStyleConfiguration

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Mirrors SolderScopeCommands.swift: a `Commands` conformer whose body is a
/// `CommandMenu` of `Button`s carrying `.keyboardShortcut` metadata.
private struct ZoomCommands: Commands {
    var body: some Commands {
        CommandMenu("View") {
            Button("Zoom In") {}
                .keyboardShortcut("]", modifiers: .command)
        }
    }
}

/// Mirrors CalibrationOverlay.swift's `CalibrationCanvasNSView` (and
/// MicroscopeView's `MicroscopeNSView`): a custom NSView that installs a
/// cursor rect inside `resetCursorRects()`.
private final class CrosshairCursorView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

/// Mirrors the mouse/scroll handling shape in Renderer/MicroscopeView.swift
/// without importing the upstream app target into this small conformance suite.
private final class MicroscopeInteractionProbeView: NSView {
    var zooms: [(factor: CGFloat, point: CGPoint)] = []
    var pans: [CGPoint] = []
    var resetCount = 0
    private var isDragging = false
    private var lastDragPoint: CGPoint = .zero

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let zoomFactor: CGFloat
        if event.hasPreciseScrollingDeltas {
            zoomFactor = 1.0 + event.scrollingDeltaY * 0.01
        } else {
            zoomFactor = event.scrollingDeltaY > 0 ? 1.1 : 0.9
        }
        zooms.append((zoomFactor, convert(event.locationInWindow, from: nil)))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            resetCount += 1
        } else {
            isDragging = true
            lastDragPoint = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        pans.append(CGPoint(
            x: currentPoint.x - lastDragPoint.x,
            y: currentPoint.y - lastDragPoint.y
        ))
        lastDragPoint = currentPoint
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        if isDragging {
            isDragging = false
            NSCursor.pop()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        _ = event
        if isDragging {
            NSCursor.closedHand.set()
        } else {
            NSCursor.openHand.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Tests

@Suite("SolderScope chrome conformance", .serialized)
@MainActor
struct SolderScopeChromeConformanceTests {

    // MARK: Font

    @Test func fontSystemTextStyleWithDesign() {
        // HUDView: .font(.system(.caption, design: .monospaced))
        let caption = Font.system(.caption, design: .monospaced)
        #expect(caption == Font.system(.caption, design: .monospaced))
        // FrozenIndicator / ScaleBarView: the design + weight call-site form
        // ("incorrect argument labels … (have '_:design:weight:')").
        let bold = Font.system(.caption, design: .monospaced, weight: .bold)
        #expect(bold == Font.system(.caption, design: .monospaced, weight: .bold))
        let semibold = Font.system(.caption, design: .monospaced, weight: .semibold)
        #expect(semibold == Font.system(.caption, design: .monospaced, weight: .semibold))
    }

    @Test func fontSystemTextStyleOnly() {
        let caption2 = Font.system(.caption2)
        #expect(caption2 == Font.system(.caption2))
        let title3 = Font.system(.title3)
        #expect(title3 == Font.system(.title3))
    }

    @Test func textMonospacedDigitFontChain() {
        // ContentView toolbar: Text("…").monospacedDigit() inside a font chain.
        let text = Text("12.3")
            .monospacedDigit()
            .font(.system(.caption, design: .monospaced))
        #expect(builds(text))
    }

    // MARK: Animation

    @Test func animationEaseInOutRepeatForever() {
        // RecordingIndicator: .animation(.easeInOut(duration: 0.5).repeatForever(), value:)
        let explicit = Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)
        #expect(explicit == Animation.easeInOut(duration: 1).repeatForever(autoreverses: true))
        // The app's spelling uses the defaulted argument.
        let defaulted = Animation.easeInOut(duration: 0.5).repeatForever()
        #expect(builds(defaulted))
    }

    // MARK: Padding

    @Test func paddingEdgeSetWithLength() {
        // ToolbarView: .padding(.horizontal, 16) / .padding(.vertical, 8)
        let padded = Text("pad")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        #expect(builds(padded))
    }

    // MARK: Menu

    @Test func menuContentLabelInitAndBorderlessButtonStyle() {
        // CameraPicker: Menu { … } label: { … } + .menuStyle(.borderlessButton)
        let menu = Menu {
            Button("a") {}
        } label: {
            Text("l")
        }
        let styled = menu.menuStyle(.borderlessButton)
        #expect(builds(styled))
    }

    // MARK: Button styles and roles

    @Test func customButtonStyleConformanceApplies() {
        // ContentView: .buttonStyle(ToolbarButtonStyle()) — the protocol-based
        // overload must coexist with the ButtonStyleType enum overload.
        let button = Button("press") {}
            .buttonStyle(PressOpacityButtonStyle())
        #expect(builds(button))
    }

    @Test func buttonRoleCancelAndDestructive() {
        // ScaleBarView alert actions: Button("Cancel", role: .cancel) { } and
        // Button("Delete", role: .destructive) { … }
        let cancel = Button("Cancel", role: .cancel) {}
        #expect(builds(cancel))
        #expect(cancel.role == .cancel)
        let destructive = Button("Delete", role: .destructive) {}
        #expect(builds(destructive))
        #expect(destructive.role == .destructive)
    }

    @Test func alertActionBuilderPreservesButtonRoles() {
        // ScaleBarView's SwiftUI-style alert builder must preserve role
        // metadata through the compatibility lowering so GTK can style
        // destructive actions and keep cancel semantics.
        let view = Text("scope").alert("Delete scale?", isPresented: .constant(true)) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {}
        } message: {
            Text("This cannot be undone.")
        }

        #expect(view.buttons.count == 2)
        #expect(view.buttons[0].label == "Cancel")
        #expect(view.buttons[0].role == .cancel)
        #expect(view.buttons[1].label == "Delete")
        #expect(view.buttons[1].role == .destructive)
        #expect(view.message == "This cannot be undone.")
    }

    @Test func nsAlertAutomationCanDriveAccessoryTextInput() {
        // CalibrationOverlay.showCustomLengthAlert(): NSAlert with Apply /
        // Cancel buttons and an NSTextField accessory. The shim can be driven
        // deterministically by smoke tests without requiring stdin.
        setenv("QUILLUI_NSALERT_RESPONSE", "Cancel", 1)
        setenv("QUILLUI_NSALERT_ACCESSORY_TEXT", "2.54 mm", 1)
        defer {
            unsetenv("QUILLUI_NSALERT_RESPONSE")
            unsetenv("QUILLUI_NSALERT_ACCESSORY_TEXT")
        }

        let alert = NSAlert()
        alert.messageText = "Enter Known Length"
        alert.informativeText = "Supports: mm, um, cm, in (default: mm)"
        alert.alertStyle = .informational
        _ = alert.addButton(withTitle: "Apply")
        _ = alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "e.g., 2.54 mm"
        alert.accessoryView = textField

        #expect(alert.runModal() == .alertSecondButtonReturn)
        #expect(textField.stringValue == "2.54 mm")
    }

    @Test func nsAlertBackendHookCanDriveAccessoryTextInput() {
        // Runtime backends such as QuillAppKitGTK install a modal presenter
        // through NSAlert._runModalHook. The hook must be able to update the
        // accessory field and return the exact AppKit response for the chosen
        // button without app-source changes.
        let previousHook = NSAlert._runModalHook
        NSAlert._runModalHook = { alert in
            alert.quillFirstAccessoryTextField()?.stringValue = "1.5 cm"
            return alert.quillResponse(forButtonAtOneBasedIndex: 2)
        }
        defer {
            NSAlert._runModalHook = previousHook
        }

        let alert = NSAlert()
        alert.messageText = "Enter Known Length"
        _ = alert.addButton(withTitle: "Apply")
        _ = alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField

        #expect(alert.runModal() == .alertSecondButtonReturn)
        #expect(textField.stringValue == "1.5 cm")
    }

    // MARK: Scenes

    /// Scene-typed context mirroring SolderScopeApp.body (the modifier must
    /// chain off a `WindowGroup` built without a title argument).
    private static func hiddenTitleBarStructScene() -> some Scene {
        WindowGroup { Text("x") }
            .windowStyle(HiddenTitleBarWindowStyle())
    }

    private static func hiddenTitleBarMemberScene() -> some Scene {
        WindowGroup { Text("x") }
            .windowStyle(.hiddenTitleBar)
    }

    @Test func windowStyleHiddenTitleBarStruct() {
        #expect(builds(Self.hiddenTitleBarStructScene()))
    }

    @Test func windowStyleHiddenTitleBarMember() {
        // SolderScopeApp uses the leading-dot spelling: .windowStyle(.hiddenTitleBar)
        #expect(builds(Self.hiddenTitleBarMemberScene()))
    }

    // MARK: Commands

    @Test func commandMenuOfButtonsWithKeyboardShortcut() {
        // SolderScopeCommands: CommandMenu("View") { Button(…).keyboardShortcut(…) }
        let commands = ZoomCommands()
        #expect(builds(commands.body))
    }

    @Test func commandMenuItemsExtractForBackendShortcuts() {
        // Hidden-title-bar SolderScope windows do not show an in-window GTK
        // menu bar, but the backend still needs the extracted command items
        // so keyboard shortcuts match the macOS app chrome.
        let items = extractCommandGroups(from: ZoomCommands())
            .values
            .flatMap { $0 }

        #expect(items.count == 1)
        #expect(items.first?.label == "Zoom In")
        #expect(items.first?.shortcut == KeyboardShortcut("]", modifiers: .command))
    }

    @Test func keyEquivalentSpaceExists() {
        // SolderScopeCommands: .keyboardShortcut(.space, modifiers: [])
        #expect(KeyEquivalent.space.character == " ")
    }

    @Test func onExitCommandPreservesCancelHandler() {
        // ContentView: `.onExitCommand { ... }` should be real Escape/cancel
        // command metadata, not a source-only no-op.
        var fired = 0
        let view = Text("exit").onExitCommand {
            fired += 1
        }
        #expect(builds(view))
        view.action?()
        #expect(fired == 1)

        let disabled = Text("exit").onExitCommand(perform: nil)
        #expect(disabled.action == nil)
    }

    @Test func cancelShortcutDispatchesWithinWindowScope() {
        // GTK backs onExitCommand with KeyboardShortcut.cancelAction, scoped
        // to the active window so one app window cannot steal another's Escape.
        let windowID = 93_501
        var fired = 0
        let id = KeyboardShortcutRegistry.shared.register(.cancelAction, windowID: windowID) {
            fired += 1
        }
        defer { KeyboardShortcutRegistry.shared.unregister(id: id) }

        #expect(KeyboardShortcutRegistry.shared.dispatch(.cancelAction, windowID: windowID))
        #expect(fired == 1)
        #expect(!KeyboardShortcutRegistry.shared.dispatch(.cancelAction, windowID: windowID + 1))
        #expect(fired == 1)
    }

    // MARK: NSCursor

    @Test func nsCursorPushAndStaticPop() {
        // MicroscopeNSView mouse handlers: NSCursor.closedHand.push() / NSCursor.pop()
        NSCursor.arrow.set()
        NSCursor.openHand.push()
        #expect(NSCursor.current === NSCursor.openHand)
        NSCursor.closedHand.push()
        #expect(NSCursor.current === NSCursor.closedHand)
        NSCursor.pop()
        #expect(NSCursor.current === NSCursor.openHand)
        NSCursor.pop()
        #expect(NSCursor.current === NSCursor.arrow)
    }

    @Test func addCursorRectInsideResetCursorRects() {
        // CalibrationCanvasNSView/MicroscopeNSView: addCursorRect(bounds, cursor:)
        let view = CrosshairCursorView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        view.resetCursorRects()
        #expect(builds(view))
        #expect(view.quillCursorRects.count == 1)
        #expect(view.quillCursor(at: NSPoint(x: 50, y: 40)) === NSCursor.crosshair)
        #expect(view.quillCursor(at: NSPoint(x: 120, y: 40)) == nil)
        view.discardCursorRects()
        #expect(view.quillCursorRects.isEmpty)
        #expect(view.quillCursor(at: NSPoint(x: 50, y: 40)) == nil)
    }

    @Test func microscopeMouseAndScrollEventsMatchAppHandlers() {
        // MicroscopeNSView.scrollWheel/mouseDown/mouseDragged/mouseUp:
        // GTK hosts synthesize these AppKit events so zoom-around-cursor and
        // drag-pan work without changing the upstream app.
        let view = MicroscopeInteractionProbeView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        view.resetCursorRects()
        NSCursor.openHand.set()

        let preciseScroll = NSEvent()
        preciseScroll.type = .scrollWheel
        preciseScroll.locationInWindow = CGPoint(x: 80, y: 40)
        preciseScroll.hasPreciseScrollingDeltas = true
        preciseScroll.scrollingDeltaY = 8
        view.scrollWheel(with: preciseScroll)
        #expect(view.zooms.count == 1)
        #expect(view.zooms[0].factor == 1.08)
        #expect(view.zooms[0].point == CGPoint(x: 80, y: 40))

        let wheelScroll = NSEvent()
        wheelScroll.type = .scrollWheel
        wheelScroll.locationInWindow = CGPoint(x: 90, y: 45)
        wheelScroll.scrollingDeltaY = -1
        view.scrollWheel(with: wheelScroll)
        #expect(view.zooms[1].factor == 0.9)

        let mouseDown = NSEvent()
        mouseDown.type = .leftMouseDown
        mouseDown.locationInWindow = CGPoint(x: 10, y: 10)
        view.mouseDown(with: mouseDown)
        #expect(NSCursor.current === NSCursor.closedHand)

        let mouseDrag = NSEvent()
        mouseDrag.type = .leftMouseDragged
        mouseDrag.locationInWindow = CGPoint(x: 25, y: 30)
        view.mouseDragged(with: mouseDrag)
        #expect(view.pans == [CGPoint(x: 15, y: 20)])

        let mouseUp = NSEvent()
        mouseUp.type = .leftMouseUp
        mouseUp.locationInWindow = CGPoint(x: 25, y: 30)
        view.mouseUp(with: mouseUp)
        #expect(NSCursor.current === NSCursor.openHand)

        let doubleClick = NSEvent()
        doubleClick.type = .leftMouseDown
        doubleClick.clickCount = 2
        doubleClick.locationInWindow = CGPoint(x: 50, y: 60)
        view.mouseDown(with: doubleClick)
        #expect(view.resetCount == 1)
    }

    // MARK: NSBitmapImageRep / NSImage

    @Test func bitmapImageRepFromCGImageRepresentations() {
        // SnapshotManager.saveImage: NSBitmapImageRep(cgImage:) +
        // representation(using:properties:) for every format the app writes.
        // (Optional-typed `let` so the test compiles against either a failable
        // or, as on Apple, non-failable init.)
        let rep: NSBitmapImageRep? = NSBitmapImageRep(cgImage: CGImage())
        #expect(rep != nil)
        let png = rep?.representation(using: .png, properties: [:])
        let tiff = rep?.representation(
            using: .tiff,
            properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw]
        )
        let jpeg = rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        // Inert codecs may hand back empty/pass-through bytes; the surface is
        // what matters here, not the encoding.
        _ = (png, tiff, jpeg)
    }

    @Test func tiffCompressionRawValue() {
        // Apple-exact raw value: NSBitmapImageRep.TIFFCompression.lzw == 5.
        #expect(NSBitmapImageRep.TIFFCompression.lzw.rawValue == 5)
    }

    @Test func nsImageFromCGImageAndSize() {
        // SnapshotManager.copyToClipboard: NSImage(cgImage: …, size: …)
        let image = NSImage(cgImage: CGImage(), size: .zero)
        #expect(builds(image))
    }

    // MARK: Alert

    @Test func alertWithActionsAndMessageBuilders() {
        // ScaleBarView: .alert("…", isPresented:) { Button(…) } message: { Text(…) }
        let view = Text("v")
            .alert("t", isPresented: .constant(false)) {
                Button("OK") {}
            } message: {
                Text("m")
            }
        #expect(builds(view))
    }
}
#endif
