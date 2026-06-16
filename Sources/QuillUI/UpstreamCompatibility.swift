import Foundation
#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI
import QuillSwiftUICompatibility
import QuillKit
import QuillFoundation
import class UIKit.NSItemProvider
import enum UIKit.UIKeyboardType
// App-chrome shims that BOTH `import QuillUI` and the Linux `import SwiftUI`
// shadow must see (Material, command/menu builder expressions, WindowGroup
// conveniences, …) are canonical in QuillSwiftUICompatibility; primitive
// renderer-visible surfaces (ButtonRole, ButtonStyle, …) live in SwiftOpenUI.
// QuillUI re-exports the compatibility module, so keeping ONE defining module
// avoids ambiguous lookups in files that import both (see the
// firstTextBaseline note below for the same pattern).
// This file still references several of those names (Shape.fill(_ material:),
// PlainButtonStyle, …) via the direct import at the top of this block.
@_exported import CoreTransferable
@_exported import UniformTypeIdentifiers

#if !os(macOS) && !os(iOS) && !os(visionOS)
private func recordQuillUIFallback(_ operation: String, message: String) {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "QuillUI",
        operation: operation,
        severity: .info,
        message: message
    )
}

private func recordQuillUIFallbackView<Content: View>(
    _ view: Content,
    operation: String,
    message: String
) -> Content {
    recordQuillUIFallback(operation, message: message)
    return view
}

public extension UTType {
    static func type(for url: URL) -> UTType? {
        UTType(filenameExtension: url.pathExtension)
    }

    fileprivate func accepts(url: URL) -> Bool {
        UTType.type(for: url)?.conforms(to: self) == true
    }
}
#endif

// `Material` moved to QuillSwiftUICompatibility so real source that only
// `import SwiftUI`s sees it; QuillUI re-exports that module. (Namespace
// lives in DesignSystemSurfaceCompat.swift.)
// `FocusState` was previously declared here as a Binding-projecting
// shim, but SwiftOpenUI ships its own `FocusState<Value: Hashable>`
// with `projectedValue: FocusState<Value>` and a matching
// `View.focused(_:)` modifier overload. Having both visible to
// `import QuillUI` consumers (via the @_exported SwiftOpenUI plus
// QuillUI's own struct) caused ~230 "'FocusState' is ambiguous for
// type lookup" errors in the generated Enchanted Linux build.
// SwiftOpenUI's version is the canonical one going forward —
// callers get it transparently through `@_exported import SwiftOpenUI`.
// QuillUI only fills source-compatibility initializer gaps around that
// canonical type.

public extension FocusState where Value == Bool {
    init(wrappedValue: Bool) {
        self.init()
        self.wrappedValue = wrappedValue
    }
}

public extension FocusState {
    init<Wrapped>(wrappedValue: Wrapped?) where Value == Wrapped? {
        self.init()
        self.wrappedValue = wrappedValue
    }
}

public struct PinnedScrollableViews: OptionSet, Sendable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

public struct ContextMenu {
    public var menuElements: [MenuElement]

    public init(@MenuBuilder menuItems: () -> [MenuElement]) {
        self.menuElements = menuItems()
    }
}

public enum TextSelectability: Sendable {
    case enabled
    case disabled
}

#if !os(macOS) && !os(iOS) && !os(visionOS)
public typealias ToolbarItemGroup<Content: View> = ToolbarItem<Content>

// `VerticalAlignment.firstTextBaseline` / `.lastTextBaseline`
// live in `QuillSwiftUICompatibility`, which both `QuillUI` and
// the Linux `SwiftUI` shadow re-export. Keeping one defining
// module avoids ambiguous uses in code that imports both modules.

public extension GridItem.Size {
    static func flexible(minimum: Double = 10, maximum: Double = .infinity) -> GridItem.Size {
        .flexible
    }

    static func fixed(_ size: Double) -> GridItem.Size {
        .fixed
    }
}

public extension GridItem {
    init(_ size: Size = .flexible, spacing: Double? = nil, alignment: Alignment? = nil) {
        self.init(size)
    }
}

public extension LazyVGrid where Data == Int {
    init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(columns: columns, data: [0]) { _ in content() }
    }
}
#endif

