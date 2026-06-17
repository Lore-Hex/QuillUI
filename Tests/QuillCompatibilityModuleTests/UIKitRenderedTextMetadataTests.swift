#if os(Linux)
import Testing
import UIKit

@MainActor
struct UIKitRenderedTextMetadataTests {

    @Test func customDrawnTextMetadataRoundTripsOnUIView() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 44))

        #expect(view.quillRenderedText == nil)
        #expect(view.quillRenderedTextColor == nil)
        #expect(view.quillRenderedTextPointSize == 17)
        #expect(view.quillRenderedTextAlignment == .natural)
        #expect(view.quillRenderedTextNumberOfLines == 0)

        view.quillRenderedText = "Signal body text"
        view.quillRenderedTextColor = .label
        view.quillRenderedTextPointSize = 15
        view.quillRenderedTextAlignment = .center
        view.quillRenderedTextNumberOfLines = 2

        #expect(view.quillRenderedText == "Signal body text")
        #expect(view.quillRenderedTextColor != nil)
        #expect(view.quillRenderedTextPointSize == 15)
        #expect(view.quillRenderedTextAlignment == .center)
        #expect(view.quillRenderedTextNumberOfLines == 2)

        view.quillRenderedText = nil
        #expect(view.quillRenderedText == nil)
    }
}
#endif
