import Foundation
import QuillUI

/// Quill IINA placeholder content view.
///
/// The upstream `iina/iina` is a Cocoa/AppKit media player that
/// wraps `mpv` for playback. QuillIINA's place in the QuillUI
/// app rotation is the player UI shell (playlist, inspector,
/// playback chrome) — actual media decode stays behind an
/// adapter so the Swift app shell can compile without bundling
/// libmpv on every build.
///
/// QuillIINA renders a static scaffold so the SwiftPM target
/// builds end-to-end through QuillUI's compatibility layer.
/// Next slices: file picker → playlist surface → playback
/// chrome (transport bar / volume / fullscreen) backed by an
/// `IINAMediaBackend` protocol with a mock implementation.
@MainActor
public struct QuillIINAContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Quill IINA")
                .font(.title)
            Text("Scaffold — file picker, playlist, and transport chrome coming next.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(20)
    }
}
