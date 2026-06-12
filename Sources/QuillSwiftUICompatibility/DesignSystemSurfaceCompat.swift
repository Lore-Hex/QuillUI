import Foundation
import Combine
import SwiftOpenUI

public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder @MainActor static var previews: Previews { get }
}

public struct RedactionReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let placeholder = RedactionReasons(rawValue: 1 << 0)
}

public enum LayoutDirection: Sendable {
    case leftToRight
    case rightToLeft
}

private struct RedactionReasonsKey: EnvironmentKey {
    static let defaultValue = RedactionReasons()
}

private struct LayoutDirectionKey: EnvironmentKey {
    static let defaultValue = LayoutDirection.leftToRight
}

private struct CalendarKey: EnvironmentKey {
    static let defaultValue = Calendar.current
}

public enum EditMode: Sendable {
    case inactive
    case active
    case transient
}

private struct EditModeKey: EnvironmentKey {
    static let defaultValue: Binding<EditMode>? = nil
}

public extension EnvironmentValues {
    var redactionReasons: RedactionReasons {
        get { self[RedactionReasonsKey.self] }
        set { self[RedactionReasonsKey.self] = newValue }
    }

    var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }

    var calendar: Calendar {
        get { self[CalendarKey.self] }
        set { self[CalendarKey.self] = newValue }
    }

    var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
}

public struct ContentUnavailableView<Description: View>: View {
    private let title: String
    private let systemImage: String
    private let descriptionView: Description

    public init<T>(_ title: T, systemImage: String, description: Description) {
        self.title = String(describing: title)
        self.systemImage = systemImage
        self.descriptionView = description
    }

    public init<T>(_ title: T, systemImage: String) where Description == EmptyView {
        self.title = String(describing: title)
        self.systemImage = systemImage
        self.descriptionView = EmptyView()
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
            descriptionView
        }
    }
}

public struct GroupBox<Label: View, Content: View>: View {
    private let label: Label?
    private let content: Content

    public init(@ViewBuilder content: () -> Content) where Label == EmptyView {
        self.label = nil
        self.content = content()
    }

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                label
            }
            content
        }
    }
}

public struct PlainListStyle: Sendable {
    public init() {}
    public static let plain = PlainListStyle()
    public static let insetGrouped = PlainListStyle()
    public static let grouped = PlainListStyle()
}

public enum ButtonRole: Sendable {
    case cancel
    case destructive
}

public struct LocalizedStringKey: Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    private static let encodedPrefix = "\u{1F}quill-localized-key:"

    private let storage: String

    public init(stringLiteral value: String) {
        self.storage = value
    }

    public init(_ value: String) {
        self.storage = value
    }

    public init(stringInterpolation: StringInterpolation) {
        self.storage = Self.encode(key: stringInterpolation.key, arguments: stringInterpolation.arguments)
    }

    public var key: String {
        Self.decode(storage).key
    }

    public var arguments: [String] {
        Self.decode(storage).arguments
    }

    public var resolved: String {
        quillResolveLocalizedString(key, arguments: arguments)
    }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        public var key = ""
        public var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += quillLocalizedStringKeyPlaceholder(for: value)
            arguments.append(String(describing: value))
        }
        public mutating func appendInterpolation<T>(_ value: T, format: NumberFormatStyle) {
            key += "%@"
            arguments.append(quillFormatNumber(value, format: format))
        }
    }

    private static func encode(key: String, arguments: [String]) -> String {
        guard !arguments.isEmpty else {
            return key
        }
        var encoded = encodedPrefix
        encoded += "\(key.count):\(key)"
        for argument in arguments {
            encoded += "\(argument.count):\(argument)"
        }
        return encoded
    }

    private static func decode(_ storage: String) -> (key: String, arguments: [String]) {
        guard storage.hasPrefix(encodedPrefix) else {
            return (storage, [])
        }

        var index = storage.index(storage.startIndex, offsetBy: encodedPrefix.count)
        guard let key = readEncodedField(from: storage, index: &index) else {
            return (storage, [])
        }

        var arguments: [String] = []
        while index < storage.endIndex {
            guard let argument = readEncodedField(from: storage, index: &index) else {
                return (key, arguments)
            }
            arguments.append(argument)
        }
        return (key, arguments)
    }

    private static func readEncodedField(from storage: String, index: inout String.Index) -> String? {
        var lengthText = ""
        while index < storage.endIndex {
            let character = storage[index]
            index = storage.index(after: index)
            if character == ":" {
                break
            }
            lengthText.append(character)
        }
        guard let length = Int(lengthText),
              let end = storage.index(index, offsetBy: length, limitedBy: storage.endIndex) else {
            return nil
        }
        let value = String(storage[index..<end])
        index = end
        return value
    }
}

public extension Button where Label == Text {
    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(title.resolved, action: action)
    }

    init(_ title: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) {
        _ = role
        self.init(title.resolved, action: action)
    }

    init<T>(_ title: T, role: ButtonRole?, action: @escaping () -> Void) {
        _ = role
        self.init(String(describing: title), action: action)
    }
}

public extension Text {
    init(_ key: LocalizedStringKey) {
        self.init(key.resolved)
    }

    init(verbatim content: String) {
        self.init(styledRuns: [.init(text: content)])
    }
}

public extension Button {
    init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        _ = role
        self.init(action: action, label: label)
    }
}

public struct SymbolEffect: Sendable {
    public init() {}
    public static let variableColor = SymbolEffect()
    public static let pulse = SymbolEffect()
    public var iterative: SymbolEffect { self }
}

public struct SymbolEffectOptions: Sendable {
    public init() {}
    public static let `default` = SymbolEffectOptions()
    public static func `repeat`(_ count: Int) -> SymbolEffectOptions {
        _ = count
        return SymbolEffectOptions()
    }
}

public struct AnyTransition: Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String = "identity") {
        self.description = description
    }

    public init(_ transition: AnyTransition) {
        self = transition
    }

    public static let opacity = AnyTransition("opacity")
    public static let slide = AnyTransition("slide")
    public static let identity = AnyTransition("identity")
    public static var scale: AnyTransition { .scale() }

    public static func scale(scale: Double = 1.0, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition("scale(\(scale), \(anchor))")
    }

    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition("move(\(edge.rawValue))")
    }

    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition("push(\(edge.rawValue))")
    }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition("asymmetric(\(insertion.description), \(removal.description))")
    }

    public func combined(with transition: AnyTransition) -> AnyTransition {
        AnyTransition("combined(\(description), \(transition.description))")
    }
}

public struct GlassEffect: Sendable {
    public init() {}
    public static let regular = GlassEffect()
    public func tint(_ color: Color) -> GlassEffect {
        _ = color
        return self
    }
    public func interactive() -> GlassEffect { self }
}

public struct GlassEffectShape: Sendable {
    public init() {}
    public static let capsule = GlassEffectShape()

    public static func rect(cornerRadius: Double) -> GlassEffectShape {
        _ = cornerRadius
        return GlassEffectShape()
    }
}

public struct Material: View, Sendable {
    public init() {}
    public var body: some View { EmptyView() }
    public static let ultraThinMaterial = Material()
    public static let ultraThin = Material()
    public static let thinMaterial = Material()
    public static let regularMaterial = Material()
    public static let thickMaterial = Material()
    public static let ultraThickMaterial = Material()
    public static let ultraThick = Material()
}

