import Foundation
import Testing
@testable import QuillFoundation

#if os(Linux)
@Suite("RSColor attributed-string compatibility")
struct AttributedStringColorTests {
    @Test("RSColor compares by RGBA components")
    func colorEqualityUsesComponents() {
        let first = RSColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let same = RSColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let different = RSColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)

        #expect(first.isEqual(same))
        #expect(first.hash == same.hash)
        #expect(!first.isEqual(different))
    }

    @Test("foreground color attributes can be reapplied over existing color runs")
    func foregroundColorCanBeReappliedOverExistingRun() {
        let text = NSMutableAttributedString(string: "#swift")
        let fullRange = NSRange(location: 0, length: text.string.utf16.count)

        text.addAttributes(
            [
                .foregroundColor: RSColor.label,
                .backgroundColor: RSColor.clear,
            ],
            range: fullRange
        )
        text.addAttributes([.foregroundColor: RSColor.systemBlue], range: fullRange)

        let foreground = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? RSColor
        #expect(foreground?.isEqual(RSColor.systemBlue) == true)
    }
}
#endif
