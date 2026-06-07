import Foundation
#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI
import QuillKit
import QuillFoundation
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

public final class NSItemProvider: @unchecked Sendable {
    private enum Representation {
        case data(Data, UTType)
        case file(URL, UTType?)
    }

    private let representations: [Representation]

    public init() {
        self.representations = []
    }

    public init(fileURL: URL) {
        self.representations = [.file(fileURL, UTType.type(for: fileURL))]
    }

    public convenience init(contentsOf url: URL) {
        self.init(fileURL: url)
    }

    public init(data: Data, type: UTType) {
        self.representations = [.data(data, type)]
    }

    public func loadDataRepresentation(
        for contentType: UTType,
        completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        for representation in representations {
            switch representation {
            case .data(let data, let type) where type.conforms(to: contentType):
                completionHandler(data, nil)
                return nil
            case .file(let url, let type) where type?.conforms(to: contentType) == true || contentType.accepts(url: url):
                do {
                    completionHandler(try Data(contentsOf: url), nil)
                } catch {
                    completionHandler(nil, error)
                }
                return nil
            default:
                continue
            }
        }
        completionHandler(nil, QuillCompatibilityError.representationUnavailable(contentType.identifier))
        return nil
    }
}

public enum QuillCompatibilityError: Error, LocalizedError, Equatable {
    case representationUnavailable(String)
    case fileSelectionUnavailable
    case unsupportedFileSelection(URL, [UTType])

    public var errorDescription: String? {
        switch self {
        case .representationUnavailable(let identifier):
            return "No data representation is available for \(identifier)."
        case .fileSelectionUnavailable:
            return "No file selection provider is available."
        case .unsupportedFileSelection(let url, let allowedTypes):
            let allowed = allowedTypes.map(\.identifier).joined(separator: ", ")
            return "\(url.path) is not one of the allowed file types: \(allowed)."
        }
    }
}

public enum QuillFileImporter {
    private static let environmentKey = "QUILLUI_FILE_IMPORTER_SELECTION"
    private static let testSelection = TestSelection()

    public static func setTestSelection(_ url: URL?) {
        testSelection.set(url)
    }

    public static func selectURL(allowedContentTypes: [UTType]) -> Result<URL, Error> {
        if let testSelectionURL = testSelection.url {
            return validate(testSelectionURL, allowedContentTypes: allowedContentTypes)
        }

        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey],
           !environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return validate(URL(fileURLWithPath: environmentValue), allowedContentTypes: allowedContentTypes)
        }

        for command in fileSelectionCommands {
            if let url = run(command: command) {
                return validate(url, allowedContentTypes: allowedContentTypes)
            }
        }

        return .failure(QuillCompatibilityError.fileSelectionUnavailable)
    }

    private final class TestSelection: @unchecked Sendable {
        private let lock = NSLock()
        private var selectedURL: URL?

        var url: URL? {
            lock.withLock { selectedURL }
        }

        func set(_ url: URL?) {
            lock.withLock {
                selectedURL = url
            }
        }
    }

    private static var fileSelectionCommands: [[String]] {
        [
            ["zenity", "--file-selection"],
            ["kdialog", "--getopenfilename"],
            ["yad", "--file-selection"]
        ]
    }

    private static func validate(_ url: URL, allowedContentTypes: [UTType]) -> Result<URL, Error> {
        guard allowedContentTypes.isEmpty || allowedContentTypes.contains(where: { $0.accepts(url: url) }) else {
            return .failure(QuillCompatibilityError.unsupportedFileSelection(url, allowedContentTypes))
        }
        return .success(url)
    }

    private static func run(command: [String]) -> URL? {
        guard let executable = command.first,
              let executableURL = executableURL(named: executable) else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = Array(command.dropFirst())
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { return nil }
        return URL(fileURLWithPath: output)
    }

    private static func executableURL(named name: String) -> URL? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin")
            .split(separator: ":")
            .map(String.init)
        for path in paths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

public struct Material: Sendable {
    public init() {}
    public static let ultraThinMaterial = Material()
    public static let thinMaterial = Material()
    public static let regularMaterial = Material()
    public static let thickMaterial = Material()
    public static let ultraThickMaterial = Material()
}

@propertyWrapper
public struct Namespace: Sendable {
    public struct ID: Hashable, Sendable {
        private let rawValue = UUID()

        public init() {}
    }

    private var id: ID

    public init() {
        self.id = ID()
    }