public struct HoverEffect: Sendable {
    public init() {}
    public static let lift = HoverEffect()
}

@propertyWrapper
public struct Namespace {
    public struct ID: Hashable, Sendable {
        private let rawValue: UUID
        public init() { rawValue = UUID() }
    }

    private let id = ID()
    public init() {}
    public var wrappedValue: ID { id }
}

public struct AccessibilityChildBehavior: Hashable, Sendable {
    private let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let combine = AccessibilityChildBehavior("combine")
    public static let ignore = AccessibilityChildBehavior("ignore")
    public static let contain = AccessibilityChildBehavior("contain")
}

public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 0)
    public static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 1)
    public static let isButton = AccessibilityTraits(rawValue: 1 << 2)
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 3)
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 4)
    public static let isImage = AccessibilityTraits(rawValue: 1 << 5)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 6)
    public static let isLink = AccessibilityTraits(rawValue: 1 << 7)
}

public struct AccessibilityActionKind: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let `default` = AccessibilityActionKind("default")
    public static let escape = AccessibilityActionKind("escape")
    public static let magicTap = AccessibilityActionKind("magicTap")
}

public struct NumberFormatStyle: Sendable {
    public struct Notation: Sendable {
        public init() {
        }
        public static let compactName = Notation()
    }

    public struct Precision: Sendable {
        public init() {
        }

        public static func fractionLength(_ length: Int) -> Precision {
            _ = length
            return Precision()
        }
    }

    public init() {
    }

    public static let number = NumberFormatStyle()
    public static let percent = NumberFormatStyle()

    public func notation(_ notation: Notation) -> NumberFormatStyle {
        _ = notation
        return self
    }

    public func precision(_ precision: Precision) -> NumberFormatStyle {
        _ = precision
        return self
    }
}

private func quillLocalizedStringKeyPlaceholder<T>(for value: T) -> String {
    switch value {
    case is Int, is Int8, is Int16, is Int32, is Int64:
        return "%lld"
    case is UInt, is UInt8, is UInt16, is UInt32, is UInt64:
        return "%llu"
    case is Float, is Double:
        return "%f"
    default:
        return "%@"
    }
}

private func quillFormatNumber<T>(_ value: T, format: NumberFormatStyle) -> String {
    _ = format
    let plain = String(describing: value)
    let normalized = plain.replacingOccurrences(of: ",", with: "")
    guard let number = Double(normalized) else { return plain }
    return quillCompactNumberString(number, fractionLength: nil)
}

private func quillCompactNumberString(_ value: Double, fractionLength: Int?) -> String {
    let absolute = abs(value)
    let sign = value < 0 ? "-" : ""
    let scales: [(threshold: Double, divisor: Double, suffix: String)] = [
        (1_000_000_000_000, 1_000_000_000_000, "T"),
        (1_000_000_000, 1_000_000_000, "B"),
        (1_000_000, 1_000_000, "M"),
        (1_000, 1_000, "K"),
    ]

    guard let scale = scales.first(where: { absolute >= $0.threshold }) else {
        let digits = fractionLength ?? 0
        return String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    let scaled = absolute / scale.divisor
    let digits = fractionLength ?? (scaled < 100 ? 1 : 1)
    var formatted = String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), scaled)
    if fractionLength == nil, formatted.hasSuffix(".0") {
        formatted.removeLast(2)
    }
    return "\(sign)\(formatted)\(scale.suffix)"
}

public struct DateFormatStyle: Sendable {
    public struct MonthStyle: Sendable {
        public init() {}
        public static let abbreviated = MonthStyle()
        public static let wide = MonthStyle()
        public static let narrow = MonthStyle()
    }

    public init() {}
    public static let dateTime = DateFormatStyle()

    public func month(_ style: MonthStyle) -> DateFormatStyle {
        _ = style
        return self
    }

    public func day() -> DateFormatStyle { self }
}

public enum TextSelectability: Sendable {
    case enabled
    case disabled
}

public enum ScrollDismissesKeyboardMode: Sendable {
    case automatic
    case immediately
    case interactively
    case never
}

public enum ScenePhase: Sendable {
    case active
    case inactive
    case background
}

private struct ScenePhaseKey: EnvironmentKey {
    static let defaultValue = ScenePhase.active
}

public extension EnvironmentValues {
    var scenePhase: ScenePhase {
        get { self[ScenePhaseKey.self] }
        set { self[ScenePhaseKey.self] = newValue }
    }
}

@propertyWrapper
public struct GestureState<Value> {
    private var value: Value

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    public var wrappedValue: Value {
        get { value }
        nonmutating set {}
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

public struct SharePreview<ImageValue> {
    public let title: String
    public let image: ImageValue?

    public init<T>(_ title: T, image: ImageValue) {
        self.title = String(describing: title)
        self.image = image
    }

    public init<T>(_ title: T, @ViewBuilder image: () -> ImageValue) {
        self.title = String(describing: title)
        self.image = image()
    }
}

public struct ShareLink<Item>: View {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }

    public init<PreviewImage>(item: Item, preview: SharePreview<PreviewImage>) {
        self.item = item
        _ = preview
    }

    public init<Label: View>(item: Item, @ViewBuilder label: () -> Label) {
        self.item = item
        _ = label()
    }

    public init<Label: View>(
        item: Item,
        subject: Text,
        @ViewBuilder label: () -> Label
    ) {
        self.item = item
        _ = subject
        _ = label()
    }

    public init<Label: View>(
        item: Item,
        subject: Text,
        message: Text,
        @ViewBuilder label: () -> Label
    ) {
        self.item = item
        _ = subject
        _ = message
        _ = label()
    }

    public var body: some View { EmptyView() }
}

public struct ControlGroup<Content: View>: View {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View { content }
}

public struct ProgressViewStyle: Sendable {
    public init() {}
    public static let circular = ProgressViewStyle()
    public static let linear = ProgressViewStyle()
}

public typealias KeyEquivalent = SwiftOpenUI.KeyEquivalent

public enum KeyPressResult: Sendable {
    case handled
    case ignored
}

public struct ScrollTargetBehavior: Sendable {
    public init() {}
    public static let viewAligned = ScrollTargetBehavior()
}

public struct Transaction: Sendable {
    public var disablesAnimations: Bool
    public init(disablesAnimations: Bool = false) {
        self.disablesAnimations = disablesAnimations
    }

    public init(animation: Animation?) {
        _ = animation
        self.disablesAnimations = false
    }
}

public func withTransaction<Result>(
    _ transaction: Transaction,
    _ body: () throws -> Result
) rethrows -> Result {
    _ = transaction
    return try body()
}

public struct PresentationDetent: Hashable, Sendable {
    private let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }
    public static let medium = PresentationDetent("medium")
    public static let large = PresentationDetent("large")
    public static func height(_ height: Double) -> PresentationDetent {
        PresentationDetent("height:\(height)")
    }
}

public struct NavigationTransition: Sendable {
    public init() {}
    public static func zoom<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> NavigationTransition {
        _ = sourceID
        _ = namespace
        return NavigationTransition()
    }
}

public struct CoordinateSpace: Hashable, Sendable {
    private let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }
    public static let local = CoordinateSpace("local")
    public static let global = CoordinateSpace("global")
    public static func named(_ name: String) -> CoordinateSpace {
        CoordinateSpace("named:\(name)")
    }
}

public extension GeometryProxy {
    var safeAreaInsets: EdgeInsets { EdgeInsets() }

