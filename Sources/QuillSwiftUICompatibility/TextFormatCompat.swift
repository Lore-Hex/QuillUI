import Foundation
import SwiftOpenUI

// SwiftUI's `Text(_ value:, format:)` — renders a value through a Foundation
// `FormatStyle` (e.g. `Text(count, format: .number.notation(.compactName))`,
// used by vendored DesignSystem for compact follower/post counts). Linux
// Foundation provides the REAL FormatStyle (`.number.notation(.compactName)`
// works), so this only bridges the formatted String into SwiftOpenUI's Text.
// Surfaced to vendored real source through the SwiftUI shim's re-export of
// QuillSwiftUICompatibility.
extension Text {
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(format.format(input))
    }
}

// SwiftUI `Text(_ attributedString:)` — render a Foundation AttributedString as
// plain text on Linux (SwiftOpenUI's Text takes a String). Used by vendored DS.
extension Text {
    public init(_ attributedString: AttributedString) {
        self.init(String(attributedString.characters))
    }
}