public extension Animation {
    static func snappy(duration: Double = 0.35) -> Animation {
        QuillCompatibilityDiagnostics.shared.record(
            QuillCompatibilityEvent(
                subsystem: "QuillUI",
                operation: "Animation.snappy",
                severity: .warning,
                message: "Animation.snappy is approximated by .easeOut(duration:) on Linux. Real SwiftUI's snappy is a spring; motion shape will differ."
            )
        )
        return .easeOut(duration: duration)
    }

    // `repeatForever(autoreverses:)` moved to QuillSwiftUICompatibility
    // (SolderScopeChrome.swift) so `import SwiftUI` files see it as well.
    // That module links QuillKit (via DesignSystemSurfaceCompat), so it keeps
    // recording the `.info` compatibility diagnostic there.

    func delay(_ delay: Double) -> Animation {
        recordQuillUIFallback(
            "Animation.delay",
            message: "Animation.delay metadata is preserved on Linux and GTK transitions apply it as CSS transition delay."
        )
        return Animation(
            curve: curve,
            duration: duration,
            delay: self.delay + max(0, delay),
            repeatsForever: repeatsForever,
            autoreverses: autoreverses
        )
    }
}

@MainActor
public func withAnimation(_ animation: Animation = .default, _ body: @MainActor () -> Void) {
    SwiftOpenUI.withAnimation(animation) {
        MainActor.assumeIsolated {
            body()
        }
    }
}

public extension CommandGroupPlacement {
    static var appInfo: CommandGroupPlacement { .help }
}

public extension CommandGroup {
    init(
        after placement: CommandGroupPlacement,
        @CommandMenuBuilder content: () -> [CommandMenuItem]
    ) {
        self.init(replacing: placement, content: content)
    }
}

// `WindowGroup.defaultSize(width:height:)`, the `CommandMenuBuilder` /
// `MenuBuilder` view-expression overloads, and `Menu(content:label:)` moved
// to QuillSwiftUICompatibility (SolderScopeChrome.swift) so real source that
// only `import SwiftUI`s sees them (SolderScope's camera-picker Menu and
// command menus); QuillUI re-exports that module. The moved builder
// expressions walk view trees with self-contained equivalents of the
// quill* helpers below (which stay here — Picker/Section/Label inits and
// the @_spi(QuillTesting) surface still use them).

public extension PickerStyle {
    static var menu: PickerStyle { .automatic }
}

public struct MenuPickerStyle: Sendable {
    public init() {}
}

public extension Picker {
    init<SelectionValue: Hashable, Content: View, LabelContent: View>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> LabelContent
    ) {
        let extracted = quillPickerOptions(from: content())
        let tags = extracted.map(\.tag)
        let labelText = quillTextLabel(from: label())
        let indexSelection = Binding<Int>(
            get: {
                tags.firstIndex(of: AnyHashable(selection.wrappedValue)) ?? 0
            },
            set: { index in
                guard tags.indices.contains(index),
                      let value = tags[index].base as? SelectionValue,
                      value != selection.wrappedValue
                else { return }
                selection.wrappedValue = value
            }
        )
        self.init(labelText, selection: indexSelection, options: extracted.map(\.label))
    }

    func pickerStyle(_ style: MenuPickerStyle) -> Picker {
        pickerStyle(.automatic)
    }
}

public extension Section {
    init<Header: View>(
        header: Header,
        @ViewBuilder content: () -> Content
    ) {
        self.init(header: quillTextLabel(from: header), content: content)
    }
}

public extension Image {
    /// Linux source-compatibility inits matching SwiftUI's
    /// `Image(nsImage:)` / `Image(uiImage:)`. SwiftOpenUI's
    /// `Image` doesn't have bitmap-decoding initializers yet;
    /// fall through to the system-symbol placeholder so call
    /// sites compile. When a real GTK decoder lands, both can
    /// route through `image.data`. (`init(data:)` is provided
    /// separately in `Compatibility.swift` with a temp-file
    /// implementation.)
    init(nsImage image: RSImage) {
        self.init(systemName: "photo")
    }

    init(uiImage image: RSImage) {
        self.init(systemName: "photo")
    }

    enum TemplateRenderingMode {
        case original
        case template
    }

    enum SymbolRenderingMode {
        case monochrome
        case hierarchical
        case palette
        case multicolor
    }