    func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        _ = coordinateSpace
        return CGRect(origin: .zero, size: size)
    }
}

public enum NavigationBarTitleDisplayMode: Sendable {
    case automatic
    case inline
    case large
}

// ScrollContentBackgroundVisibility lives in QuillUI — a second enum here
// made `.hidden` member lookups ambiguous in scrollContentBackground calls.

public enum ScrollBounceBehavior: Sendable {
    case automatic
    case always
    case basedOnSize
}

public enum ContentSizeCategory: Hashable, Sendable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge
    case extraExtraLarge
    case extraExtraExtraLarge
    case accessibilityMedium
    case accessibilityLarge
    case accessibilityExtraLarge
    case accessibilityExtraExtraLarge
    case accessibilityExtraExtraExtraLarge
}

private struct ContentSizeCategoryKey: EnvironmentKey {
    static let defaultValue = ContentSizeCategory.large
}

public struct SymbolVariants: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let none = SymbolVariants("none")
    public static let fill = SymbolVariants("fill")
    public static let slash = SymbolVariants("slash")
}

private struct SymbolVariantsKey: EnvironmentKey {
    static let defaultValue = SymbolVariants.none
}

public enum ControlSize: Hashable, Sendable {
    case mini
    case small
    case regular
    case large
    case extraLarge
}

private struct ControlSizeKey: EnvironmentKey {
    static let defaultValue = ControlSize.regular
}

public enum UserInterfaceSizeClass: Hashable, Sendable {
    case compact
    case regular
}

private struct HorizontalSizeClassKey: EnvironmentKey {
    static let defaultValue: UserInterfaceSizeClass? = .regular
}

private struct AccessibilityVoiceOverEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct LocaleKey: EnvironmentKey {
    static let defaultValue = Locale.current
}

private struct DefaultMinListRowHeightKey: EnvironmentKey {
    static let defaultValue = 44
}

public extension EnvironmentValues {
    var sizeCategory: ContentSizeCategory {
        get { self[ContentSizeCategoryKey.self] }
        set { self[ContentSizeCategoryKey.self] = newValue }
    }

    var symbolVariants: SymbolVariants {
        get { self[SymbolVariantsKey.self] }
        set { self[SymbolVariantsKey.self] = newValue }
    }

    var controlSize: ControlSize {
        get { self[ControlSizeKey.self] }
        set { self[ControlSizeKey.self] = newValue }
    }

    var horizontalSizeClass: UserInterfaceSizeClass? {
        get { self[HorizontalSizeClassKey.self] }
        set { self[HorizontalSizeClassKey.self] = newValue }
    }

    var accessibilityVoiceOverEnabled: Bool {
        get { self[AccessibilityVoiceOverEnabledKey.self] }
        set { self[AccessibilityVoiceOverEnabledKey.self] = newValue }
    }

    var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }

    var defaultMinListRowHeight: Int {
        get { self[DefaultMinListRowHeightKey.self] }
        set { self[DefaultMinListRowHeightKey.self] = newValue }
    }

}

public extension Shape where Self == Circle {
    static var circle: Circle { Circle() }
}

public struct ToolbarSpacer: ToolbarContent, ToolbarContentItemsProvider {
    public typealias Body = Never
    public let placement: ToolbarItemPlacement

    public init(placement: ToolbarItemPlacement = .primaryAction) {
        self.placement = placement
    }

    public var toolbarContentItems: [AnyToolbarItem] { [] }
    public var body: Never { return fatalError("ToolbarSpacer is primitive toolbar content") }
}

public enum ButtonBorderShape: Hashable, Sendable {
    case automatic
    case capsule
    case circle
    case roundedRectangle
}

public struct Alert {
    public struct Button {
        public let label: Text
        public let action: () -> Void

        public init(label: Text, action: @escaping () -> Void = {}) {
            self.label = label
            self.action = action
        }

        public static func `default`(_ label: Text, action: @escaping () -> Void = {}) -> Button {
            Button(label: label, action: action)
        }

        public static func destructive(_ label: Text, action: @escaping () -> Void = {}) -> Button {
            Button(label: label, action: action)
        }

        public static func cancel(_ label: Text = Text("Cancel"), action: @escaping () -> Void = {}) -> Button {
            Button(label: label, action: action)
        }
    }

    public let title: Text
    public let message: Text?
    public let primaryButton: Button?
    public let secondaryButton: Button?

    public init(title: Text, message: Text? = nil, primaryButton: Button? = nil, secondaryButton: Button? = nil) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }
}

public extension String {
    static let line3HorizontalDecrease = "line.3.horizontal.decrease"

    init(localized key: String) {
        self = quillResolveLocalizedString(key)
    }

    init(localized key: StaticString) {
        self = quillResolveLocalizedString(key.description)
    }
}

public extension Label where Title == Text, Icon == Image {
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.init(title.resolved, systemImage: systemImage)
    }

    init(_ title: LocalizedStringKey, image: String) {
        self.init(title.resolved, image: image)
    }

    init<T>(_ title: T, systemSymbol: String) {
        self.init(title, systemImage: systemSymbol)
    }
}

public extension Link {
    init(_ title: String, destination: URL) {
        self.init(title, destination: destination.absoluteString)
    }
}

public extension ButtonStyleType {
    static var glass: ButtonStyleType { .bordered }
    static var glassProminent: ButtonStyleType { .borderedProminent }
    static var borderless: ButtonStyleType { .plain }
}

public struct LabelStyleType: Sendable {
    public init() {}
    public static let iconOnly = LabelStyleType()
    public static let titleOnly = LabelStyleType()
    public static let titleAndIcon = LabelStyleType()
}

public struct MenuStyleType: Sendable {
    public init() {}
    public static let button = MenuStyleType()
}

public struct ControlGroupStyleType: Sendable {
    public init() {}
    public static let compactMenu = ControlGroupStyleType()
}

public struct DynamicTypeSize: Hashable, Comparable, Sendable {
    private let rawValue: Int

    public init(_ rawValue: Int = 0) {
        self.rawValue = rawValue
    }

    public static let xSmall = DynamicTypeSize(0)
    public static let small = DynamicTypeSize(1)
    public static let medium = DynamicTypeSize(2)
    public static let large = DynamicTypeSize(3)
    public static let xLarge = DynamicTypeSize(4)
    public static let xxLarge = DynamicTypeSize(5)
    public static let xxxLarge = DynamicTypeSize(6)
    public static let accessibility1 = DynamicTypeSize(7)
    public static let accessibility2 = DynamicTypeSize(8)
    public static let accessibility3 = DynamicTypeSize(9)
    public static let accessibility4 = DynamicTypeSize(10)
    public static let accessibility5 = DynamicTypeSize(11)

    public static func < (lhs: DynamicTypeSize, rhs: DynamicTypeSize) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// `ButtonStyle` / `ButtonStyleConfiguration` intentionally live in QuillUI
// (Sources/QuillUI/UpstreamCompatibility.swift), not here. QuillUI
// `@_exported import`s this module, so a second declaration here makes
// `ButtonStyle` (and its `Configuration` typealias) ambiguous for every
// consumer that sees both modules — including the generated apps. This
// module cannot typealias to QuillUI's copy (QuillUI depends on this
// target), so the symbol is simply not declared here.

public struct LayoutSubviews: RandomAccessCollection {
    public typealias Element = LayoutSubview
    private let storage: [LayoutSubview]

