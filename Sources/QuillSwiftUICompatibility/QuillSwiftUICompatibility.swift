@_exported import SwiftOpenUI
import QuillFoundation

#if os(Linux)
/// SwiftUI's iOS-18 `@Entry` macro for `EnvironmentValues` entries, backed by
/// `QuillDataMacros.QuillEntryMacro`. Expands `@Entry var name: T = default`
/// into a computed get/set plus a private `EnvironmentKey` peer that carries
/// the default value. Surfaced to real source through the SwiftUI shim, which
/// re-exports this canonical compatibility module.
@attached(accessor)
@attached(peer, names: prefixed(`__Key_`))
public macro Entry() = #externalMacro(module: "QuillDataMacros", type: "QuillEntryMacro")

/// SwiftUI's iOS-17 `#Preview { … }` macro. No-op on Linux (previews are never
/// rendered) — expands to nothing, so vendored real source that declares
/// previews compiles. Backed by `QuillDataMacros.QuillPreviewMacro`.
@freestanding(declaration)
public macro Preview<Content>(_ name: String? = nil, @ViewBuilder body: () -> Content) = #externalMacro(module: "QuillDataMacros", type: "QuillPreviewMacro")
#endif

#if os(Linux)
public struct EditActions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let move = EditActions(rawValue: 1 << 0)
    public static let delete = EditActions(rawValue: 1 << 1)
    public static let all: EditActions = [.move, .delete]
}

public extension ForEach where Data: Identifiable, ID == Data.ID {
    init(
        _ data: Binding<[Data]>,
        editActions: EditActions,
        @ViewBuilder content: @escaping (Binding<Data>) -> Content
    ) {
        self.init(data.wrappedValue) { element in
            let elementID = element.id
            return content(Binding<Data>(
                get: {
                    data.wrappedValue.first { $0.id == elementID } ?? element
                },
                set: { newValue in
                    var values = data.wrappedValue
                    if let index = values.firstIndex(where: { $0.id == elementID }) {
                        values[index] = newValue
                    } else {
                        values.append(newValue)
                    }
                    data.wrappedValue = values
                }
            ))
        }
    }
}

/// SwiftUI's localized-key spelling. SwiftOpenUI stores display strings
/// directly today; a typealias keeps explicit `LocalizedStringKey` source
/// compileable without introducing overload ambiguity for string literals.
public typealias LocalizedStringKey = String

public extension TextField {
    /// SwiftUI's prompt overload. SwiftOpenUI has one placeholder slot, so the
    /// prompt takes visual precedence when present.
    init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(prompt?.content ?? titleKey, text: text)
    }

    /// SwiftUI's label-builder overload. When the label is a `Text`, preserve
    /// it as the fallback placeholder; otherwise use the prompt or an empty
    /// placeholder until SwiftOpenUI carries a separate accessibility label.
    init<Label: View>(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) {
        let resolvedLabel = (label() as? Text)?.content ?? ""
        self.init(prompt?.content ?? resolvedLabel, text: text)
    }
}

public extension SecureField {
    /// SwiftUI's prompt overload. SwiftOpenUI has one placeholder slot, so the
    /// prompt takes visual precedence when present.
    init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) {
        self.init(prompt?.content ?? titleKey, text: text)
    }

    /// SwiftUI's label-builder overload. Mirrors `TextField`'s compatibility
    /// behavior for secure input.
    init<Label: View>(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) {
        let resolvedLabel = (label() as? Text)?.content ?? ""
        self.init(prompt?.content ?? resolvedLabel, text: text)
    }
}

public enum SubmitLabel: Hashable, Sendable {
    case `return`
    case done
    case go
    case join
    case next
    case route
    case search
    case send
    case `continue`
}

public struct SubmitLabelView<Content: View>: View {
    public let content: Content
    public let submitLabel: SubmitLabel

    public init(content: Content, submitLabel: SubmitLabel) {
        self.content = content
        self.submitLabel = submitLabel
    }

    public var body: some View { content }
}

public extension View {
    func submitLabel(_ submitLabel: SubmitLabel) -> SubmitLabelView<Self> {
        SubmitLabelView(content: self, submitLabel: submitLabel)
    }
}

/// Canonical Linux image type exposed through the SwiftUI shim.
///
/// SwiftOpenUI keeps its renderer image as a byte-backed value type, but the
/// lowered AppKit/UIKit compatibility layers use `RSImage` for `NSImage` and
/// `UIImage`. Exporting `PlatformImage` as `RSImage` keeps genuine SwiftUI
/// source like `return ImageRenderer(content: view).nsImage` type-compatible
/// with app code that returns `NSImage?` / `PlatformImage?`.
public typealias PlatformImage = RSImage

/// SwiftUI-compatible image renderer that bridges SwiftOpenUI's rendered bytes
/// into QuillFoundation's canonical app image container.
public final class ImageRenderer<Content: View> {
    private let renderer: SwiftOpenUI.ImageRenderer<Content>

    public var content: Content {
        get { renderer.content }
        set { renderer.content = newValue }
    }

    public var scale: CGFloat {
        get { renderer.scale }
        set { renderer.scale = newValue }
    }

    public var proposedSize: CGSize? {
        get { renderer.proposedSize }
        set { renderer.proposedSize = newValue }
    }

    public init(content: Content) {
        self.renderer = SwiftOpenUI.ImageRenderer(content: content)
    }

    public var platformImage: PlatformImage? {
        bridge(renderer.platformImage)
    }

    public var nsImage: PlatformImage? {
        bridge(renderer.nsImage)
    }

    public var uiImage: PlatformImage? {
        bridge(renderer.uiImage)
    }

    public var cgImage: PlatformImage? {
        bridge(renderer.cgImage)
    }

    private func bridge(_ image: SwiftOpenUI.PlatformImage?) -> PlatformImage? {
        guard let image else { return nil }
        return PlatformImage(platformImage: image)
    }
}

public extension RSImage {
    convenience init?(platformImage: SwiftOpenUI.PlatformImage) {
        guard let data = platformImage.data else { return nil }
        self.init(data: data)
    }
}

// Upstream SwiftUI exposes `Font.Weight` as a nested type. SwiftOpenUI
// uses a top-level `FontWeight`, so expose the spelling from one shared
// module that both `QuillUI` and the Linux `SwiftUI` shadow can re-export.
public extension Font {
    typealias Weight = FontWeight
}

// SwiftOpenUI currently provides top/center/bottom alignment only.
// Downgrade baseline-relative alignments to the closest visual
// approximation until backend text metrics can drive true baselines.
public extension VerticalAlignment {
    static var firstTextBaseline: VerticalAlignment { .top }
    static var lastTextBaseline: VerticalAlignment { .bottom }
}
#endif
