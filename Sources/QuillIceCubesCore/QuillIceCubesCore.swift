import Foundation
import QuillUI

/// Quill IceCubes placeholder content view.
///
/// The real IceCubes app (`Dimillian/IceCubesApp`) pulls its `Models` and
/// `NetworkClient` Swift packages out of `Packages/`, but those package
/// manifests pin `platforms: [.iOS(.v18), .visionOS(.v1)]` — they don't
/// resolve on macOS or Linux. Until those platform pins are relaxed (or
/// the relevant types are reimplemented locally), `QuillIceCubesCore`
/// renders a static placeholder so the SwiftPM target builds end-to-end
/// through QuillUI's compatibility layer.
///
/// Next slice will reimplement a `Status` / `MastodonClient` surface
/// locally (the IceCubes-shaped subset that `QuillIceCubesContentView`
/// needs) so the placeholder turns into a real Mastodon public-timeline
/// shell.
public struct QuillIceCubesContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Quill IceCubes")
                .font(.title)
            Text("Mastodon timeline shell, compatibility-only.")
                .multilineTextAlignment(.center)
            Text("Wiring `Models` / `NetworkClient` from `Dimillian/IceCubesApp` needs upstream `platforms:` relaxed (currently `.iOS(.v18)` / `.visionOS(.v1)`) or a local reimplementation of the `Status` / `MastodonClient` surface.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(20)
    }
}