    func renderingMode(_ mode: TemplateRenderingMode) -> Image {
        renderingMode(Optional(mode))
    }

    func renderingMode(_ mode: TemplateRenderingMode?) -> Image {
        recordQuillUIFallback(
            "renderingMode",
            message: "Image renderingMode is currently a source-compatibility fallback on Linux."
        )
        return self
    }

    func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image {
        recordQuillUIFallback(
            "symbolRenderingMode",
            message: "Image symbolRenderingMode is currently a source-compatibility fallback on Linux."
        )
        return self
    }
}

extension Image: @retroactive Equatable {
    // nonisolated: Equatable's requirement is nonisolated and == is pure
    // value comparison of stored data.
    nonisolated public static func == (lhs: Image, rhs: Image) -> Bool {
        switch (lhs.source, rhs.source) {
        case (.systemName(let left), .systemName(let right)):
            return left == right && lhs.scale == rhs.scale && lhs.isResizable == rhs.isResizable
        case (.filePath(let left), .filePath(let right)):
            return left == right && lhs.scale == rhs.scale && lhs.isResizable == rhs.isResizable
        case (.materialSymbol(let left), .materialSymbol(let right)):
            return left == right && lhs.scale == rhs.scale && lhs.isResizable == rhs.isResizable
        default:
            return false
        }
    }
}

// Title-less `WindowGroup { … }` init + State(initialValue:) live in
// QuillSwiftUICompatibility (DesignSystemSurfaceCompat.swift).

public struct LabeledContent<Content: View>: View {
    public var title: String
    public var content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public init<Value>(_ title: String, value: Value) where Content == Text {
        self.title = title
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

public struct AccessibilityChildBehavior: Hashable, Sendable {
    private let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let combine = AccessibilityChildBehavior("combine")
    public static let ignore = AccessibilityChildBehavior("ignore")
}

public struct AccessibilityLabelView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let label: String

    public var body: Never { fatalError("AccessibilityLabelView is a primitive view") }
}

public struct AccessibilityValueView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let value: String

    public var body: Never { fatalError("AccessibilityValueView is a primitive view") }
}

public struct AccessibilityElementView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let children: AccessibilityChildBehavior

    public var body: Never { fatalError("AccessibilityElementView is a primitive view") }
}

public struct MinimumScaleFactorView<Content: View>: View {
    public let content: Content
    public let factor: Double

    public init(content: Content, factor: Double) {
        self.content = content
        self.factor = factor
    }

    public var body: some View { content }
}

public struct ImageScaleView<Content: View>: View {
    public let content: Content
    public let scale: ImageScale

    public init(content: Content, scale: ImageScale) {
        self.content = content
        self.scale = scale
    }

    public var body: some View { content }
}

public struct SymbolRenderingModeView<Content: View>: View {
    public let content: Content
    public let mode: Image.SymbolRenderingMode?

    public init(content: Content, mode: Image.SymbolRenderingMode?) {
        self.content = content
        self.mode = mode
    }

    public var body: some View { content }
}

public struct ListRowInsetsView<Content: View>: View {
    public let content: Content
    public let insets: EdgeInsets?

    public init(content: Content, insets: EdgeInsets?) {
        self.content = content
        self.insets = insets
    }

    public var body: some View { content }
}

public struct ListRowSeparatorView<Content: View>: View {
    public let content: Content
    public let visibility: Visibility
    public let edges: Edge.Set

    public init(content: Content, visibility: Visibility, edges: Edge.Set) {
        self.content = content
        self.visibility = visibility
        self.edges = edges
    }

    public var body: some View { content }
}

public struct ContentShapeView<Content: View, ShapeValue: Shape>: View {
    public let content: Content
    public let shape: ShapeValue

    public init(content: Content, shape: ShapeValue) {
        self.content = content
        self.shape = shape
    }

    public var body: some View { content }
}

public struct AllowsHitTestingView<Content: View>: View {
    public let content: Content
    public let enabled: Bool

    public init(content: Content, enabled: Bool) {
        self.content = content
        self.enabled = enabled
    }

    public var body: some View { content }
}

public struct GestureView<Content: View, GestureValue>: View {
    public let content: Content
    public let gesture: GestureValue

    public init(content: Content, gesture: GestureValue) {
        self.content = content
        self.gesture = gesture
    }

