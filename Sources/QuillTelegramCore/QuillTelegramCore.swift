import Foundation
import QuillUI

/// Quill Telegram placeholder content view.
///
/// The upstream `mtg-experiments/Telegram-iOS` (and the macOS
/// `Telegram-Swift` fork) is a massive multi-target project
/// with bespoke MTProto / TDLib / SwiftSignalKit dependencies
/// that aren't SwiftPM-friendly. QuillTelegram renders a static
/// scaffold so the SwiftPM target builds end-to-end through
/// QuillUI's compatibility layer — same shape as the
/// IceCubes/NetNewsWire/Signal scaffolds before their local
/// surfaces landed.
///
/// Next slices: a fixtures-only chat list + message timeline
/// with a `QuillData`-backed local store. Real MTProto network
/// stack stays out of scope.
@MainActor
public struct QuillTelegramContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Quill Telegram")
                .font(.title)
            Text("Scaffold — chat list + fixture-driven timeline coming next.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(20)
    }
}
