// Mirrors SwiftOpenUI's `Text(styledRuns:)` / `Text.Run` onto real SwiftUI
// so the same source — e.g. QuillIceCubesCore's accent-tinted Mastodon
// mention/hashtag content — compiles unmodified on Apple platforms.
//
// On Linux the GTK/Qt backends use SwiftOpenUI's `Text`, which defines these
// natively (multi-run inline color). On macOS/iOS/visionOS, QuillUI
// `@_exported import SwiftUI`s the real `Text`, which has neither — so this
// additive extension folds the runs into concatenated, per-run-colored real
// SwiftUI `Text`. Same approach as the AsyncImage mirror; keeps app code free
// of `#if os(...)` forks.
#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI

public extension Text {
    /// A styled span within a `Text` — text plus an optional color. Matches
    /// `SwiftOpenUI.Text.Run` so callers are source-identical on both stacks.
    struct Run: Equatable {
        public var text: String
        public var color: Color?
        public init(text: String, color: Color? = nil) {
            self.text = text
            self.color = color
        }
    }

    /// Build a multi-color `Text` from styled runs. Folds the runs into
    /// `Text + Text`, applying each run's color via `foregroundColor`. A plain
    /// run (nil color) contributes uncolored text; an empty array yields empty
    /// text — matching SwiftOpenUI's `init(styledRuns:)` semantics.
    init(styledRuns runs: [Run]) {
        self = runs.reduce(Text(verbatim: "")) { accumulated, run in
            let piece = run.color.map { Text(verbatim: run.text).foregroundColor($0) }
                ?? Text(verbatim: run.text)
            return accumulated + piece
        }
    }
}
#endif