    public init(_ storage: [LayoutSubview] = []) {
        self.storage = storage
    }

    public var startIndex: Int { storage.startIndex }
    public var endIndex: Int { storage.endIndex }
    public subscript(position: Int) -> LayoutSubview { storage[position] }
}

public protocol Layout: View where Body == Never {
    typealias Subviews = LayoutSubviews

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
}

public extension Layout {
    var body: Never { fatalError("Layout is a primitive view") }

    func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> LayoutContainer<Self, Content> {
        LayoutContainer(layout: self, content: content())
    }
}

public struct LayoutContainer<L: Layout, Content: View>: View {
    public let layout: L
    public let content: Content

    public var body: some View { content }
}

public extension LayoutSubview {
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        _ = proposal
        return .zero
    }

    func place(at point: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        _ = point
        _ = anchor
        _ = proposal
    }
}

public extension ProposedViewSize {
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

public struct UnevenRoundedRectangle: Shape {
    public typealias Body = Never
    public var topLeadingRadius: CGFloat
    public var bottomLeadingRadius: CGFloat
    public var bottomTrailingRadius: CGFloat
    public var topTrailingRadius: CGFloat

    public init(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0
    ) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
    }

    public func path(in rect: CGRect) -> Path {
        let radius = max(topLeadingRadius, bottomLeadingRadius, bottomTrailingRadius, topTrailingRadius)
        var path = Path()
        path.addRoundedRect(in: rect, cornerRadius: radius)
        return path
    }

    public var body: Never { fatalError("UnevenRoundedRectangle is a primitive shape") }
}

public extension Animation {
    static var bouncy: Animation { .spring }
    static var smooth: Animation { .easeInOut }
    static var snappy: Animation { .easeInOut }

    static func bouncy(duration: Double) -> Animation {
        .spring
    }

    static func bouncy(duration: CGFloat) -> Animation {
        bouncy(duration: Double(duration))
    }

    static func spring(duration: Double) -> Animation {
        Animation(curve: .spring, duration: duration)
    }

    static func spring(duration: CGFloat) -> Animation {
        spring(duration: Double(duration))
    }
}

public struct ContentTransition: Sendable {
    public init() {}
    public static let identity = ContentTransition()

    public static func numericText() -> ContentTransition {
        ContentTransition()
    }

    public static func numericText<Value>(value: Value) -> ContentTransition {
        _ = value
        return ContentTransition()
    }
}

public enum PresentationBackgroundInteraction: Sendable {
    case automatic
    case enabled
    case disabled
}

public struct GlassEffectContainer<Content: View>: View {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        _ = spacing
        self.content = content()
    }

    public var body: some View { content }
}

public struct VStackLayout: Layout {
    public var alignment: HorizontalAlignment
    public var spacing: Double?

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        _ = subviews
        return CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = bounds
        _ = proposal
        _ = subviews
    }
}

public extension Font {
    static func system(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        switch style {
        case .largeTitle: return .system(size: 34, weight: weight, design: design)
        case .title: return .system(size: 28, weight: weight, design: design)
        case .title2: return .system(size: 22, weight: weight, design: design)
        case .title3: return .system(size: 20, weight: weight, design: design)
        case .headline: return .system(size: 17, weight: weight, design: design)
        case .subheadline: return .system(size: 15, weight: weight, design: design)
        case .body: return .system(size: 17, weight: weight, design: design)
        case .callout: return .system(size: 16, weight: weight, design: design)
        case .footnote: return .system(size: 13, weight: weight, design: design)
        case .caption: return .system(size: 12, weight: weight, design: design)
        case .caption2: return .system(size: 11, weight: weight, design: design)
        case .custom(let size, _, _): return .system(size: size, weight: weight, design: design)
        }
    }

    func monospacedDigit() -> Font {
        self
    }
}

// Binding.animation lives in QuillUI (Compatibility.swift), which records the
// fallback — a verbatim twin here made every `$value.animation(...)` call
// ambiguous (generated Enchanted InputFields_macOS: three call sites in one
// body, surfaced as a solver give-up at `var body`). Every app graph imports
// QuillUI, so the richer version is always available.

public extension ViewThatFits {
    init(in axes: Axis, @ViewThatFitsBuilder content: () -> [AnyView]) {
        _ = axes
        self.init(content: content)
    }
}

public extension ForEach {
    func onDelete(perform action: @escaping (IndexSet) -> Void) -> Self {
        _ = action
        return self
    }
}

public extension Shape {
    func fill(_ material: Material) -> FilledShape<Self> {
        _ = material
        return fill(Color.white.opacity(0.92))
    }
}

public extension Double {
    static let layoutPadding: Double = 16
    static let pollBarHeight: Double = 30
    static let statusColumnsSpacing: Double = 8
    static let statusComponentSpacing: Double = 6
}

public extension Int {
    static let scrollToViewHeight = 1
}

public extension State {
    /// Apple's `SwiftUI.State` has `init(initialValue:)`; SwiftOpenUI's `State`
    /// only has `init(wrappedValue:)`, so the `SwiftUI` shim surface (which
    /// re-exports this module but NOT QuillUI) needs this copy for files that
    /// only `import SwiftUI`. QuillUI declares an identical extension
    /// (Sources/QuillUI/UpstreamCompatibility.swift) and `@_exported`-imports
    /// this module, making both visible to every QuillUI importer — disfavor
    /// this copy so QuillUI's wins instead of being ambiguous (behavior is
    /// identical either way).
    @_disfavoredOverload
    init(initialValue: Value) {
        self.init(wrappedValue: initialValue)
    }
}

public extension Text {
    enum DateStyle: Sendable {
        case date
        case time
        case relative
        case offset
        case timer
    }

    init<Value>(_ value: Value, format: NumberFormatStyle) {
        self.init(quillFormatNumber(value, format: format))
    }