    public var body: some View { content }
}

public struct TransitionView<Content: View>: View {
    public let content: Content
    public let transition: AnyTransition

    public init(content: Content, transition: AnyTransition) {
        self.content = content
        self.transition = transition
    }

    public var body: some View { content }
}

public struct SymbolEffectView<Content: View, Value: Equatable>: View {
    public let content: Content
    public let effect: SymbolEffect
    public let options: SymbolEffectOptions
    public let value: Value

    public init(
        content: Content,
        effect: SymbolEffect,
        options: SymbolEffectOptions,
        value: Value
    ) {
        self.content = content
        self.effect = effect
        self.options = options
        self.value = value
    }

    public var body: some View { content }
}

public struct ViewMaskView<Content: View, MaskContent: View>: View {
    public let content: Content
    public let mask: MaskContent

    public init(content: Content, mask: MaskContent) {
        self.content = content
        self.mask = mask
    }

    public var body: some View { content }
}

public struct OnHoverView<Content: View>: View {
    public let content: Content
    public let action: (Bool) -> Void

    public init(content: Content, action: @escaping (Bool) -> Void) {
        self.content = content
        self.action = action
    }

    public var body: some View { content }
}

public struct FocusBindingView<Content: View, Value>: View {
    public let content: Content
    public let binding: Binding<Value>

    public init(content: Content, binding: Binding<Value>) {
        self.content = content
        self.binding = binding
    }

    public var body: some View { content }
}

public struct FocusEqualsBindingView<Content: View, Value: Equatable>: View {
    public let content: Content
    public let binding: Binding<Value?>
    public let value: Value

    public init(content: Content, binding: Binding<Value?>, value: Value) {
        self.content = content
        self.binding = binding
        self.value = value
    }

    public var body: some View { content }
}

public struct TextSelectionView<Content: View>: View {
    public let content: Content
    public let selection: TextSelectability

    public init(content: Content, selection: TextSelectability) {
        self.content = content
        self.selection = selection
    }

    public var body: some View { content }
}

public extension View {
    func antialiased(_ antialiased: Bool) -> Self {
        self
    }

    func imageScale(_ scale: ImageScale) -> ImageScaleView<Self> {
        recordQuillUIFallback(
            "imageScale",
            message: "View imageScale is preserved as image metadata on Linux."
        )
        return ImageScaleView(content: self, scale: scale)
    }
}

public extension Shape {
    func strokeBorder(style: StrokeStyle) -> StrokedShape<Self> {
        strokeBorder(.primary, style: style)
    }
}

public extension View {
    func contentShape<S: Shape>(_ shape: S) -> ContentShapeView<Self, S> {
        recordQuillUIFallback(
            "contentShape",
            message: "contentShape is preserved as hit-testing shape metadata on Linux."
        )
        return ContentShapeView(content: self, shape: shape)
    }

    func allowsHitTesting(_ enabled: Bool) -> AllowsHitTestingView<Self> {
        recordQuillUIFallback(
            "allowsHitTesting",
            message: "allowsHitTesting is preserved as interaction metadata on Linux."
        )
        return AllowsHitTestingView(content: self, enabled: enabled)
    }

    func onHover(perform action: @escaping (Bool) -> Void) -> OnHoverView<Self> {
        recordQuillUIFallback(
            "onHover",
            message: "onHover is preserved as hover handler metadata on Linux."
        )
        return OnHoverView(content: self, action: action)
    }

    func transition(_ transition: AnyTransition) -> TransitionView<Self> {
        recordQuillUIFallback(
            "transition",
            message: "transition is preserved as transition metadata on Linux."
        )
        return TransitionView(content: self, transition: transition)
    }

    func symbolEffect<Value: Equatable>(
        _ effect: SymbolEffect,
        options: SymbolEffectOptions = .default,
        value: Value
    ) -> SymbolEffectView<Self, Value> {
        recordQuillUIFallback(
            "symbolEffect",
            message: "symbolEffect is preserved as symbol animation metadata on Linux."
        )
        return SymbolEffectView(
            content: self,
            effect: effect,
            options: options,
            value: value
        )
    }

    func offset(_ size: CGSize) -> OffsetView<Self> {
        offset(x: size.width, y: size.height)
    }

