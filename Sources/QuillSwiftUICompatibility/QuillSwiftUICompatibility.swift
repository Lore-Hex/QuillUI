@_exported import SwiftOpenUI

#if os(Linux)
// Upstream SwiftUI exposes `Font.Weight` as a nested type. SwiftOpenUI
// uses a top-level `FontWeight`, so expose the spelling from one shared
// module that both `QuillUI` and the Linux `SwiftUI` shadow can re-export.
public extension Font {
    typealias Weight = FontWeight
}

// SwiftOpenUI currently provides top/center/bottom alignment only.
// Downgrade baseline-relative alignments to the closest visual
// approximation until backend text metrics can drive true baselines.
public extension VerticalAlignment {
    static var firstTextBaseline: VerticalAlignment { .top }
    static var lastTextBaseline: VerticalAlignment { .bottom }
}
#endif