    init(_ date: Date, format: DateFormatStyle) {
        _ = format
        self.init(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
    }

    init(_ date: Date, style: DateStyle) {
        _ = style
        self.init(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
    }

    init<T>(_ key: String, _ value: T, style: DateStyle) {
        _ = value
        _ = style
        self.init(key)
    }

    // Text.font lives in SwiftOpenUI (StyleModifiers.swift) — a twin here
    // made `.font(.headline)` ambiguous in the generated Enchanted build.

    func fontWeight(_ weight: FontWeight) -> Text {
        _ = weight
        return self
    }

    func foregroundStyle(_ color: Color) -> Text {
        _ = color
        return self
    }

    @_disfavoredOverload
    func foregroundColor(_ color: Color) -> Text {
        _ = color
        return self
    }

    func bold() -> Text {
        self
    }

    func italic() -> Text {
        self
    }

    @_disfavoredOverload
    static func + (lhs: Text, rhs: Text) -> Text {
        Text(styledRuns: lhs.runs + rhs.runs)
    }
}

public struct ToolbarTitleMenu<Content: View>: ToolbarContent, ToolbarContentItemsProvider {
    public typealias Body = Never

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var toolbarContentItems: [AnyToolbarItem] {
        [AnyToolbarItem(ToolbarItem(placement: .principal) { content })]
    }

    public var body: Never {
        return fatalError("ToolbarTitleMenu is primitive toolbar content")
    }
}

public extension String.StringInterpolation {
    mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) {
        _ = style
        appendLiteral(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
    }

    mutating func appendInterpolation<T>(_ value: T, format: NumberFormatStyle) {
        appendLiteral(quillFormatNumber(value, format: format))
    }
}

public extension Image {
    @_disfavoredOverload
    init(_ name: String) {
        self.init(resource: name)
    }
}

public extension GridItem.Size {
    static func flexible(minimum: Double = 10, maximum: Double = .infinity) -> GridItem.Size {
        _ = minimum
        _ = maximum
        return .flexible
    }

    static func adaptive(minimum: Double, maximum: Double) -> GridItem.Size {
        _ = maximum
        return .adaptive(minimum: minimum)
    }
}

public extension GridItem {
    init(_ size: GridItem.Size = .flexible, spacing: Double? = nil, alignment: Alignment? = nil) {
        _ = spacing
        _ = alignment
        self.init(size)
    }
}

// ForEach's generic-collection init moved INTO SwiftOpenUI's ForEach.swift:
// a cross-module overload overlapping the canonical Array-typed init made
// `ForEach(_, id:)` explode the expression solver inside MenuBuilder
// contexts ("failed to produce diagnostic", generated ModelSelectorView).

public extension LazyVStack where Data == Int {
    init(
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _ = alignment
        _ = spacing
        self.init([0]) { _ in content() }
    }
}

public extension LazyHStack where Data == Int {
    init(
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _ = alignment
        _ = spacing
        self.init([0]) { _ in content() }
    }
}

public extension LazyVGrid where Data == Int {
    init(
        columns: [GridItem],
        spacing: Double? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _ = spacing
        self.init(columns: columns, data: [0]) { _ in content() }
    }
}

public extension Section {
    init<Header: View, Footer: View>(
        header: Header,
        footer: Footer,
        @ViewBuilder content: () -> Content
    ) {
        _ = header
        _ = footer
        self.init(nil, content: content)
    }

    init<Header: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) {
        _ = header()
        self.init(nil, content: content)
    }

    init<Footer: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        _ = footer()
        self.init(nil, content: content)
    }

    init<Header: View, Footer: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        _ = header()
        _ = footer()
        self.init(nil, content: content)
    }
}

public extension Menu {
    @_disfavoredOverload
    init<Label: View>(
        @MenuBuilder content: () -> [MenuElement],
        @ViewBuilder label: () -> Label
    ) {
        _ = label()
        self.init("", content: content)
    }
}

// TextField's axis: init lives in QuillUI/Compatibility.swift — a twin here
// made `init(_:text:axis:)` ambiguous in the generated Enchanted build.

public extension SearchFieldPlacement {
    static var navigationBarDrawer: SearchFieldPlacement {
        .navigationBarDrawer(displayMode: .automatic)
    }
}

public extension TabBuilder {
    static func buildExpression<V: View>(_ view: V) -> [AnyTab] {
        let tabs = quillCollectTabs(from: view)
        if !tabs.isEmpty {
            return tabs
        }
        return [AnyTab(Tab("", id: "tab-\(String(reflecting: V.self))") { view })]
    }
}

fileprivate protocol QuillTabCollectible {
    var quillCollectedTabs: [AnyTab] { get }
}

fileprivate func quillCollectTabs<V: View>(from view: V) -> [AnyTab] {
    quillCollectTabs(fromAny: view)
}

fileprivate func quillCollectTabs(fromAny view: any View) -> [AnyTab] {
    if let tabSource = view as? any QuillTabCollectible {
        return tabSource.quillCollectedTabs
    }
    if let multi = view as? any MultiChildView {
        return multi.children.flatMap(quillCollectTabs(fromAny:))
    }
    return []
}

extension Tab: QuillTabCollectible {
    fileprivate var quillCollectedTabs: [AnyTab] {
        [AnyTab(self)]
    }
}

extension ForEach: QuillTabCollectible {
    fileprivate var quillCollectedTabs: [AnyTab] {
        children.flatMap(quillCollectTabs(fromAny:))
    }
}

extension Optional: QuillTabCollectible where Wrapped: View {
    fileprivate var quillCollectedTabs: [AnyTab] {
        switch self {
        case .some(let wrapped):
            return quillCollectTabs(from: wrapped)
        case .none:
            return []
        }
    }
}

extension _ConditionalView: QuillTabCollectible {
    fileprivate var quillCollectedTabs: [AnyTab] {
        switch self {
        case .trueContent(let content):
            return quillCollectTabs(from: content)
        case .falseContent(let content):
            return quillCollectTabs(from: content)
        }
    }
}

public struct PageTabViewStyle: Sendable {
    public enum IndexDisplayMode: Sendable {
        case automatic
        case always
        case never
    }

    public let indexDisplayMode: IndexDisplayMode
    public init(indexDisplayMode: IndexDisplayMode = .automatic) {
        self.indexDisplayMode = indexDisplayMode
    }
}

public extension PageTabViewStyle {
    static func page(indexDisplayMode: IndexDisplayMode = .automatic) -> PageTabViewStyle {
        PageTabViewStyle(indexDisplayMode: indexDisplayMode)
    }

    static var sidebarAdaptable: PageTabViewStyle {
        PageTabViewStyle()
    }
}

// GroupedFormStyle lives in QuillUI (UpstreamCompatibility.swift), whose
// formStyle(_:) approximates grouping with padding+background; a twin type
// here made `.formStyle(.grouped)` ambiguous in the generated build.

public struct TextContentType: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let URL = TextContentType("URL")
    public static let password = TextContentType("password")
}

public struct TextInputAutocapitalization: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let never = TextInputAutocapitalization("never")
    public static let none = TextInputAutocapitalization("none")
}

public struct TabPlacement: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let automatic = TabPlacement("automatic")
    public static let pinned = TabPlacement("pinned")
    public static let sidebarOnly = TabPlacement("sidebarOnly")
}

public struct SharedBackgroundVisibility: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let automatic = SharedBackgroundVisibility("automatic")
    public static let visible = SharedBackgroundVisibility("visible")
    public static let hidden = SharedBackgroundVisibility("hidden")
}

public struct ImageRenderingMode: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let original = ImageRenderingMode("original")
    public static let template = ImageRenderingMode("template")
}

public extension View {
    func tabViewStyle(_ style: PageTabViewStyle) -> Self {
        _ = style
        return self
    }

    // formStyle(_: GroupedFormStyle) lives in QuillUI with its type.

    func textContentType(_ contentType: TextContentType?) -> Self {
        _ = contentType
        return self
    }

    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> Self {
        _ = autocapitalization
        return self
    }

    func autocorrectionDisabled(_ disabled: Bool = true) -> Self {
        _ = disabled
        return self
    }

    @_disfavoredOverload
    func onAppear(perform action: @escaping () -> Void) -> OnAppearView<Self> {
        onAppear(action)
    }

    func onReceive<Publisher>(
        _ publisher: Publisher,
        perform action: @escaping (Publisher.Output) -> Void
    ) -> Self where Publisher: Combine.Publisher {
        _ = publisher
        _ = action
        return self
    }

    func navigationDestination<Item, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: (Item) -> Destination
    ) -> Self {
        _ = item
        return self
    }

    func navigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: () -> Destination
    ) -> Self {
        _ = isPresented
        _ = destination()
        return self
    }

    func onOpenURL(perform action: @escaping (URL) -> Void) -> Self {
        _ = action
        return self
    }

    @_disfavoredOverload
    func mask<Mask: View>(_ mask: Mask) -> Self {
        _ = mask
        return self
    }

    func mask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> Self {
        _ = mask()
        return self
    }
}