    func padding(_ amount: CGFloat) -> PaddedView<Self> {
        padding(Int(amount))
    }

    func padding(_ edges: Edge.Set, _ amount: Double) -> PaddedView<Self> {
        padding(edges, Int(amount))
    }

    func padding(_ edges: Edge.Set, _ amount: CGFloat) -> PaddedView<Self> {
        padding(edges, Int(amount))
    }

    func listRowInsets(_ insets: EdgeInsets?) -> ListRowInsetsView<Self> {
        recordQuillUIFallback(
            "listRowInsets",
            message: "listRowInsets is preserved as list row layout metadata on Linux."
        )
        return ListRowInsetsView(content: self, insets: insets)
    }

    func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> ListRowSeparatorView<Self> {
        recordQuillUIFallback(
            "listRowSeparator",
            message: "listRowSeparator is preserved as list row separator metadata on Linux."
        )
        return ListRowSeparatorView(content: self, visibility: visibility, edges: edges)
    }

    func focused<Value>(_ binding: Binding<Value>) -> FocusBindingView<Self, Value> {
        recordQuillUIFallback(
            "focused",
            message: "Focus bindings are preserved as focus metadata on Linux."
        )
        return FocusBindingView(content: self, binding: binding)
    }

    func focused<Value: Equatable>(_ binding: Binding<Value?>, equals value: Value) -> FocusEqualsBindingView<Self, Value> {
        recordQuillUIFallback(
            "focused",
            message: "Optional focus bindings are preserved as focus-equals metadata on Linux."
        )
        return FocusEqualsBindingView(content: self, binding: binding, value: value)
    }

    func textSelection(_ selection: TextSelectability = .enabled) -> TextSelectionView<Self> {
        recordQuillUIFallback(
            "textSelection",
            message: "textSelection is preserved as selectable text metadata on Linux."
        )
        return TextSelectionView(content: self, selection: selection)
    }

    func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self> {
        recordQuillUIFallback(
            "accessibilityLabel",
            message: "View accessibility labels are propagated to GTK accessibility metadata on Linux."
        )
        return AccessibilityLabelView(content: self, label: label)
    }

    func accessibilityLabel<T>(_ label: T) -> AccessibilityLabelView<Self> {
        accessibilityLabel(String(describing: label))
    }

    func accessibilityValue(_ value: String) -> AccessibilityValueView<Self> {
        recordQuillUIFallback(
            "accessibilityValue",
            message: "View accessibility values are propagated to GTK accessibility metadata on Linux."
        )
        return AccessibilityValueView(content: self, value: value)
    }

    func accessibilityValue<T>(_ value: T) -> AccessibilityValueView<Self> {
        accessibilityValue(String(describing: value))
    }

    func accessibilityElement(children: AccessibilityChildBehavior) -> AccessibilityElementView<Self> {
        recordQuillUIFallback(
            "accessibilityElement(children:)",
            message: "View accessibility child behavior is preserved for GTK accessibility rendering on Linux."
        )
        return AccessibilityElementView(content: self, children: children)
    }

    func minimumScaleFactor(_ factor: Double) -> MinimumScaleFactorView<Self> {
        recordQuillUIFallback(
            "minimumScaleFactor",
            message: "minimumScaleFactor is preserved as layout metadata on Linux."
        )
        return MinimumScaleFactorView(content: self, factor: factor)
    }

    func lineLimit(_ number: Int?, reservesSpace: Bool) -> some View {
        lineLimit(number)
    }

    @_disfavoredOverload
    @ViewBuilder
    func foregroundStyle<Style>(_ style: Style) -> some View {
        if let color = style as? Color {
            foregroundColor(color)
        } else if let gradient = style as? LinearGradient {
            foregroundColor(gradient.gradient.quillAverageColor)
        } else if let gradient = style as? RadialGradient {
            foregroundColor(gradient.gradient.quillAverageColor)
        } else {
            recordQuillUIFallbackView(
                self,
                operation: "foregroundStyle",
                message: "Unknown foregroundStyle values currently render through the original view on Linux."
            )
        }
    }

    func foregroundStyle(_ style: LinearGradient) -> some View {
        foregroundColor(style.gradient.quillAverageColor)
    }

