/// A view that displays one or more lines of read-only text.
public struct Text: View, PrimitiveView {
    public typealias Body = Never

    /// A styled span within a `Text`. Concatenating Text values — e.g.
    /// `Text("hi ") + Text("@alex").foregroundColor(.blue)` — builds a Text
    /// of multiple runs, mirroring SwiftUI's `Text + Text`.
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
        self.content = content
        self.runs = [Run(text: content)]
    }

    init(runs: [Run]) {
        self.runs = runs
        self.content = runs.map(\.text).joined()
    }

    public var body: Never { fatalError("Text is a primitive view") }

    /// SwiftUI's Text-specific `foregroundColor` — returns `Text` (so it
    /// composes with concatenation) and colors every run. Takes a
    /// non-optional `Color` to match `View.foregroundColor(_:)`'s signature
    /// exactly, so this concrete-type method wins overload resolution over the
    /// protocol-extension modifier for a `Text` receiver (a `Color?` parameter
    /// would lose to the non-optional modifier on a non-nil argument).
    public func foregroundColor(_ color: Color) -> Text {
        Text(runs: runs.map { Run(text: $0.text, color: color) })
    }

    /// Concatenate two `Text` values into one multi-run `Text`, mirroring
    /// SwiftUI's `Text + Text`.
    public static func + (lhs: Text, rhs: Text) -> Text {
        Text(runs: lhs.runs + rhs.runs)
    }

    /// True when rendering needs Pango markup (a colored or multi-run text)
    /// rather than a plain label string — keeps plain `Text` on the existing
    /// fast path. `public` so the GTK backend (a separate module) can branch.
    public var hasStyledRuns: Bool {
        runs.count > 1 || runs.contains { $0.color != nil }
    }
}
