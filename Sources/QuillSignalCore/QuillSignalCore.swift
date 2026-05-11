import Foundation
import QuillUI

/// Quill Signal placeholder content view.
///
/// The upstream `signalapp/Signal-iOS` is a UIKit app that pulls
/// in CocoaPods + a large native crypto/database stack
/// (libsignal-client, RingRTC, GRDB, MobileCoreServices). Wiring
/// it as a SwiftPM target is multi-week work. For now QuillSignal
/// renders a static scaffold so the SwiftPM target builds
/// end-to-end through QuillUI's compatibility layer — same shape
/// as the IceCubes/NetNewsWire scaffolds before their local API
/// surface landed.
///
/// Next slices: build a fixtures-only conversation timeline with
/// `QuillData`-shaped local storage, then wire encrypted-at-rest
/// SQLite + a fake-account "Quill Signal Linux" identity. Real
/// libsignal protocol stays out of scope until the QuillData
/// encrypted-key column work is done.
@MainActor
public struct QuillSignalContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Quill Signal")
                .font(.title)
            Text("Scaffold — conversation timeline + local fixture store coming next.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(20)
    }
}