    func foregroundStyle(_ style: RadialGradient) -> some View {
        foregroundColor(style.gradient.quillAverageColor)
    }

    @_disfavoredOverload
    func foregroundStyle(_ primary: Color, _ secondary: Color) -> some View {
        foregroundColor(primary)
    }

    func symbolRenderingMode(_ mode: Image.SymbolRenderingMode?) -> SymbolRenderingModeView<Self> {
        recordQuillUIFallback(
            "symbolRenderingMode",
            message: "View symbolRenderingMode is preserved as symbol rendering metadata on Linux."
        )
        return SymbolRenderingModeView(content: self, mode: mode)
    }

    func onMove(perform action: ((IndexSet, Int) -> Void)?) -> Self {
        recordQuillUIFallback(
            "onMove",
            message: "onMove is currently a source-compatibility fallback on Linux."
        )
        return self
    }

    func gesture<Gesture>(_ gesture: Gesture) -> GestureView<Self, Gesture> {
        recordQuillUIFallback(
            "gesture",
            message: "gesture is preserved as gesture metadata on Linux."
        )
        return GestureView(content: self, gesture: gesture)
    }

    // The View-mask is the FAVORED functional overload (a View covers Shapes
    // too). It must win over QuillSwiftUICompatibility's inert
    // `mask(alignment:_:)` fallback — leaving BOTH disfavored made
    // `mask(Text(…))` ambiguous (two equally-disfavored View overloads). The
    // Shape-mask below is disfavored instead, so `mask(Rectangle())` also binds
    // here (ViewMaskView) rather than tying with the Shape overload.
    func mask<Mask: View>(_ mask: Mask) -> ViewMaskView<Self, Mask> {
        recordQuillUIFallback(
            "mask",
            message: "View masks are preserved as mask metadata on Linux."
        )
        return ViewMaskView(content: self, mask: mask)
    }

    @_disfavoredOverload
    func mask<S: Shape>(_ shape: S) -> ClipShapeView<Self, S> {
        recordQuillUIFallback(
            "mask",
            message: "Shape masks are approximated with clipShape on Linux."
        )
        return clipShape(shape)
    }

    func onDrop(
        of supportedContentTypes: [UTType],
        isTargeted: Binding<Bool>? = nil,
        perform action: @escaping ([NSItemProvider]) -> Bool
    ) -> DropDestinationView<Self> {
        dropDestination(for: URL.self) { urls, _ in
            let providers = urls
                .filter { url in
                    supportedContentTypes.isEmpty || supportedContentTypes.contains { $0.accepts(url: url) }
                }
                .map(NSItemProvider.init(fileURL:))
            guard !providers.isEmpty else { return false }
            return action(providers)
        } isTargeted: { targeted in
            isTargeted?.wrappedValue = targeted
        }
    }

    func contextMenu(_ contextMenu: ContextMenu) -> ContextMenuView<Self> {
        self.contextMenu {
            contextMenu.menuElements
        }
    }

    // `matchedGeometryEffect` is canonical in QuillSwiftUICompatibility
    // (DesignSystemSurfaceCompat.swift) — main canonicalized it there, so
    // no copy here. `buttonStyle<S: ButtonStyle>` likewise lives in
    // QuillSwiftUICompatibility (SolderScopeChrome.swift) alongside the
    // ButtonStyle protocol; custom styles still fall back to the plain GTK
    // chrome there.


    func focusedSceneValue<K: FocusedValueKey>(
        _ keyPath: WritableKeyPath<FocusedValues, K.Value?>,
        _ value: K.Value
    ) -> FocusedValueView<Self, K> {
        focusedValue(keyPath, value)
    }

    func focusedSceneValue<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>,
        _ value: Value
    ) -> Self {
        recordQuillUIFallback(
            "focusedSceneValue",
            message: "focusedSceneValue is currently a source-compatibility fallback on Linux."
        )
        return self
    }

    func formStyle(_ style: GroupedFormStyle) -> BackgroundView<PaddedView<Self>, Color> {
        recordQuillUIFallback(
            "formStyle",
            message: "GroupedFormStyle is approximated with grouped padding and background on Linux."
        )
        return padding(8)
            .background(Color.gray5Custom)
    }

}

