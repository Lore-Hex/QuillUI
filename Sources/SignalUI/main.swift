//
// signal-ui -- a native QuillOS window for the real Signal-iOS device.
//
// This is the visual half of Track B: QuillUI's SwiftUI-on-GTK frontend rendering
// the state of the REAL signalapp/Signal-iOS SignalServiceKit backend that linked
// this machine as a Signal device. It reads the durably-persisted linked-account
// record (written by the live link flow into the qs-work DB via the real SSK
// account/identity stores) and presents it as a Signal-branded card -- proving,
// in one window, that Signal's own SSK is running natively on Linux AND that
// QuillUI can host it. Display-only in this first cut (no network); the live
// "connected" indicator + message list build on top of this.
//
import Foundation
import SignalServiceKit
import QuillUI
import QuillUIGtk

// Where the live link flow persisted the durable account (qs-work volume in the
// container; overridable via QUILL_SIGNAL_DB).
func quillSignalUIDBPath() -> String {
    if let p = ProcessInfo.processInfo.environment["QUILL_SIGNAL_DB"], !p.isEmpty { return p }
    if FileManager.default.fileExists(atPath: "/work") { return "/work/quill-signal-account.sqlite" }
    return FileManager.default.temporaryDirectory.appendingPathComponent("quill-signal-account.sqlite").path
}

// MARK: - Brand palette

private enum SignalBrand {
    static let blue = "#3A76F0"        // Signal's accent blue
    static let blueDark = "#2456C4"
    static let ink = "#1B1B1F"
    static let subtle = "#6A6A70"
    static let hairline = "#E4E4E8"
    static let surface = "#FFFFFF"
    static let canvas = "#F5F6F8"
    static let green = "#2FAE60"
}

// MARK: - App

struct SignalDemoApp: App {
    init() {}
    var body: some Scene {
        QuillAppWindow.scene(
            "Signal · QuillOS",
            width: 440,
            height: 720,
            defaultSizePolicy: .requested
        ) {
            SignalDemoView()
        }
    }
}

struct SignalDemoView: View {
    private let account: QuillAccountDisplay?

    init() {
        self.account = quillLoadAccountDisplay(path: quillSignalUIDBPath())
    }

    // Color fills via .background (GTK CSS) rather than Color-in-ZStack:
    // the overlay/fixed ZStack measure path sizes against the screen, not
    // the window, and overflows a .requested-width window.
    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(20)
        }
        .background(Color(hex: SignalBrand.canvas))
    }

    // Signal-blue banner.
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Signal")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color(hex: "#FFFFFF"))
                Text("running on QuillOS · Linux aarch64")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#DDE6FF"))
            }
            Spacer()
        }
        .padding(20)
        .background(Color(hex: SignalBrand.blue))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusPill
            card
            Spacer()
            footnote
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Text("●").font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: account == nil ? SignalBrand.subtle : SignalBrand.green))
            Text(account == nil ? "No linked account found" : "Linked device · durable login active")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: SignalBrand.ink))
            Spacer()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let account {
                row("Phone number", account.e164)
                Divider()
                row("This device", "Device #\(account.deviceId)")
                Divider()
                row("Account (ACI)", shortId(account.aciUppercase))
                Divider()
                row("Registration ID", "\(account.aciRegistrationId)")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan the linking QR to register this device.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: SignalBrand.subtle))
                }
                .padding(16)
            }
        }
        .background(Color(hex: SignalBrand.surface))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: SignalBrand.subtle))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: SignalBrand.ink))
        }
        .padding(16)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Real signalapp/Signal-iOS SignalServiceKit")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: SignalBrand.subtle))
            Text("compiled & running on Linux · linked to this account by QR · login survives restart")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: SignalBrand.subtle))
        }
    }

    private func shortId(_ uuid: String) -> String {
        let lower = uuid.lowercased()
        guard lower.count > 13 else { return lower }
        return "\(lower.prefix(8))…\(lower.suffix(4))"
    }
}

// Launch the GTK-backed window.
QuillGtkApp.run(SignalDemoApp.self)