    public var wrappedValue: ID {
        get { id }
        set { id = newValue }
    }
}

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

public struct AnyTransition: Sendable, CustomStringConvertible {
    public let quillDescription: String

    public init() {
        self.quillDescription = "identity"
    }

    private init(quillDescription: String) {
        self.quillDescription = quillDescription
    }

    public static let opacity = AnyTransition(quillDescription: "opacity")
    public static let slide = AnyTransition(quillDescription: "slide")

    public static func scale(scale: Double = 1.0, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(quillDescription: "scale(scale: \(scale), anchor: \(anchor))")
    }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(
            quillDescription: "asymmetric(insertion: \(insertion.quillDescription), removal: \(removal.quillDescription))"
        )
    }

    public init(_ transition: AnyTransition) {
        self = transition
    }

    public func combined(with transition: AnyTransition) -> AnyTransition {
        AnyTransition(quillDescription: "combined(\(quillDescription), \(transition.quillDescription))")
    }

    public var description: String { quillDescription }
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

public struct AngularGradient {
    public var gradient: Gradient
    public var center: UnitPoint
    public var startAngle: Angle
    public var endAngle: Angle

    public init(
        gradient: Gradient,
        center: UnitPoint,
        startAngle: Angle = .zero,
        endAngle: Angle = .zero
    ) {
        self.gradient = gradient
        self.center = center
        self.startAngle = startAngle
        self.endAngle = endAngle
    }

    public init(colors: [Color], center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .zero) {
        self.init(gradient: Gradient(colors: colors), center: center, startAngle: startAngle, endAngle: endAngle)
    }

    public func opacity(_ opacity: Double) -> Color {
        gradient.quillAverageColor.opacity(opacity)
    }
}

#if !os(macOS) && !os(iOS) && !os(visionOS)
public struct ButtonStyleConfiguration {
    public var label: Text
    public var isPressed: Bool

    public init(label: Text, isPressed: Bool) {
        self.label = label
        self.isPressed = isPressed
    }
}

public protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}

public struct PlainButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> Text {
        configuration.label
    }
}
#endif

#if !os(macOS) && !os(iOS) && !os(visionOS)
public typealias ToolbarItemGroup<Content: View> = ToolbarItem<Content>

public extension ToolbarItemPlacement {
    static var automatic: ToolbarItemPlacement { .primaryAction }
    static var navigation: ToolbarItemPlacement { .leading }
    static var navigationBarTrailing: ToolbarItemPlacement { .trailing }
    static var topBarLeading: ToolbarItemPlacement { .leading }
}

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

    func repeatForever(autoreverses: Bool = true) -> Animation {
        recordQuillUIFallback(
            "Animation.repeatForever",
            message: "Animation.repeatForever is currently a source-compatibility no-op on Linux; the animation will run once instead of looping."
        )
        return self
    }

    func delay(_ delay: Double) -> Animation {
        recordQuillUIFallback(
            "Animation.delay",
            message: "Animation.delay is currently a source-compatibility no-op on Linux; the requested delay will not be applied."
        )
        return self
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

public extension HStack {
    init(
        alignment: VerticalAlignment = .center,
        spacing: Double?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            spacing: spacing.map { Int($0) } ?? stackDefaultSpacing,
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
            spacing: spacing.map { Int($0) } ?? stackDefaultSpacing,
            content: content
        )
    }
}

public extension CommandGroupPlacement {
    static var appSettings: CommandGroupPlacement { .newItem }
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

public extension WindowGroup {
    func defaultSize(width: Double, height: Double) -> WindowGroup<Content> {
        defaultWindowSize(width: width, height: height)
    }
}

public extension CommandMenuBuilder {
    static func buildExpression<Label: View>(_ button: Button<Label>) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                quillTextLabel(from: button.label),
                action: button.action
            )
        ]
    }

    static func buildExpression<Label: View>(_ shortcutView: KeyboardShortcutView<Button<Label>>) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                quillTextLabel(from: shortcutView.content.label),
                shortcut: shortcutView.shortcut,
                action: shortcutView.content.action
            )
        ]
    }

    static func buildExpression<Content: View>(_ disabledView: DisabledView<Content>) -> [CommandMenuItem] {
        quillCommandMenuItems(from: disabledView.content)
            .map { quillCommandMenuItem($0, disabled: disabledView.isDisabled) }
    }

    static func buildExpression<Content: View>(_ view: Content) -> [CommandMenuItem] {
        quillCommandMenuItems(from: view)
    }
}