// @MainActor: witnesses are members of main-actor-isolated View types
// (whole-protocol View isolation, Apple shape); walkers are isolated too.
@MainActor
private protocol QuillButtonRepresentable {
    var quillButtonLabel: String { get }
    var quillButtonAction: () -> Void { get }
}

extension Button: QuillButtonRepresentable {
    fileprivate var quillButtonLabel: String { quillTextLabel(from: label) }
    fileprivate var quillButtonAction: () -> Void { action }
}

// @MainActor: witnesses are members of main-actor-isolated View types
// (whole-protocol View isolation, Apple shape); walkers are isolated too.
@MainActor
private protocol QuillDisabledRepresentable {
    var quillDisabledContent: any View { get }
    var quillIsDisabled: Bool { get }
}

extension DisabledView: QuillDisabledRepresentable {
    fileprivate var quillDisabledContent: any View { content }
    fileprivate var quillIsDisabled: Bool { isDisabled }
}

// @MainActor: witnesses are members of main-actor-isolated View types
// (whole-protocol View isolation, Apple shape); walkers are isolated too.
@MainActor
private protocol QuillKeyboardShortcutRepresentable {
    var quillShortcutContent: any View { get }
    var quillShortcut: KeyboardShortcut { get }
}

extension KeyboardShortcutView: QuillKeyboardShortcutRepresentable {
    fileprivate var quillShortcutContent: any View { content }
    fileprivate var quillShortcut: KeyboardShortcut { shortcut }
}

// @MainActor: witnesses are members of main-actor-isolated View types
// (whole-protocol View isolation, Apple shape); walkers are isolated too.
@MainActor
private protocol QuillWrappedViewRepresentable {
    var quillWrappedContent: any View { get }
}

@MainActor
private protocol QuillAccessibilityLabelRepresentable: QuillWrappedViewRepresentable {
    var quillAccessibilityLabel: String { get }
}

extension AccessibilityLabelView: QuillAccessibilityLabelRepresentable {
    fileprivate var quillWrappedContent: any View { content }
    fileprivate var quillAccessibilityLabel: String { label }
}

extension AccessibilityValueView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension AccessibilityElementView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ForegroundColorView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension BackgroundView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FontModifiedView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension BorderView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension LineLimitView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension TruncationModeView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension LineSpacingView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension MultilineTextAlignmentView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension BoldView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ItalicView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FontWeightView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension UnderlineView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension StrikethroughView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension TextCaseView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension PaddedView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FrameView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension PositionView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension LayoutPriorityView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FixedSizeView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension SymbolRenderingModeView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ListRowInsetsView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ListRowSeparatorView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ScrollIndicatorsView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ScrollContentBackgroundView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ContentShapeView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension AllowsHitTestingView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension GestureView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension TransitionView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension SymbolEffectView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ViewMaskView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension OnHoverView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FocusEffectDisabledView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FocusedView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FocusedEqualsView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FocusBindingView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension FocusEqualsBindingView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension EdgesIgnoringSafeAreaView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension IgnoresSafeAreaView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension TextSelectionView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension TextContentTypeView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension AutocorrectionDisabledView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension KeyboardTypeView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension AutocapitalizationView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension OverlayView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension OpacityView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension OffsetView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension ScaleEffectView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension AnimatedView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

extension HelpView: QuillWrappedViewRepresentable {
    fileprivate var quillWrappedContent: any View { content }
}

@_spi(QuillTesting)
@MainActor
public func quillTextLabel(from view: any View) -> String {
    if let text = view as? Text {
        return text.content
    }

    if let label = view as? any AnyLabelView {
        return label.title
    }

    if let image = view as? Image {
        return quillSystemImageName(from: image)
    }

    if let multi = view as? MultiChildView {
        for child in multi.children {
            let label = quillTextLabel(from: child)
            if !label.isEmpty {
                return label
            }
        }
    }

    if let accessibility = view as? any QuillAccessibilityLabelRepresentable {
        let contentLabel = quillTextLabel(from: accessibility.quillWrappedContent)
        return contentLabel.isEmpty ? accessibility.quillAccessibilityLabel : contentLabel
    }

    if let wrapped = view as? any QuillWrappedViewRepresentable {
        return quillTextLabel(from: wrapped.quillWrappedContent)
    }

    return ""
}