public extension Image {
    func renderingMode(_ mode: ImageRenderingMode?) -> Image {
        _ = mode
        return self
    }
}

public extension Tab {
    init<Value: Hashable, Label: View>(
        value: Value,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        _ = value
        _ = role
        _ = label()
        self.init("", id: String(describing: value), content: content)
    }

    func tabPlacement(_ placement: TabPlacement) -> Self {
        _ = placement
        return self
    }

    func badge(_ count: Int) -> Self {
        _ = count
        return self
    }
}

public struct TabRole: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let search = TabRole("search")
}

public struct TabSection<Content: View>: View {
    public let title: String
    public let content: Content

    public init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title.resolved
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View { content }

    public func tabPlacement(_ placement: TabPlacement) -> Self {
        _ = placement
        return self
    }
}

extension TabSection: QuillTabCollectible {
    fileprivate var quillCollectedTabs: [AnyTab] {
        quillCollectTabs(from: content)
    }
}

public struct EditButton: View {
    public init() {}
    public var body: some View { Button("Edit") {} }
}

public extension ToolbarItem {
    func sharedBackgroundVisibility(_ visibility: SharedBackgroundVisibility) -> Self {
        _ = visibility
        return self
    }
}

public typealias AccessibilityFocusState<Value: Hashable> = FocusState<Value>

public extension ViewDimensions {
    subscript(_ alignment: VerticalAlignment) -> CGFloat {
        _ = alignment
        return height
    }
}

public enum ListRowSeparatorLeadingAlignmentID: AlignmentID {
    public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width }
}

public enum ListRowSeparatorTrailingAlignmentID: AlignmentID {
    public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width }
}

public extension VerticalAlignment {
    static var leading: VerticalAlignment { .center }
    static var listRowSeparatorLeading: VerticalAlignment { VerticalAlignment(ListRowSeparatorLeadingAlignmentID.self) }
    static var listRowSeparatorTrailing: VerticalAlignment { VerticalAlignment(ListRowSeparatorTrailingAlignmentID.self) }
}

public struct ColorPicker<Label: View>: View {
    public let label: Label
    public let selection: Binding<Color>

    public init<T>(_ title: T, selection: Binding<Color>) where Label == Text {
        self.label = Text(String(describing: title))
        self.selection = selection
    }

    public init(selection: Binding<Color>, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
    }

    public var body: some View {
        label
    }
}

public struct LabeledContent<Content: View>: View {
    public let title: String
    public let content: Content

    public init<T>(_ title: T, @ViewBuilder content: () -> Content) {
        self.title = String(describing: title)
        self.content = content()
    }

    public init<T, Value>(_ title: T, value: Value) where Content == Text {
        self.title = String(describing: title)
        self.content = Text(String(describing: value))
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 16)
            content
                .multilineTextAlignment(.trailing)
        }
    }
}

public struct PresentationSizing: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    public static let page = PresentationSizing("page")
}

public extension HStack {
    init(
        alignment: VerticalAlignment = .center,
        spacing: Double?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            spacing: spacing.map(Int.init) ?? stackDefaultSpacing,
            content: content
        )
    }
}

public extension VStack {
    init(
        alignment: HorizontalAlignment = .center,
        spacing: Double?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            spacing: spacing.map(Int.init) ?? stackDefaultSpacing,
            content: content
        )
    }
}

public extension View {
    func task<ID: Equatable>(
        id: ID,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping () async -> Void
    ) -> TaskView<Self> {
        _ = id
        let box = QuillTaskActionBox(action)
        return TaskView(content: self, priority: priority, action: { await box.run() })
    }

    // listStyle(PlainListStyle) lives in QuillUI (Compatibility.swift), which
    // records the fallback — a verbatim twin here made the generated
    // MenuBarControlView Events chain ambiguous (reported as "ambiguous use
    // of 'showIf'" further up the chained expression).

    func pickerStyle(_ style: PickerStyle) -> Self {
        _ = style
        return self
    }

    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> Self {
        _ = mode
        return self
    }

    func font(_ font: Font?) -> Self {
        _ = font
        return self
    }

    func brightness(_ amount: Double) -> Self {
        _ = amount
        return self
    }

    func labelStyle(_ style: LabelStyleType) -> Self {
        _ = style
        return self
    }

    func menuStyle(_ style: MenuStyleType) -> Self {
        _ = style
        return self
    }

    func controlGroupStyle(_ style: ControlGroupStyleType) -> Self {
        _ = style
        return self
    }

    func dynamicTypeSize(_ size: DynamicTypeSize) -> Self {
        _ = size
        return self
    }

    func monospacedDigit() -> Self {
        self
    }

    // No generic `buttonStyle<S: ButtonStyle>` shim here: the ButtonStyle
    // protocol lives in QuillUI (UpstreamCompatibility.swift), whose View
    // extension already provides the custom-style fallback. Built-in styles
    // like `.buttonStyle(.plain)` resolve to SwiftOpenUI's
    // `buttonStyle(_: ButtonStyleType)`.

    func controlSize(_ size: ControlSize) -> Self {
        _ = size
        return self
    }

    func symbolVariant(_ variant: SymbolVariants) -> Self {
        _ = variant
        return self
    }

    func scrollClipDisabled(_ disabled: Bool = true) -> Self {
        _ = disabled
        return self
    }

    func scrollIndicators(_ visibility: Visibility) -> Self {
        _ = visibility
        return self
    }

