#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

public enum QuillPaintButtonChrome: Equatable, Hashable, Sendable {
    case macDefault
    case macBordered
}

public extension View {
    @ViewBuilder
    func quillPaint(_ chrome: QuillPaintButtonChrome) -> some View {
        #if os(macOS)
        switch chrome {
        case .macDefault:
            buttonStyle(.borderedProminent)
        case .macBordered:
            buttonStyle(.bordered)
        }
        #elseif os(Linux)
        switch chrome {
        case .macDefault:
            buttonStyle(ButtonStyleType.quillPaintMacDefault)
        case .macBordered:
            buttonStyle(ButtonStyleType.quillPaintMacBordered)
        }
        #else
        self
        #endif
    }
}