@_spi(QuillTesting)
@MainActor
public func quillSystemImageName(from view: any View) -> String {
    guard let image = view as? Image else {
        return "circle"
    }

    switch image.source {
    case .systemName(let name), .materialSymbol(let name):
        return QuillSystemSymbol.compatibleName(name)
    case .filePath:
        return "photo"
    }
}

@_spi(QuillTesting)
@MainActor
public func quillMenuElements(from view: any View) -> [MenuElement] {
    if let button = view as? any QuillButtonRepresentable {
        return [.item(label: button.quillButtonLabel, action: button.quillButtonAction)]
    }

    if let disabled = view as? any QuillDisabledRepresentable {
        return quillMenuElements(from: disabled.quillDisabledContent)
            .map { quillMenuElement($0, disabled: disabled.quillIsDisabled) }
    }

    if let shortcut = view as? any QuillKeyboardShortcutRepresentable {
        return quillMenuElements(from: shortcut.quillShortcutContent)
    }

    if let wrapped = view as? any QuillWrappedViewRepresentable {
        return quillMenuElements(from: wrapped.quillWrappedContent)
    }

    if let multi = view as? MultiChildView {
        return multi.children.flatMap(quillMenuElements)
    }

    return []
}

@MainActor
private func quillConfirmationDialogButtons(from view: any View) -> [AlertButton] {
    quillMenuElements(from: view).flatMap(quillAlertButtons)
}

private func quillAlertButtons(from element: MenuElement) -> [AlertButton] {
    switch element {
    case .item(let label, let action):
        return [AlertButton(label, action: action)]
    case .divider:
        return []
    case .submenu(_, let children):
        return children.flatMap(quillAlertButtons)
    }
}

private func quillMenuElement(_ element: MenuElement, disabled: Bool) -> MenuElement {
    guard disabled else { return element }
    switch element {
    case .item(let label, _):
        return .item(label: label, action: {})
    case .divider:
        return .divider
    case .submenu(let label, let children):
        return .submenu(label: label, children: children.map { quillMenuElement($0, disabled: true) })
    }
}

@_spi(QuillTesting)
@MainActor
public func quillCommandMenuItems(from view: any View) -> [CommandMenuItem] {
    if let button = view as? any QuillButtonRepresentable {
        return [CommandMenuItem(button.quillButtonLabel, action: button.quillButtonAction)]
    }

    if let shortcut = view as? any QuillKeyboardShortcutRepresentable {
        return quillCommandMenuItems(from: shortcut.quillShortcutContent)
            .map { quillCommandMenuItem($0, shortcut: shortcut.quillShortcut) }
    }

    if let disabled = view as? any QuillDisabledRepresentable {
        return quillCommandMenuItems(from: disabled.quillDisabledContent)
            .map { quillCommandMenuItem($0, disabled: disabled.quillIsDisabled) }
    }

    if let wrapped = view as? any QuillWrappedViewRepresentable {
        return quillCommandMenuItems(from: wrapped.quillWrappedContent)
    }

    if let multi = view as? MultiChildView {
        return multi.children.flatMap(quillCommandMenuItems)
    }

    return []
}

private func quillCommandMenuItem(_ item: CommandMenuItem, shortcut: KeyboardShortcut) -> CommandMenuItem {
    CommandMenuItem(
        item.label,
        shortcut: item.shortcut ?? shortcut,
        action: item.action
    )
    .disabled(item.isDisabled)
}

private func quillCommandMenuItem(_ item: CommandMenuItem, disabled: Bool) -> CommandMenuItem {
    item.disabled(disabled || item.isDisabled)
}

@_spi(QuillTesting)
@MainActor
public func quillPickerOptions(from view: any View) -> [(label: String, tag: AnyHashable)] {
    if let tagged = view as? AnyTagView {
        let label = quillTextLabel(from: tagged.anyTagContent)
        return [(label.isEmpty ? String(describing: tagged.anyTagValue.base) : label, tagged.anyTagValue)]
    }

    if let wrapped = view as? any QuillWrappedViewRepresentable {
        return quillPickerOptions(from: wrapped.quillWrappedContent)
    }

    if let multi = view as? MultiChildView {
        return multi.children.flatMap(quillPickerOptions)
    }

    return []
}
#endif
