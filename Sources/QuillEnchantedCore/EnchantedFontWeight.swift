import QuillUI
#if canImport(SwiftUI)
import SwiftUI
#endif

public func enchantedFontWeight(_ value: Int) -> Font.Weight {
    switch value {
    case 700...:
        return .bold
    case 650..<700:
        return .semibold
    case 600..<650:
        return .medium
    default:
        return .regular
    }
}
