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
import Testing
import SwiftUI

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
private struct PressOpacityButtonStyle: ButtonStyle {
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

// MARK: - Tests

@Suite("SolderScope chrome conformance")
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
        let destructive = Button("Delete", role: .destructive) {}
        #expect(builds(destructive))
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

    @Test func keyEquivalentSpaceExists() {
        // SolderScopeCommands: .keyboardShortcut(.space, modifiers: [])
        #expect(KeyEquivalent.space.character == " ")
    }

    // MARK: NSCursor

    @Test func nsCursorPushAndStaticPop() {
        // MicroscopeNSView mouse handlers: NSCursor.closedHand.push() / NSCursor.pop()
        NSCursor.openHand.push()
        NSCursor.pop()
        #expect(NSCursor.openHand === NSCursor.openHand)
    }

    @Test func addCursorRectInsideResetCursorRects() {
        // CalibrationCanvasNSView/MicroscopeNSView: addCursorRect(bounds, cursor:)
        let view = CrosshairCursorView(frame: .zero)
        view.resetCursorRects()
        #expect(builds(view))
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
