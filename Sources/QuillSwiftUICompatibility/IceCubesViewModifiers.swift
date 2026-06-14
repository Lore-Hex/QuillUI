import Foundation
import SwiftOpenUI

// SwiftUI view modifiers that the real upstream IceCubes source calls but that
// only exist in the QuillUI module — which the IceCubes Linux graph cannot
// import (its SwiftUI shim deliberately avoids `@_exported import QuillUI` to
// dodge the NSImage/FocusState collisions). They are cosmetic / metadata on
// Linux, so re-declare them here in QuillSwiftUICompatibility (which the
// IceCubes SwiftUI shim DOES re-export) as layout-neutral pass-throughs.
//
// Return `Self` rather than QuillUI's wrapper views (OnHoverView, etc.), which
// likewise are not visible here. The supporting value types they reference
// (SymbolEffect, SymbolEffectOptions, TextSelectability, GroupedFormStyle) are
// already declared in DesignSystemSurfaceCompat; ButtonStyle/PlainButtonStyle/
// ButtonStyleConfiguration come from SwiftOpenUI.

public extension View {
    @_disfavoredOverload
    func onHover(perform action: @escaping (Bool) -> Void) -> Self {
        _ = action
        return self
    }

    @_disfavoredOverload
    func allowsHitTesting(_ enabled: Bool) -> Self {
        _ = enabled
        return self
    }

    @_disfavoredOverload
    func textSelection(_ selection: TextSelectability = .enabled) -> Self {
        _ = selection
        return self
    }

    @_disfavoredOverload
    func contentShape<S: Shape>(_ shape: S) -> Self {
        _ = shape
        return self
    }

    @_disfavoredOverload
    func symbolEffect<Value: Equatable>(
        _ effect: SymbolEffect,
        options: SymbolEffectOptions = .default,
        value: Value
    ) -> Self {
        _ = effect
        _ = options
        _ = value
        return self
    }

    @_disfavoredOverload
    func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> Self {
        _ = visibility
        _ = edges
        return self
    }

    @_disfavoredOverload
    func listRowInsets(_ insets: EdgeInsets?) -> Self {
        _ = insets
        return self
    }

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

    // SwiftUI's multi-style `foregroundStyle` (primary + secondary [+ tertiary]),
    // used for multicolor SF Symbols e.g. `.foregroundStyle(.white, .green)`.
    // The single-Color form exists in SwiftOpenUI; the secondary/tertiary layers
    // are cosmetic on Linux, so apply nothing and pass through.
    @_disfavoredOverload
    func foregroundStyle(_ primary: Color, _ secondary: Color) -> Self {
        _ = primary
        _ = secondary
        return self
    }

    @_disfavoredOverload
    func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Self {
        _ = primary
        _ = secondary
        _ = tertiary
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
