import Foundation

// A few plain compat TYPES that vendored source references but that carry no
// QuillKit diagnostics or GTK rendering, so they can live in this lower package.
// The rich modifiers (contentShape / allowsHitTesting / listRow* /
// scrollContentBackground / symbolEffect — which record QuillKit fallback
// diagnostics — and onHover — which renders GTK accessibility/hover metadata)
// were moved UP to QuillSwiftUICompatibility / QuillUI: SwiftOpenUI is a separate
// lower package and cannot import QuillKit, so it cannot record those diagnostics.
public struct SymbolEffect: Sendable {
    public init() {}
    public static let variableColor = SymbolEffect()
    public static let pulse = SymbolEffect()
    public static let bounce = SymbolEffect()
    public static let scale = SymbolEffect()
    public static let appear = SymbolEffect()
    public static let disappear = SymbolEffect()
    public var iterative: SymbolEffect { self }
}
public struct SymbolEffectOptions: Sendable {
    public init() {}
    public static let `default` = SymbolEffectOptions()
    public static func `repeat`(_ count: Int) -> SymbolEffectOptions { SymbolEffectOptions() }
}

public struct ListStyleType: Sendable {
    private let id: String
    public static let automatic = ListStyleType(id: "automatic")
    public static let plain = ListStyleType(id: "plain")
    public static let grouped = ListStyleType(id: "grouped")
    public static let inset = ListStyleType(id: "inset")
    public static let insetGrouped = ListStyleType(id: "insetGrouped")
    public static let sidebar = ListStyleType(id: "sidebar")
    public static let bordered = ListStyleType(id: "bordered")
}

extension View {
    // listStyle is a pure no-op metadata passthrough (not asserted by the
    // diagnostics test), so it can stay in this lower package for vendored source.
    public func listStyle(_ style: ListStyleType) -> some View { self }
}
