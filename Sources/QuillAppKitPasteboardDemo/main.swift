// QuillAppKitPasteboardDemo
// =========================
// Linux runtime demo proving Phase B AppKit backings actually flow
// real data on Linux:
//
//   • NSPasteboard.general — round-trips a string and binary data.
//     Tier picked at runtime: wl-copy/wl-paste on Wayland, xclip on
//     X11, file-backed at \$XDG_RUNTIME_DIR otherwise.
//   • NSWorkspace.shared — xdg-open detection via xdg-mime.
//   • NSSound.beep() — terminal bell.
//
// On macOS the real frameworks win via the SDK and this demo target
// isn't built (it's gated to `os(Linux)` in Package.swift).

import AppKit
import QuillAppKitGTK
import Foundation

@main
struct PasteboardDemo {
    static func main() {
        let pb = NSPasteboard.general
        let initialChange = pb.changeCount

        let payload = "Hello from QuillAppKit @ \(Date()) — pid \(ProcessInfo.processInfo.processIdentifier)"
        print("[write] \(payload)")
        _ = pb.clearContents()
        _ = pb.setString(payload, forType: .string)

        let readBack = pb.string(forType: .string)
        print("[read]  \(readBack ?? "<nil>")")
        print("[change] \(initialChange) → \(pb.changeCount)")

        let ok = readBack == payload
        let typeCount = pb.types()?.count ?? 0
        print("[types] \(typeCount) recorded types")
        print("[result] \(ok ? "✅ round-trip succeeded" : "❌ round-trip mismatch")")

        // Also exercise data path
        let bytes = Data("binary-payload".utf8)
        _ = pb.setData(bytes, forType: NSPasteboard.PasteboardType(rawValue: "com.quill.test"))
        let bytesBack = pb.data(forType: NSPasteboard.PasteboardType(rawValue: "com.quill.test"))
        let dataOK = bytesBack == bytes
        print("[binary] \(dataOK ? "✅ data round-trip" : "❌ data mismatch")")

        // NSWorkspace tier-2 check: just probe that the API doesn't
        // explode and that xdg-open detection runs. We don't actually
        // dispatch a browser open because there's no display in the VM.
        let ws = NSWorkspace.shared
        let appURL = ws.urlForApplication(toOpen: URL(string: "https://example.com")!)
        print("[workspace] urlForApplication(https) → \(appURL?.lastPathComponent ?? "<nil>")")

        // NSSound.beep — emits BEL to stderr. Harmless; just prove the
        // call executes without crashing.
        NSSound.beep()
        print("[sound] NSSound.beep() emitted")

        // NSAlert — prints the message + buttons to stderr. With no
        // interactive stdin we get .alertFirstButtonReturn back.
        runAlertCheck()

        // NSColor real components round-trip
        let c = NSColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0)
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let colorOK = r == 0.25 && g == 0.5 && b == 0.75
        print("[color] redComponent=\(r) green=\(g) blue=\(b) → \(colorOK ? "✅" : "❌")")

        // NSScreen real-ish bounds (NSScreen.main is non-optional in
        // the Linux shim; matches Apple's behavior in practice).
        let screenBounds = NSScreen.main.bounds
        print("[screen] main.bounds = \(Int(screenBounds.width))x\(Int(screenBounds.height))")

