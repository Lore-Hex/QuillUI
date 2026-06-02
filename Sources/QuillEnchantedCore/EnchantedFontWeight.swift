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
    case ..<250:
        // Genuine native Enchanted renders the empty-state wordmark with
        // Font.system(weight: .thin). Map low weights (<250) to .thin so the
        // gradient wordmark reads delicate like genuine. Safe: nothing else in
        // the app uses a sub-600 weight (all titles are 650-700).
        return .thin
    default:
        return .regular
    }
}