    func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = .all) -> Self {
        _ = behavior
        _ = axes
        return self
    }

    func refreshable(action: @escaping () async -> Void) -> Self {
        _ = action
        return self
    }

    func allowsHitTesting(_ enabled: Bool) -> Self {
        _ = enabled
        return self
    }

    func accessibilitySortPriority(_ priority: Double) -> Self {
        _ = priority
        return self
    }

    func listSectionSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> Self {
        _ = visibility
        _ = edges
        return self
    }

    // overlay(_ color:alignment:) moved INTO SwiftOpenUI's
    // OverlayModifier.swift beside the generic overlay<V: View> — Color is
    // a View, so a twin here paired with that generic cross-module on every
    // Color argument (the established ambiguity disease in the generated
    // Enchanted build; concrete-vs-generic ranking is only reliable
    // same-module).

    func interactiveDismissDisabled(_ isDisabled: Bool = true) -> Self {
        _ = isDisabled
        return self
    }

    func accessibilityInputLabels<T>(_ labels: [T]) -> Self {
        _ = labels
        return self
    }

    @_disfavoredOverload
    func accessibility(hidden: Bool) -> Self {
        _ = hidden
        return self
    }

    func accessibility(label: Text) -> Self {
        _ = label
        return self
    }

    func transition(_ transition: AnyTransition) -> Self {
        _ = transition
        return self
    }

    @_disfavoredOverload
    func preferredColorScheme(_ colorScheme: ColorScheme?) -> Self {
        _ = colorScheme
        return self
    }

    // contentShape lives in QuillUI (UpstreamCompatibility.swift), which
    // preserves the hit-testing shape as metadata. A twin here — even
    // @_disfavoredOverload — still tied cross-module inside ViewBuilder
    // closures (generated Enchanted InputFields_macOS,
    // `.contentShape(Rectangle())` at the tail of the composer body).

    @_disfavoredOverload
    func onHover(perform action: @escaping (Bool) -> Void) -> Self {
        _ = action
        return self
    }

    @_disfavoredOverload
    func accessibilityLabel(_ label: String) -> Self {
        _ = label
        return self
    }

    @_disfavoredOverload
    func accessibilityLabel<T>(_ label: T) -> Self {
        _ = label
        return self
    }

    @_disfavoredOverload
    func accessibilityValue(_ value: String) -> Self {
        _ = value
        return self
    }

    @_disfavoredOverload
    func accessibilityValue<T>(_ value: T) -> Self {
        _ = value
        return self
    }

    @_disfavoredOverload
    func accessibilityElement(children: AccessibilityChildBehavior) -> Self {
        _ = children
        return self
    }

    @_disfavoredOverload
    func accessibilityAddTraits(_ traits: AccessibilityTraits) -> Self {
        _ = traits
        return self
    }

    @_disfavoredOverload
    func accessibility(addTraits traits: AccessibilityTraits) -> Self {
        _ = traits
        return self
    }

    @_disfavoredOverload
    func accessibilityHint(_ hint: String) -> Self {
        _ = hint
        return self
    }

    @_disfavoredOverload
    func accessibilityHint<T>(_ hint: T) -> Self {
        _ = hint
        return self
    }

    @_disfavoredOverload
    func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> Self {
        _ = traits
        return self
    }

    @_disfavoredOverload
    func accessibilityRepresentation<Representation: View>(
        @ViewBuilder representation: () -> Representation
    ) -> Self {
        _ = representation()
        return self
    }

    @_disfavoredOverload
    func accessibilityRespondsToUserInteraction(_ responds: Bool) -> Self {
        _ = responds
        return self
    }

    @_disfavoredOverload
    func accessibilityActions<Actions: View>(@ViewBuilder _ actions: () -> Actions) -> Self {
        _ = actions()
        return self
    }

    @_disfavoredOverload
    func accessibilityAction(_ action: @escaping () -> Void) -> Self {
        _ = action
        return self
    }

    @_disfavoredOverload
    func accessibilityAction(_ kind: AccessibilityActionKind, _ action: @escaping () -> Void) -> Self {
        _ = kind
        _ = action
        return self
    }

    @_disfavoredOverload
    func textSelection(_ selection: TextSelectability = .enabled) -> Self {
        _ = selection
        return self
    }

    @_disfavoredOverload
    func minimumScaleFactor(_ factor: Double) -> Self {
        _ = factor
        return self
    }

    @_disfavoredOverload
    func buttonBorderShape(_ shape: ButtonBorderShape) -> Self {
        _ = shape
        return self
    }

    @_disfavoredOverload
    func foregroundColor(_ color: Color?) -> ForegroundColorView<Self> {
        foregroundColor(color ?? .clear)
    }

    func alignmentGuide(
        _ alignment: VerticalAlignment,
        computeValue: (ViewDimensions) -> CGFloat
    ) -> Self {
        _ = alignment
        _ = computeValue(ViewDimensions())
        return self
    }

    @_disfavoredOverload
    func listRowInsets(_ insets: EdgeInsets?) -> Self {
        _ = insets
        return self
    }

    // listRowSeparator lives in QuillUI (UpstreamCompatibility.swift), which
    // preserves it as list-row metadata. Cross-module @_disfavoredOverload is
    // not honored inside ViewBuilder closures, so a twin here still made the
    // generated MenuBarControlView Events chain (`.listRowSeparator(.hidden)`
    // inside ForEach) ambiguous.

    // Double/Int? padding adapters now live IN SwiftOpenUI's
    // PaddingModifier.swift (same module as the canonical Int overloads):
    // cross-module overload sets — even @_disfavoredOverload ones — made
    // bare `.padding()` ambiguous inside generic/ViewBuilder contexts in
    // the generated Enchanted build. Same-module ranking is reliable.
    // The CGFloat? edge-set adapter stays HERE (CGFloat is QuillFoundation's
    // type; SwiftOpenUI core must stay platform-independent) — safe because
    // a two-argument overload never competes with bare `.padding()`.
    @_disfavoredOverload
    func padding(_ edges: Edge.Set, _ amount: CGFloat?) -> PaddedView<Self> {
        padding(edges, amount.map { Int($0) } ?? 8)
    }

    // The single-argument CGFloat adapter likewise lives HERE (moved from
    // QuillUI, where it was an undisfavored cross-module rival of
    // SwiftOpenUI's canonical Int/Double single-arg overloads for every
    // `.padding(8)` literal — a twin in the set that surfaced as
    // "ambiguous use of 'padding'" in the generated Enchanted
    // CompletionsEditorView). Safe for the same reason as the edge-set
    // adapter above: a one-required-argument overload never competes with
    // bare `.padding()`.
    @_disfavoredOverload
    func padding(_ amount: CGFloat) -> PaddedView<Self> {
        padding(Int(amount))
    }

    // padding(_ insets: EdgeInsets) lives in QuillUI (verbatim twin here
    // made every .padding(insets) call ambiguous).

    // frame(width:height: Int?) now lives IN SwiftOpenUI's FrameModifier.swift
    // (same module as the canonical Double? overload): the cross-module twin
    // here made `.frame(width: 800, height: 600)` integer-literal calls
    // ambiguous — surfaced as "ambiguous use of 'padding'" at the head of
    // the chain (generated Enchanted CompletionsEditorView).

    // The CGFloat frame adapters stay HERE (CGFloat is QuillFoundation's
    // type; SwiftOpenUI core stays platform-independent) but must be
    // @_disfavoredOverload: undisfavored they tied with SwiftOpenUI's
    // Double? frame overloads on literal / `.infinity` arguments.
    @_disfavoredOverload
    func frame(maxWidth: CGFloat?, alignment: Alignment = .center) -> FrameView<Self> {
        frame(maxWidth: maxWidth.map(Double.init), alignment: alignment)
    }

    func onChange<V: Equatable>(of value: V, _ action: @escaping () -> Void) -> OnChangeView<Self, V> {
        onChange(of: value) { _ in action() }
    }

    func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping () -> Void
    ) -> OnChangeView<Self, V> {
        _ = initial
        return onChange(of: value, action)
    }

    func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping (V) -> Void
    ) -> OnChangeView<Self, V> {
        _ = initial
        return onChange(of: value, perform: action)
    }

    func onTapGesture(count: Int = 1, perform action: @escaping (CGPoint) -> Void) -> TapGestureView<Self> {
        onTapGesture(count: count) {
            action(.zero)
        }
    }

    func alert<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> Self {
        _ = title
        _ = isPresented
        _ = actions()
        _ = message()
        return self
    }

    func alert<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions
    ) -> Self {
        _ = title
        _ = isPresented
        _ = actions()
        return self
    }

    func alert(isPresented: Binding<Bool>, content: () -> Alert) -> Self {
        _ = isPresented
        _ = content()
        return self
    }

    func confirmationDialog<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions
    ) -> Self {
        _ = title
        _ = isPresented
        _ = actions()
        return self
    }

    func confirmationDialog<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility,
        @ViewBuilder actions: () -> Actions
    ) -> Self {
        _ = title
        _ = isPresented
        _ = titleVisibility
        _ = actions()
        return self
    }

    func swipeActions<Actions: View>(
        edge: Edge = .trailing,
        allowsFullSwipe: Bool = true,
        @ViewBuilder content: () -> Actions
    ) -> Self {
        _ = edge
        _ = allowsFullSwipe
        _ = content()
        return self
    }

    func draggable<T>(_ payload: T) -> Self {
        _ = payload
        return self
    }

    func quickLookPreview(_ item: Binding<URL?>) -> Self {
        _ = item
        return self
    }

    func accessibilityFocused<Value: Hashable>(
        _ binding: FocusState<Value>.Binding,
        equals value: Value
    ) -> Self {
        _ = binding
        _ = value
        return self
    }

    func progressViewStyle(_ style: ProgressViewStyle) -> Self {
        _ = style
        return self
    }

    func redacted(reason: RedactionReasons) -> Self {
        _ = reason
        return self
    }

    func foregroundStyle(_ primary: Color, _ secondary: Color) -> Self {
        _ = primary
        _ = secondary
        return self
    }

    func presentationDetents(_ detents: Set<PresentationDetent>) -> Self {
        _ = detents
        return self
    }

    func presentationDetents(_ detents: [PresentationDetent]) -> Self {
        presentationDetents(Set(detents))
    }

    func presentationDetents(
        _ detents: Set<PresentationDetent>,
        selection: Binding<PresentationDetent>
    ) -> Self {
        _ = detents
        _ = selection
        return self
    }

    func presentationDetents(
        _ detents: [PresentationDetent],
        selection: Binding<PresentationDetent>
    ) -> Self {
        presentationDetents(Set(detents), selection: selection)
    }

    func navigationTransition(_ transition: NavigationTransition) -> Self {
        _ = transition
        return self
    }

    func presentationBackground(_ material: Material) -> Self {
        _ = material
        return self
    }

    func presentationBackground(_ color: Color) -> Self {
        _ = color
        return self
    }

    func presentationSizing(_ sizing: PresentationSizing) -> Self {
        _ = sizing
        return self
    }

    func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> Self {
        _ = interaction
        return self
    }

    func background(_ material: Material) -> Self {
        _ = material
        return self
    }

    func presentationCornerRadius(_ radius: Double) -> Self {
        _ = radius
        return self
    }

    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarTitleDisplayMode) -> Self {
        _ = displayMode
        return self
    }

    func toolbarBackground(_ visibility: Visibility, for target: ToolbarPlacementTarget) -> Self {
        _ = visibility
        _ = target
        return self
    }

    @_disfavoredOverload
    func navigationTitle<T>(_ title: T) -> Self {
        _ = title
        return self
    }

    // scrollContentBackground lives in QuillUI.

    // matchedGeometryEffect lives in QuillUI (UpstreamCompatibility.swift),
    // which approximates it with value-driven animation and records the
    // fallback. A same-signature no-op here became ambiguous with it once
    // Namespace unified to this module's type. Every app graph imports
    // QuillUI, so the richer version is always available.

    func matchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> Self {
        _ = id
        _ = namespace
        return self
    }

    func containerRelativeFrame(_ axes: [Axis]) -> Self {
        _ = axes
        return self
    }

    func containerRelativeFrame(
        _ axes: Axis,
        count: Int,
        span: Int,
        spacing: CGFloat,
        alignment: Alignment = .center
    ) -> Self {
        _ = axes
        _ = count
        _ = span
        _ = spacing
        _ = alignment
        return self
    }

    func scrollTargetLayout() -> Self {
        self
    }

    func scrollTargetBehavior(_ behavior: ScrollTargetBehavior) -> Self {
        _ = behavior
        return self
    }

    func scrollPosition<ID: Hashable>(id: Binding<ID?>) -> Self {
        _ = id
        return self
    }

    func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint?) -> Self {
        _ = id
        _ = anchor
        return self
    }

    // @_disfavoredOverload like the other CGFloat frame adapters: an
    // undisfavored twin here ties with SwiftOpenUI's frame(width:height:
    // Double?) on literal height arguments (cross-module sets are the
    // ambiguity disease; see the frame(width:height:) note above).
    @_disfavoredOverload
    func frame(height: CGFloat?, alignment: Alignment = .center) -> FrameView<Self> {
        frame(height: height.map(Double.init), alignment: alignment)
    }

    func focusable(_ isFocusable: Bool = true) -> Self {
        _ = isFocusable
        return self
    }

    // focusEffectDisabled lives in QuillUI (metadata-preserving version).

    func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPressResult) -> Self {
        _ = key
        _ = action
        return self
    }

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

    func glassEffect(_ effect: GlassEffect, in shape: GlassEffectShape) -> Self {
        _ = effect
        _ = shape
        return self
    }

    func glassEffect(_ effect: GlassEffect) -> Self {
        _ = effect
        return self
    }

    func glassEffect() -> Self {
        glassEffect(.regular)
    }

    func glassEffect<S: Shape>(_ effect: GlassEffect, in shape: S) -> Self {
        _ = effect
        _ = shape
        return self
    }

    func background<S: Shape>(_ material: Material, in shape: S) -> Self {
        _ = material
        _ = shape
        return self
    }

    func backgroundStyle(_ material: Material) -> Self {
        _ = material
        return self
    }

    func background<S: Shape>(_ color: Color, in shape: S) -> Self {
        _ = color
        _ = shape
        return self
    }

    func hoverEffect(_ effect: HoverEffect) -> Self {
        _ = effect
        return self
    }

    func hoverEffect() -> Self {
        hoverEffect(.lift)
    }

    func contentTransition(_ transition: ContentTransition) -> Self {
        _ = transition
        return self
    }

    // edgesIgnoringSafeArea lives in QuillUI (metadata-preserving version).

    func safeAreaBar<Content: View>(
        edge: Edge,
        @ViewBuilder content: () -> Content
    ) -> Self {
        _ = edge
        _ = content()
        return self
    }
}