public extension Menu {
    init<LabelContent: View>(
        @MenuBuilder content: () -> [MenuElement],
        @ViewBuilder label: () -> LabelContent
    ) {
        self.init(quillTextLabel(from: label()), content: content)
    }
}

public extension MenuBuilder {
    static func buildExpression(_ elements: [MenuElement]) -> [MenuElement] {
        elements
    }

    static func buildExpression<Label: View>(_ button: Button<Label>) -> [MenuElement] {
        [.item(label: quillTextLabel(from: button.label), action: button.action)]
    }

    static func buildExpression<Label: View>(_ shortcutView: KeyboardShortcutView<Button<Label>>) -> [MenuElement] {
        [.item(label: quillTextLabel(from: shortcutView.content.label), action: shortcutView.content.action)]
    }

    static func buildExpression<Content: View>(_ disabledView: DisabledView<Content>) -> [MenuElement] {
        quillMenuElements(from: disabledView.content)
            .map { quillMenuElement($0, disabled: disabledView.isDisabled) }
    }

    static func buildExpression(_ divider: Divider) -> [MenuElement] {
        [.divider]
    }

    static func buildExpression<Content: View>(_ view: Content) -> [MenuElement] {
        quillMenuElements(from: view)
    }

}

public extension Label {
    init<Title: View, Icon: View>(
        @ViewBuilder title: () -> Title,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(quillTextLabel(from: title()), systemImage: quillSystemImageName(from: icon()))
    }
}

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

public struct RoundedBorderTextFieldStyle: Sendable {
    public init() {}
}

public struct PlainTextFieldStyle: Sendable {
    public init() {}
}

public struct FormStyleType: Sendable {
    public init() {}
    public static let grouped = FormStyleType()
}

public struct GroupedFormStyle: Sendable {
    public init() {}
}

public struct TextContentType: Hashable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let URL = TextContentType("URL")
}

public struct KeyboardType: Hashable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let URL = KeyboardType("URL")
}

public struct TextInputAutocapitalization: Hashable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let never = TextInputAutocapitalization("never")
    public static let none = TextInputAutocapitalization("none")
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
    public static func == (lhs: Image, rhs: Image) -> Bool {
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

public extension State {
    init(initialValue: Value) {
        self.init(wrappedValue: initialValue)
    }
}

public extension WindowGroup {
    init(@ViewBuilder content: () -> Content) {
        self.init("Quill", content: content)
    }
}

public struct LabeledContent<Content: View>: View {
    public var title: String
    public var content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            content
        }
    }
}

public struct TableColumn<RowValue, Content: View>: View {
    public var title: String
    private var content: (RowValue) -> Content

    public init(_ title: String, @ViewBuilder content: @escaping (RowValue) -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        Text(title)
    }

    public func width(min: Double? = nil, max: Double? = nil) -> Self {
        self
    }
}

public struct AnyTableColumn<RowValue>: View {
    public var title: String

    public init<Content: View>(_ column: TableColumn<RowValue, Content>) {
        self.title = column.title
    }

    public var body: some View {
        Text(title)
    }
}

@resultBuilder
public enum TableColumnBuilder<RowValue> {
    public static func buildBlock(_ columns: [AnyTableColumn<RowValue>]...) -> [AnyTableColumn<RowValue>] {
        columns.flatMap { $0 }
    }

    public static func buildExpression<Content: View>(
        _ column: TableColumn<RowValue, Content>
    ) -> [AnyTableColumn<RowValue>] {
        [AnyTableColumn(column)]
    }
}

public struct Table<RowValue>: View {
    public var rows: [RowValue]
    public var columns: [AnyTableColumn<RowValue>]

    public init(_ rows: [RowValue], @TableColumnBuilder<RowValue> columns: () -> [AnyTableColumn<RowValue>]) {
        self.rows = rows
        self.columns = columns()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                column
            }
        }
    }
}

public enum ScrollIndicatorVisibility: Sendable {
    case automatic
    case visible
    case hidden
    case never
}

public struct AccessibilityChildBehavior: Hashable, Sendable {
    private let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let ignore = AccessibilityChildBehavior("ignore")
    public static let combine = AccessibilityChildBehavior("combine")
    public static let contain = AccessibilityChildBehavior("contain")
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

// ListRowInsetsView / ListRowSeparatorView moved to SwiftOpenUI
// (Modifiers/QuillUICompatModifiers.swift) so vendored source can use them.

public struct ScrollIndicatorsView<Content: View>: View {
    public let content: Content
    public let visibility: ScrollIndicatorVisibility