        // NSWindow + GTK init probe (no-op when headless)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "QuillAppKit Phase B Window"
        win.showAsGtkWindow()
        let gtkOK = QuillGTK.ensureInitialized()
        if gtkOK {
            let hasHandle = win.gtkWindowHandle != nil
            print("[gtk] initialized; gtkWindowHandle = \(hasHandle ? "✓" : "✗") title=\"\(win.title)\"")
            // Phase B end-to-end proof: read state back from the
            // underlying GtkWindow C struct via gtk_window_get_*.
            // If our Swift NSWindow wrote it, GTK should have it.
            let gtkTitle = win.gtkWindowTitle ?? "<nil>"
            let (gw, gh) = win.gtkWindowDefaultSize
            let titleOK = gtkTitle == win.title
            let sizeOK = gw == 640 && gh == 480
            print("[gtk] gtk_window_get_title → \"\(gtkTitle)\" \(titleOK ? "✅" : "❌")")
            print("[gtk] gtk_window_get_default_size → \(gw)x\(gh) \(sizeOK ? "✅" : "❌")")
            // Build a content view + label and prove the widget tree
            // exists in GTK after attaching.
            let contentView = NSView()
            let label = NSTextField.labelWithString("Hello from QuillAppKit on Linux")
            _ = label.ensureGtkLabel()
            contentView.addSubviewGTK(label)
            win.contentView = contentView
            win.attachContentViewToGtk()
            let cvHasWidget = contentView.gtkWidgetHandle != nil
            let labelHasWidget = label.gtkWidgetHandle != nil
            print("[gtk] contentView GtkBox = \(cvHasWidget ? "✅" : "❌")  label GtkLabel = \(labelHasWidget ? "✅" : "❌")")

            // NSButton with a Linux-friendly click closure → GtkButton
            // with "clicked" signal connected. Clicking the GtkButton
            // (programmatically here) fires the closure.
            let btn = NSButton(title: "Click me", target: nil, action: nil)
            var clickCount = 0
            btn.setOnClick { clickCount += 1 }
            _ = btn.ensureGtkButton()
            contentView.addSubviewGTK(btn)
            print("[gtk] button GtkButton = \(btn.gtkWidgetHandle != nil ? "✅" : "❌") title=\"\(btn.title)\"")
            // Programmatically activate the button (gtk_widget_activate
            // emits the "clicked" signal). Verify the closure ran.
            btn.gtkClick()
            btn.gtkClick()
            btn.gtkClick()
            QuillGTK.iterate(times: 10)
            print("[gtk] gtkClick() x3 → handler ran \(clickCount) time\(clickCount == 1 ? "" : "s") \(clickCount == 3 ? "✅" : "❌")")

            // Editable NSTextField → GtkEntry with text-changed signal.
            let entry = NSTextField()
            entry.stringValue = "initial"
            _ = entry.ensureGtkEntry()
            var changeCount = 0
            var lastText = ""
            entry.setOnTextChanged { newText in
                changeCount += 1
                lastText = newText
            }
            // entry will be added via the .stack below
            entry.gtkEntrySetText("hello world")
            QuillGTK.iterate(times: 5)
            let entryReadback = entry.gtkEntryText ?? "<nil>"
            print("[gtk] entry GtkEntry = \(entry.gtkWidgetHandle != nil ? "✅" : "❌") readback=\"\(entryReadback)\"")
            print("[gtk] textChanged fired \(changeCount)x, lastText=\"\(lastText)\" \(lastText == "hello world" ? "✅" : "❌")")

            // NSScrollView → GtkScrolledWindow + NSImageView → GtkImage
            let scroll = NSScrollView()
            let scrollContent = NSView()
            scroll.documentView = scrollContent
            _ = scroll.ensureGtkScrolledWindow()
            let img = NSImageView()
            _ = img.ensureGtkImage()
            print("[gtk] scrollview GtkScrolledWindow = \(scroll.gtkWidgetHandle != nil ? "✅" : "❌")")
            print("[gtk] imageview GtkImage = \(img.gtkWidgetHandle != nil ? "✅" : "❌")")

            // NSSlider → GtkScale: set value, read back through GTK.
            let slider = NSSlider()
            slider.minValue = 0
            slider.maxValue = 100
            slider.doubleValue = 42
            _ = slider.ensureGtkScale()
            slider.gtkScaleSetValue(73)
            let sliderReadback = slider.gtkScaleValue
            print("[gtk] slider GtkScale = \(slider.gtkWidgetHandle != nil ? "✅" : "❌") value=\(sliderReadback) \(sliderReadback == 73 ? "✅" : "❌")")

            // NSStackView → GtkBox with explicit horizontal orientation.
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 8
            _ = stack.ensureGtkStackBox()
            print("[gtk] stackview GtkBox = \(stack.gtkWidgetHandle != nil ? "✅" : "❌")")

            // NSProgressIndicator (bar): show fraction round-trip.
            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.minValue = 0
            progress.maxValue = 100
            progress.doubleValue = 50
            _ = progress.ensureGtkProgressIndicator()
            print("[gtk] progress (bar) GtkProgressBar = \(progress.gtkWidgetHandle != nil ? "✅" : "❌")")

            // NSProgressIndicator (spinning): GtkSpinner.
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            _ = spinner.ensureGtkProgressIndicator()
            print("[gtk] progress (spinning) GtkSpinner = \(spinner.gtkWidgetHandle != nil ? "✅" : "❌")")

            // NSPopUpButton → GtkDropDown
            let popup = NSPopUpButton()
            popup.menu = NSMenu()
            popup.addItem(withTitle: "Apple")
            popup.addItem(withTitle: "Banana")
            popup.addItem(withTitle: "Cherry")
            _ = popup.ensureGtkDropDown()
            popup.gtkDropDownSelect(2)
            let popupSel = popup.gtkDropDownSelectedIndex
            print("[gtk] popup GtkDropDown = \(popup.gtkWidgetHandle != nil ? "✅" : "❌") selectedIndex=\(popupSel) \(popupSel == 2 ? "✅" : "❌")")

            // Checkbox / radio (NSButton + ensureGtkCheckButton)
            let checkbox = NSButton(title: "Remember me", target: nil, action: nil)
            checkbox.state = .on
            _ = checkbox.ensureGtkCheckButton()
            let checkActive = checkbox.gtkCheckButtonActive
            checkbox.gtkCheckButtonSetActive(false)
            let checkAfter = checkbox.gtkCheckButtonActive
            print("[gtk] checkbox GtkCheckButton = \(checkbox.gtkWidgetHandle != nil ? "✅" : "❌") initial=\(checkActive) afterToggle=\(checkAfter) \(checkActive && !checkAfter ? "✅" : "❌")")

            // Radio group: 2 buttons sharing a group.
            let r1 = NSButton(title: "Option A", target: nil, action: nil)
            let r2 = NSButton(title: "Option B", target: nil, action: nil)
            _ = r1.ensureGtkCheckButton()
            _ = r2.ensureGtkCheckButton(group: r1)
            r2.gtkCheckButtonSetActive(true)
            let r1Active = r1.gtkCheckButtonActive
            let r2Active = r2.gtkCheckButtonActive
            print("[gtk] radio group: r1=\(r1Active) r2=\(r2Active) \(r1Active == false && r2Active == true ? "✅" : "❌")")

            // Pack everything into the contentView so they render
            // visibly under matchbox-window-manager. addSubviewGTK
            // appends to the GtkBox child list; the box auto-sizes.
            contentView.addSubviewGTK(entry)
            contentView.addSubviewGTK(slider)
            contentView.addSubviewGTK(progress)
            contentView.addSubviewGTK(popup)
            contentView.addSubviewGTK(checkbox)
            contentView.addSubviewGTK(r1)
            contentView.addSubviewGTK(r2)
            // Pump enough events so GTK lays out all the new children
            // before the screenshot tool fires.
            QuillGTK.iterate(times: 500)

            // Pump some events so the window renders if we're holding
            // it open for screenshot capture.
            QuillGTK.iterate(times: 50)
            // Hold for QUILL_DEMO_HOLD seconds so external screenshot
            // tools can capture the window. Default 0 = exit immediately.
            if let hold = ProcessInfo.processInfo.environment["QUILL_DEMO_HOLD"],
               let secs = Double(hold), secs > 0 {
                print("[gtk] holding window open for \(secs)s")
                Thread.sleep(forTimeInterval: secs)
            }
            win.closeGtkWindow()
        } else {
            print("[gtk] no display — NSWindow.showAsGtkWindow() was a no-op (correct headless behavior)")
        }

        if !ok || !dataOK { exit(1) }
    }

    @MainActor
    static func runAlertCheck() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Phase B alert demo"
        alert.informativeText = "This dialog was emitted from QuillAppKit's NSAlert backing."
        _ = alert.addButton(withTitle: "OK")
        _ = alert.addButton(withTitle: "Cancel")
        let resp = alert.runModal()
        let label = (resp == .alertFirstButtonReturn) ? "first" : "other"
        print("[alert] runModal returned \(label) button response (\(resp.rawValue))")
    }
}
