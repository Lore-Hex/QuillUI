import Foundation
#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

public enum QuillPaintButtonChrome: Equatable, Hashable, Sendable {
    case macDefault
    case macBordered
}

#if os(macOS) || os(iOS) || os(visionOS)
public struct QuillPaintButtonStyle: ButtonStyle {
    public var chrome: QuillPaintButtonChrome

    public init(_ chrome: QuillPaintButtonChrome) {
        self.chrome = chrome
    }

    public func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .foregroundColor(chrome == .macDefault ? .white : .primary)
            .background(chrome == .macDefault ? Color.accentColor : Color(white: 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(chrome == .macDefault ? Color.clear : Color.black.opacity(0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

public extension ButtonStyle where Self == QuillPaintButtonStyle {
    static func quillPaint(_ chrome: QuillPaintButtonChrome) -> QuillPaintButtonStyle {
        QuillPaintButtonStyle(chrome)
    }
}
#else
public extension ButtonStyleType {
    static func quillPaint(_ chrome: QuillPaintButtonChrome) -> ButtonStyleType {
        switch chrome {
        case .macDefault:
            return .quillPaintMacDefault
        case .macBordered:
            return .quillPaintMacBordered
        }
    }
}
#endif

public extension View {
    @ViewBuilder
    func quillPaint(_ chrome: QuillPaintButtonChrome) -> some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        switch chrome {
        case .macDefault:
            buttonStyle(.borderedProminent)
        case .macBordered:
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.quillPaint(chrome))
        #endif
    }
}