    public init(content: Content, visibility: ScrollIndicatorVisibility) {
        self.content = content
        self.visibility = visibility
    }

    public var body: some View { content }
}

public struct ScrollContentBackgroundView<Content: View>: View {
    public let content: Content
    public let visibility: Visibility

    public init(content: Content, visibility: Visibility) {
        self.content = content
        self.visibility = visibility
    }

    public var body: some View { content }
}

// ContentShapeView / AllowsHitTestingView moved to SwiftOpenUI
// (Modifiers/QuillUICompatModifiers.swift) so vendored source can use them.

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

public struct ViewMaskView<Content: View, MaskContent: View>: View {
    public let content: Content
    public let mask: MaskContent

    public init(content: Content, mask: MaskContent) {
        self.content = content
        self.mask = mask
    }

    public var body: some View { content }
}

// OnHoverView moved to SwiftOpenUI (Modifiers/QuillUICompatModifiers.swift).

public struct FocusEffectDisabledView<Content: View>: View {
    public let content: Content
    public let disabled: Bool

    public init(content: Content, disabled: Bool) {
        self.content = content
        self.disabled = disabled
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

public struct EdgesIgnoringSafeAreaView<Content: View>: View {
    public let content: Content
    public let edges: Edge.Set

    public init(content: Content, edges: Edge.Set) {
        self.content = content
        self.edges = edges
    }

    public var body: some View { content }
}

public struct IgnoresSafeAreaView<Content: View>: View {
    public let content: Content
    public let edges: Edge.Set

    public init(content: Content, edges: Edge.Set) {
        self.content = content
        self.edges = edges
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

public struct TextContentTypeView<Content: View>: View {
    public let content: Content
    public let contentType: TextContentType?

    public init(content: Content, contentType: TextContentType?) {
        self.content = content
        self.contentType = contentType
    }

    public var body: some View { content }
}

public struct AutocorrectionDisabledView<Content: View>: View {
    public let content: Content
    public let disabled: Bool?

    public init(content: Content, disabled: Bool?) {
        self.content = content
        self.disabled = disabled
    }

    public var body: some View { content }
}

public struct KeyboardTypeView<Content: View>: View {
    public let content: Content
    public let keyboardType: KeyboardType

    public init(content: Content, keyboardType: KeyboardType) {
        self.content = content
        self.keyboardType = keyboardType
    }

    public var body: some View { content }
}

public struct AutocapitalizationView<Content: View>: View {
    public let content: Content
    public let autocapitalization: TextInputAutocapitalization

    public init(content: Content, autocapitalization: TextInputAutocapitalization) {
        self.content = content
        self.autocapitalization = autocapitalization
    }

    public var body: some View { content }
}

public struct DragGesture: Sendable {
    public struct Value: Sendable {
        public var translation: CGSize

        public init(translation: CGSize = .zero) {
            self.translation = translation
        }
    }

    private var onChangedAction: (@Sendable (Value) -> Void)?
    private var onEndedAction: (@Sendable (Value) -> Void)?

    public init() {}

    public func onChanged(_ action: @escaping @Sendable (Value) -> Void) -> DragGesture {
        var copy = self
        copy.onChangedAction = action
        return copy
    }

    public func onEnded(_ action: @escaping @Sendable (Value) -> Void) -> DragGesture {
        var copy = self
        copy.onEndedAction = action
        return copy
    }
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

public extension URL {
    func startAccessingSecurityScopedResource() -> Bool { true }
    func stopAccessingSecurityScopedResource() {}
}

public extension Shape {
    func fill(_ material: Material) -> FilledShape<Self> {
        fill(Color.white.opacity(0.92))
    }

    func strokeBorder(style: StrokeStyle) -> StrokedShape<Self> {
        strokeBorder(.primary, style: style)
    }
}

public extension View {
    func offset(_ size: CGSize) -> OffsetView<Self> {
        offset(x: size.width, y: size.height)
    }

    func padding(_ insets: EdgeInsets) -> PaddedView<Self> {
        padding(
            top: Int(insets.top),
            bottom: Int(insets.bottom),
            leading: Int(insets.leading),
            trailing: Int(insets.trailing)
        )
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

    func minimumScaleFactor(_ factor: Double) -> MinimumScaleFactorView<Self> {
        recordQuillUIFallback(
            "minimumScaleFactor",
            message: "minimumScaleFactor is preserved as layout metadata on Linux."
        )
        return MinimumScaleFactorView(content: self, factor: factor)
    }

    func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self> {
        recordQuillUIFallback(
            "accessibilityLabel",
            message: "View accessibility labels are propagated to GTK accessibility metadata on Linux."
        )
        return AccessibilityLabelView(content: self, label: label)
    }

    func accessibilityValue(_ value: String) -> AccessibilityValueView<Self> {
        recordQuillUIFallback(
            "accessibilityValue",
            message: "View accessibility values are propagated to GTK accessibility metadata on Linux."
        )
        return AccessibilityValueView(content: self, value: value)
    }

    func accessibilityElement(children: AccessibilityChildBehavior) -> AccessibilityElementView<Self> {
        recordQuillUIFallback(
            "accessibilityElement(children:)",
            message: "View accessibility child behavior is preserved for GTK accessibility rendering on Linux."
        )
        return AccessibilityElementView(content: self, children: children)
    }

    func lineLimit(_ number: Int?, reservesSpace: Bool) -> some View {
        lineLimit(number)
    }

    func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> OnChangeView<Self, Bool> {
        onChange(of: isPresented.wrappedValue) { presented in
            guard presented else { return }
            isPresented.wrappedValue = false
            onCompletion(QuillFileImporter.selectURL(allowedContentTypes: allowedContentTypes))
        }
    }

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

    func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> ScrollIndicatorsView<Self> {
        recordQuillUIFallback(
            "scrollIndicators",
            message: "scrollIndicators is preserved as scroll view chrome metadata on Linux."
        )
        return ScrollIndicatorsView(content: self, visibility: visibility)
    }

    func scrollContentBackground(_ visibility: Visibility) -> ScrollContentBackgroundView<Self> {
        recordQuillUIFallback(
            "scrollContentBackground",
            message: "scrollContentBackground is preserved as scroll content background metadata on Linux."
        )
        return ScrollContentBackgroundView(content: self, visibility: visibility)
    }

    func focusEffectDisabled(_ disabled: Bool = true) -> FocusEffectDisabledView<Self> {
        recordQuillUIFallback(
            "focusEffectDisabled",
            message: "focusEffectDisabled is preserved as focus-effect metadata on Linux."
        )
        return FocusEffectDisabledView(content: self, disabled: disabled)
    }

    func edgesIgnoringSafeArea(_ edges: Edge.Set) -> EdgesIgnoringSafeAreaView<Self> {
        recordQuillUIFallback(
            "edgesIgnoringSafeArea",
            message: "edgesIgnoringSafeArea is preserved as safe-area layout metadata on Linux."
        )
        return EdgesIgnoringSafeAreaView(content: self, edges: edges)
    }

    func ignoresSafeArea(_ edges: Edge.Set = .all) -> IgnoresSafeAreaView<Self> {
        recordQuillUIFallback(
            "ignoresSafeArea",
            message: "ignoresSafeArea is preserved as safe-area layout metadata on Linux."
        )
        return IgnoresSafeAreaView(content: self, edges: edges)
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

    func mask<Mask: View>(_ mask: Mask) -> ViewMaskView<Self, Mask> {
        recordQuillUIFallback(
            "mask",
            message: "View masks are preserved as mask metadata on Linux."
        )
        return ViewMaskView(content: self, mask: mask)
    }

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

    func transition(_ transition: AnyTransition) -> TransitionView<Self> {
        recordQuillUIFallback(
            "transition",
            message: "transition is preserved as transition metadata on Linux."
        )
        return TransitionView(content: self, transition: transition)
    }

    func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> AnimatedView<Self> {
        recordQuillUIFallback(
            "matchedGeometryEffect",
            message: "matchedGeometryEffect is approximated with value-driven animation on Linux."
        )
        return animation(.easeInOut(duration: 0.2), value: AnyHashable(id))
    }

    @ViewBuilder
    func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        recordQuillUIFallbackView(
            buttonStyle(ButtonStyleType.plain),
            operation: "buttonStyle",
            message: "Custom ButtonStyle values currently fall back to a plain GTK button style on Linux."
        )
    }

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

    func textFieldStyle(_ style: RoundedBorderTextFieldStyle) -> some View {
        textFieldStyle(TextFieldStyleType.roundedBorder)
    }

    func textFieldStyle(_ style: PlainTextFieldStyle) -> some View {
        textFieldStyle(TextFieldStyleType.plain)
    }

    func formStyle(_ style: FormStyleType) -> BackgroundView<PaddedView<Self>, Color> {
        recordQuillUIFallback(
            "formStyle",
            message: "formStyle is approximated with grouped padding and background on Linux."
        )
        return padding(8)
            .background(Color.gray5Custom)
    }

    func formStyle(_ style: GroupedFormStyle) -> BackgroundView<PaddedView<Self>, Color> {
        recordQuillUIFallback(
            "formStyle",
            message: "GroupedFormStyle is approximated with grouped padding and background on Linux."
        )
        return padding(8)
            .background(Color.gray5Custom)
    }

    func textContentType(_ contentType: TextContentType?) -> TextContentTypeView<Self> {
        recordQuillUIFallback(
            "textContentType",
            message: "textContentType is preserved as text-input metadata on Linux."
        )
        return TextContentTypeView(content: self, contentType: contentType)
    }

    func disableAutocorrection(_ disabled: Bool?) -> AutocorrectionDisabledView<Self> {
        recordQuillUIFallback(
            "disableAutocorrection",
            message: "disableAutocorrection is preserved as text-input metadata on Linux."
        )
        return AutocorrectionDisabledView(content: self, disabled: disabled)
    }

    func keyboardType(_ keyboardType: KeyboardType) -> KeyboardTypeView<Self> {
        recordQuillUIFallback(
            "keyboardType",
            message: "keyboardType is preserved as text-input metadata on Linux."
        )
        return KeyboardTypeView(content: self, keyboardType: keyboardType)
    }

    func autocapitalization(_ autocapitalization: TextInputAutocapitalization) -> AutocapitalizationView<Self> {
        recordQuillUIFallback(
            "autocapitalization",
            message: "autocapitalization is preserved as text-input metadata on Linux."
        )
        return AutocapitalizationView(content: self, autocapitalization: autocapitalization)
    }

    func confirmationDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> ConfirmationDialogView<Self> {
        confirmationDialog(
            title,
            isPresented: isPresented,
            titleVisibility: .automatic,
            actions: quillConfirmationDialogButtons(from: actions()),
            message: quillTextLabel(from: message())
        )
    }

}

public extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { indices.contains($0) ? self[$0] : nil }
        for index in source.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
        let insertion = Swift.max(0, Swift.min(destination, count))
        insert(contentsOf: moving, at: insertion)
    }
}

public extension AnyTransition {
    static var scale: AnyTransition {
        .scale()
    }
}

public extension Gradient {
    var quillAverageColor: Color {
        guard !stops.isEmpty else { return .primary }
        let count = Double(stops.count)
        let red = stops.reduce(0.0) { $0 + $1.color.red } / count
        let green = stops.reduce(0.0) { $0 + $1.color.green } / count
        let blue = stops.reduce(0.0) { $0 + $1.color.blue } / count
        let alpha = stops.reduce(0.0) { $0 + $1.color.alpha } / count
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

private protocol QuillButtonRepresentable {
    var quillButtonLabel: String { get }
    var quillButtonAction: () -> Void { get }
}

extension Button: QuillButtonRepresentable {
    fileprivate var quillButtonLabel: String { quillTextLabel(from: label) }
    fileprivate var quillButtonAction: () -> Void { action }
}

private protocol QuillDisabledRepresentable {
    var quillDisabledContent: any View { get }
    var quillIsDisabled: Bool { get }
}

extension DisabledView: QuillDisabledRepresentable {
    fileprivate var quillDisabledContent: any View { content }
    fileprivate var quillIsDisabled: Bool { isDisabled }
}

private protocol QuillKeyboardShortcutRepresentable {
    var quillShortcutContent: any View { get }
    var quillShortcut: KeyboardShortcut { get }
}

extension KeyboardShortcutView: QuillKeyboardShortcutRepresentable {
    fileprivate var quillShortcutContent: any View { content }
    fileprivate var quillShortcut: KeyboardShortcut { shortcut }
}

private protocol QuillWrappedViewRepresentable {
    var quillWrappedContent: any View { get }
}

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
public func quillTextLabel(from view: any View) -> String {
    if let text = view as? Text {
        return text.content
    }

    if let label = view as? Label {
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
