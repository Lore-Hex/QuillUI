import Foundation

/// A view that displays one or more lines of read-only text.
public struct Text {
    public typealias Body = Never

    /// A styled span within a `Text` — text plus an optional color. Building a
    /// `Text` from runs renders inline multi-color content (Mastodon
    /// mentions / hashtags / links in an accent color).
    public struct Run: Equatable {
        public var text: String
        public var color: Color?
        public init(text: String, color: Color? = nil) {
            self.text = text
            self.color = color
        }
    }

    /// The styled runs making up this text. A plain `Text("…")` is a single
    /// uncolored run.
    public let runs: [Run]

    /// The full plain string (every run's text joined). Preserved for the
    /// plain-render fast path and the cross-backend descriptor tree.
    public let content: String

    public init(_ content: String) {
        let resolved = quillResolveLocalizedString(content)
        self.content = resolved
        self.runs = [Run(text: resolved)]
    }

    public init(_ content: AttributedString) {
        let resolved = String(content.characters)
        self.content = resolved
        self.runs = [Run(text: resolved)]
    }

    public init<T>(_ content: T) {
        self.content = String(describing: content)
        self.runs = [Run(text: self.content)]
    }

    /// Build a multi-color `Text` from styled runs. Additive — it does not
    /// touch `Text.foregroundColor` / `Text + Text` (which the MarkdownUI
    /// module already owns), so there is no operator collision.
    public init(styledRuns runs: [Run]) {
        self.runs = runs
        self.content = runs.map(\.text).joined()
    }

    public var body: Never { fatalError("Text is a primitive view") }

    /// True when rendering needs Pango markup (a colored or multi-run text)
    /// rather than a plain label string — keeps plain `Text` on the existing
    /// fast path. `public` so the GTK / Win32 backends (separate modules) can
    /// branch on it.
    public var hasStyledRuns: Bool {
        runs.count > 1 || runs.contains { $0.color != nil }
    }
}

// View conformance lives in an extension (Apple declares it the same
// way for primitive value views): protocol-isolation inference applies
// only to conformances declared on the type itself, so statics like
// Color.accentColor stay nonisolated and remain usable as default
// argument values in nonisolated app code (IceCubes ToastCenter).
extension Text: View, PrimitiveView {}