public extension Menu {
    init(_ title: LocalizedStringKey, @MenuBuilder content: () -> [MenuElement]) {
        self.init(title.resolved, content: content)
    }
}

public extension View {
    func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text
    ) -> SearchableView<Self> {
        searchable(
            text: text,
            isPresented: isPresented,
            placement: placement,
            prompt: prompt.content
        )
    }
}

public extension SearchableView {
    func searchScopes<Scope, ScopeContent: View>(
        _ selection: Binding<Scope>,
        @ViewBuilder _ content: () -> ScopeContent
    ) -> SearchableView<Content> {
        _ = selection
        _ = content()
        return self
    }
}

private final class QuillTaskActionBox: @unchecked Sendable {
    private let action: () async -> Void

    init(_ action: @escaping () async -> Void) {
        self.action = action
    }

    func run() async {
        await action()
    }
}

public extension View {
    func contextMenu<MenuContent: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuContent,
        @ViewBuilder preview: () -> Preview
    ) -> Self {
        _ = menuItems()
        _ = preview()
        return self
    }
}

public extension GeometryProxy {
    subscript(_ rect: CGRect) -> CGRect { rect }
}

public extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let sortedSource = source.sorted()
        let moving = sortedSource.map { self[$0] }
        for index in sortedSource.reversed() {
            remove(at: index)
        }
        let removedBeforeDestination = sortedSource.filter { $0 < destination }.count
        let insertionIndex = Swift.max(0, Swift.min(count, destination - removedBeforeDestination))
        insert(contentsOf: moving, at: insertionIndex)
    }
}


public extension URL {
    func startAccessingSecurityScopedResource() -> Bool { true }
    func stopAccessingSecurityScopedResource() {}
}
