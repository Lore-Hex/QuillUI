import Foundation
import SwiftOpenUI

// Supplemental SwiftUI view modifiers the real upstream IceCubes source calls
// that are NOT covered by IceCubesDesignSystemModifiers.swift and exist only in
// the QuillUI module (which the IceCubes SwiftUI shim can't import — it avoids
// `@_exported import QuillUI` to dodge NSImage/FocusState collisions). Cosmetic
// / metadata on Linux, so re-declare here in QuillSwiftUICompatibility (which
// the IceCubes shim DOES re-export) as layout-neutral pass-throughs.
//
// onHover/allowsHitTesting/textSelection/contentShape/symbolEffect/
// listRowSeparator/foregroundStyle live in
// IceCubesDesignSystemModifiers.swift — do NOT duplicate them here.

public extension View {
    @_disfavoredOverload
    func minimumScaleFactor(_ factor: Double) -> Self {
        _ = factor
        return self
    }

    @_disfavoredOverload
    func formStyle(_ style: GroupedFormStyle) -> Self {
        _ = style
        return self
    }
}

/// SwiftUI's `Image.TemplateRenderingMode` shim. Upstream uses it only as an
/// argument to `renderingMode(_:)`, which is a layout-neutral pass-through here.
public struct ImageRenderingMode: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let original = ImageRenderingMode("original")
    public static let template = ImageRenderingMode("template")
}

public extension Image {
    @_disfavoredOverload
    func renderingMode(_ mode: ImageRenderingMode?) -> Image {
        _ = mode
        return self
    }
}
