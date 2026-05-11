import Foundation
import QuillUI

/// Quill CodeEdit placeholder content view.
///
/// The upstream `CodeEditApp/CodeEdit` repo is a SwiftUI/AppKit
/// macOS app that depends on `CodeEditApp/CodeEditSymbols`,
/// `CodeEditSourceEditor` (NSTextView-backed), Sparkle (Apple
/// auto-updater), and a chain of CodeEditApp SPM packages. The
/// vendored `Sources/QuillUI/.upstream/codeeditsymbols` path
/// pulls in a SwiftLintPlugin prebuild command that SwiftPM 6
/// rejects ("a prebuild command cannot use executables built
/// from source"), so the `CodeEditUpstream` target stays opt-in
/// via `scripts/fetch-upstream.sh codeedit codeeditsymbols`.
///
/// QuillCodeEditCore renders a scaffold so the SwiftPM target
/// builds end-to-end through QuillUI's compatibility layer
/// without the SwiftLintPlugin opt-in path — same shape as
/// the Signal/Telegram/IINA placeholders.
///
/// Next slices: file tree → multi-tab editor → command palette,
/// likely backed by a small TextEditor surface around a custom
/// rope buffer.
@MainActor
public struct QuillCodeEditContentView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Text("Quill CodeEdit")
                .font(.title)
            Text("Scaffold — folder browser, tabbed editor, and command palette coming next.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(20)
    }
}
