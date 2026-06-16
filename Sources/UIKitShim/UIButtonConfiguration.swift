//===----------------------------------------------------------------------===//
//
//  UIButtonConfiguration.swift
//  UIKit shim — the iOS 15 UIButton.Configuration surface
//
//  Everything SignalUI's configuration-based buttons compile against:
//  the Configuration struct (factories, content insets, base colors, image
//  placement, attributed titles, text-attribute transformers), the
//  UIButton accessors layered over it (`configuration`,
//  `configurationUpdateHandler`, `setNeedsUpdateConfiguration`,
//  `init(configuration:primaryAction:)`), and the deprecated
//  UIEdgeInsets-typed edge-inset trio.
//
//  Lives in THIS module (not QuillUIKit, where the UIButton class body is):
//  the surface is NSDirectionalEdgeInsets / UIEdgeInsets / UIFont-typed and
//  those types are declared here — the UIScrollViewInsets.swift layering
//  precedent. The struct is TOP-LEVEL with a `UIButton.Configuration`
//  typealias, exactly Apple's topology (ObjC UIButtonConfiguration renamed
//  into UIButton) — which also keeps it out of the @MainActor class's
//  inferred isolation, so SignalUI's nonisolated factory extensions
//  (`static func largePrimary…`) still compile.
//
//  Honest Linux semantics (MODEL-not-engine, as everywhere in the shims):
//    - A configuration is faithfully recorded state. Applying one pushes
//      title/image/colors into titleLabel / imageView so geometry-free
//      reads agree, but nothing renders backgrounds, insets, or styles.
//    - The style factories (.filled/.gray/.plain/…) differ only in the
//      recorded `quillStyle` tag — there is no appearance engine to
//      diverge on. A future compositor can branch on the tag.
//    - `setNeedsUpdateConfiguration()` updates synchronously: there is no
//      run loop to coalesce on (the UIScrollView instant-animation rule).
//
//  Storage: the UIButton class body is in QuillUIKit (another owner), so
//  per-instance state lives in a file-scope side table with the weak-owner
//  backref + sweep-on-write pattern (UIScrollViewExtras precedent).
//
//===----------------------------------------------------------------------===//

import Foundation
import QuillFoundation
import QuillUIKit

#if !os(iOS)

// MARK: - NSDirectionalRectEdge

/// Writing-direction-relative rect edges (UIKit-declared on Apple, hence in
/// this module next to NSDirectionalEdgeInsets). Raw values match the
/// platform constants. `UIButton.Configuration.imagePlacement` is typed on it.
public struct NSDirectionalRectEdge: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let top = NSDirectionalRectEdge(rawValue: 1 << 0)
    public static let leading = NSDirectionalRectEdge(rawValue: 1 << 1)
    public static let bottom = NSDirectionalRectEdge(rawValue: 1 << 2)
    public static let trailing = NSDirectionalRectEdge(rawValue: 1 << 3)
    public static let all: NSDirectionalRectEdge = [.top, .leading, .bottom, .trailing]
}

// MARK: - Configuration transformers

/// Wraps a closure that rewrites text attributes
/// (`UIButton.Configuration.titleTextAttributesTransformer`). Faithfully
/// applied when a future text engine resolves attributed titles; today the
/// closure is recorded and callable, nothing more.
public struct UIConfigurationTextAttributesTransformer {
    private let transform: (AttributeContainer) -> AttributeContainer

    public init(_ transform: @escaping (AttributeContainer) -> AttributeContainer) {
        self.transform = transform
    }

    public func callAsFunction(_ input: AttributeContainer) -> AttributeContainer {
        transform(input)
    }
}

/// Wraps a closure that rewrites a color (image/activity-indicator color
/// transformers).
public struct UIConfigurationColorTransformer {
    private let transform: (UIColor) -> UIColor

    public init(_ transform: @escaping (UIColor) -> UIColor) {
        self.transform = transform
    }

    public func callAsFunction(_ input: UIColor) -> UIColor {
        transform(input)
    }

    /// MODEL HONESTY: identity — there is no color math on Linux to gray
    /// out with; the blessed name exists so upstream assignments compile.
    /// Computed (not a stored static) so the non-Sendable closure wrapper
    /// passes Swift 6 strict-concurrency checking.
    public static var grayscale: UIConfigurationColorTransformer {
        UIConfigurationColorTransformer { $0 }
    }
}

#if canImport(AppKit) && !os(Linux)
// macOS: AppKit's AttributeScopes already give AttributeContainer a `.font`
// (NSFont, which UIFont aliases here) — declaring one would shadow it.
#else

// MARK: - AttributeContainer.font (Linux)

/// Foundation's AttributeContainer has no UIKit attribute scope on Linux;
/// SignalUI's transformers read/write `attributes.font`. Backed by a custom
/// attribute key carrying the shim UIFont.
public enum QuillUIFontAttributeKey: AttributedStringKey {
    public typealias Value = UIFont
    public static let name = "QuillUIKit.UIFont"
}

extension AttributeContainer {
    public var font: UIFont? {
        get { self[QuillUIFontAttributeKey.self] }
        set { self[QuillUIFontAttributeKey.self] = newValue }
    }
}

// MARK: - AttributedString.font (Linux)

/// The whole-string `font` accessor Apple exposes via its UIKit attribute scope.
/// SignalUI sets `attributedTitle.font` on button-configuration titles. Reads
/// the uniform value (nil when the runs disagree); writes apply to every run.
extension AttributedString {
    public var font: UIFont? {
        get { self[QuillUIFontAttributeKey.self] }
        set { self[QuillUIFontAttributeKey.self] = newValue }
    }
}

// NOTE: AttributedString.AttributeMergePolicy and mergeAttributes(_:mergePolicy:)
// are provided by swift-corelibs Foundation 6.x natively — an earlier shim copy
// here collided ("'AttributeMergePolicy' is ambiguous"), so it was removed.

// MARK: - UIKit attribute scope (Linux)

/// Apple exposes `AttributeScopes.uiKit` (the `UIKitAttributes` scope) as the
/// `including:` argument when converting an `NSAttributedString` into a typed
/// `AttributedString` — SignalUI writes `AttributedString(ns, including: \.uiKit)`.
/// swift-corelibs Foundation on Linux ships no UIKit scope, so the `\.uiKit`
/// keypath has nothing to resolve against ("cannot infer key path type" / "extra
/// argument 'including'"). Alias it to the always-present Foundation scope: on
/// Linux there are no UIKit-only attribute keys to recognize anyway, so the
/// Foundation scope captures everything the conversion can faithfully carry, and
/// `\.uiKit` now resolves to a real `AttributeScope` the native
/// `AttributedString(_:including:)` initializer accepts.
public extension AttributeScopes {
    var uiKit: FoundationAttributes.Type { FoundationAttributes.self }
}

/// Apple's `AttributedString(_ nsAttributedString:, including:)` scoped-conversion
/// initializer. swift-corelibs ships only the unscoped `init(_:)`, so CVText's
/// `AttributedString(ns, including: \.uiKit)` reports "extra argument 'including'".
/// On Linux there are no UIKit-only attribute keys, so the scope is irrelevant —
/// delegate to the unscoped conversion (which carries every attribute corelibs
/// recognizes). Generic over the scope so `\.uiKit` (→ FoundationAttributes) binds.
public extension AttributedString {
    init<S: AttributeScope>(
        _ nsAttributedString: NSAttributedString,
        including keyPath: KeyPath<AttributeScopes, S.Type>
    ) throws {
        // MODEL HONESTY: button titles don't render rich attributes on Linux, and
        // corelibs' scoped NSAttributedString→AttributedString bridge is unreliable,
        // so carry the visible text (attributes dropped). The scope keypath is moot.
        _ = keyPath
        self = AttributedString(nsAttributedString.string)
    }
}

#endif

// MARK: - UIButtonConfiguration

/// Mirror of UIKit's UIButton.Configuration (ObjC UIButtonConfiguration).
/// Value type, nonisolated, surfaced through the nested typealias below.
public struct UIButtonConfiguration {

    // MARK: Nested option enums (raw values match the platform constants)

    public enum CornerStyle: Int, Sendable {
        case fixed = -1
        case dynamic = 0
        case small = 1
        case medium = 2
        case large = 3
        case capsule = 4
    }

    public enum Size: Int, Sendable {
        case medium = 0
        case small = 1
        case mini = 2
        case large = 3
    }

    public enum TitleAlignment: Int, Sendable {
        case automatic = 0
        case leading = 1
        case center = 2
        case trailing = 3
    }

    // MARK: Title

    public var title: String?
    public var attributedTitle: AttributedString?
    public var titleTextAttributesTransformer: UIConfigurationTextAttributesTransformer?
    public var subtitle: String?
    public var attributedSubtitle: AttributedString?
    public var subtitleTextAttributesTransformer: UIConfigurationTextAttributesTransformer?
    public var titlePadding: CGFloat = 0
    public var titleAlignment: TitleAlignment = .automatic
    // Module-qualified for the same AppKit-tie reason as UILabel.lineBreakMode.
    public var titleLineBreakMode: QuillFoundation.NSLineBreakMode = .byTruncatingTail

    // MARK: Image

    public var image: UIImage?
    public var imagePlacement: NSDirectionalRectEdge = .leading
    public var imagePadding: CGFloat = 0
    public var imageColorTransformer: UIConfigurationColorTransformer?

    // MARK: Color & background

    public var baseForegroundColor: UIColor?
    public var baseBackgroundColor: UIColor?
    /// MODEL HONESTY: UIBackgroundConfiguration is a pre-existing CLASS in
    /// QuillUIKit (Apple's is a struct), so Configuration copies share one
    /// background instance. Each fresh Configuration gets its own.
    public var background: UIBackgroundConfiguration = UIBackgroundConfiguration()
    public var cornerStyle: CornerStyle = .dynamic

    // MARK: Layout

    public var buttonSize: Size = .medium
    public var contentInsets: NSDirectionalEdgeInsets = .zero
    public var showsActivityIndicator: Bool = false
    public var automaticallyUpdateForSelection: Bool = true

    /// Which factory minted this configuration (`"plain"`, `"filled"`, …).
    /// Apple resolves real appearance from the style; on Linux the tag is
    /// the honest record a future compositor can branch on.
    public var quillStyle: String = "plain"

    public init() {}

    private init(quillStyle: String) {
        self.quillStyle = quillStyle
    }

    // MARK: Style factories

    public static func plain() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "plain")
    }

    public static func filled() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "filled")
    }

    public static func gray() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "gray")
    }

    public static func tinted() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "tinted")
    }

    public static func bordered() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "bordered")
    }

    public static func borderedTinted() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "borderedTinted")
    }

    public static func borderedProminent() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "borderedProminent")
    }

    public static func borderless() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "borderless")
    }

    /// iOS 26 Liquid Glass styles. Reachable on Linux because `*` satisfies
    /// `if #available(iOS 26, *)` on non-iOS platforms, so upstream's
    /// glass branches execute here.
    public static func glass() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "glass")
    }

    public static func prominentGlass() -> UIButtonConfiguration {
        UIButtonConfiguration(quillStyle: "prominentGlass")
    }

    /// State-resolved copy. MODEL HONESTY: no appearance engine resolves
    /// per-state colors on Linux, so this returns the configuration as-is.
    @MainActor public func updated(for button: UIButton) -> UIButtonConfiguration {
        _ = button
        return self
    }
}

// MARK: - UIButton configuration surface

private struct QuillButtonConfigurationState {
    /// Backref validating the table entry against address reuse.
    weak var owner: UIButton?

    var configuration: UIButtonConfiguration?
    var configurationUpdateHandler: UIButton.ConfigurationUpdateHandler?
    var automaticallyUpdatesConfiguration = true
    /// Recursion guard: the update handler conventionally mutates
    /// `button.configuration`, whose setter requests another update.
    var isApplyingUpdate = false
    /// Recorded by `init(configuration:primaryAction:)` for a future event
    /// backend (the UIAction.quillHandler tradition); nothing fires it yet.
    var primaryAction: UIAction?

    // Deprecated classic-layout insets: faithfully stored, nothing lays out.
    var contentEdgeInsets: UIEdgeInsets = .zero
    var titleEdgeInsets: UIEdgeInsets = .zero
    var imageEdgeInsets: UIEdgeInsets = .zero

    // Deprecated automatic image dimming (Apple default: true): faithfully
    // stored, nothing dims on Linux.
    var adjustsImageWhenHighlighted = true
    var adjustsImageWhenDisabled = true
}

@MainActor private var quillButtonConfigurationStates:
    [ObjectIdentifier: QuillButtonConfigurationState] = [:]

extension UIButton {

    public typealias Configuration = UIButtonConfiguration
    public typealias ConfigurationUpdateHandler = (UIButton) -> Void

    /// The instance's state, validated against address reuse on read and
    /// re-stamped with `owner` on write (the UIScrollViewExtras pattern).
    private var quillConfigurationState: QuillButtonConfigurationState {
        get {
            if let state = quillButtonConfigurationStates[ObjectIdentifier(self)],
               state.owner === self {
                return state
            }
            return QuillButtonConfigurationState(owner: self)
        }
        set {
            // First write from this instance: sweep entries whose owner has
            // deallocated so the table stays bounded by live buttons.
            if quillButtonConfigurationStates[ObjectIdentifier(self)]?.owner !== self {
                quillButtonConfigurationStates =
                    quillButtonConfigurationStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillButtonConfigurationStates[ObjectIdentifier(self)] = state
        }
    }

    public convenience init(configuration: UIButton.Configuration, primaryAction: UIAction? = nil) {
        self.init(frame: .zero)
        quillConfigurationState.primaryAction = primaryAction
        self.configuration = configuration
    }

    /// The action recorded by `init(configuration:primaryAction:)`, exposed
    /// `quill`-prefixed so a future event backend (or a test) can fire it.
    public var quillPrimaryAction: UIAction? {
        quillConfigurationState.primaryAction
    }

    public var configuration: Configuration? {
        get { quillConfigurationState.configuration }
        set {
            quillConfigurationState.configuration = newValue
            setNeedsUpdateConfiguration()
        }
    }

    public var configurationUpdateHandler: ConfigurationUpdateHandler? {
        get { quillConfigurationState.configurationUpdateHandler }
        set {
            quillConfigurationState.configurationUpdateHandler = newValue
            setNeedsUpdateConfiguration()
        }
    }

    /// Faithfully stored; with no event backend there are no state changes
    /// to trigger automatic updates from, so explicit setters drive updates.
    public var automaticallyUpdatesConfiguration: Bool {
        get { quillConfigurationState.automaticallyUpdatesConfiguration }
        set { quillConfigurationState.automaticallyUpdatesConfiguration = newValue }
    }

    /// Synchronous: there is no run loop to defer to on Linux (the
    /// instant-animation rule), so "needs update" IS the update.
    public func setNeedsUpdateConfiguration() {
        updateConfiguration()
    }

    /// Runs the update handler, then pushes the (possibly handler-mutated)
    /// configuration into `titleLabel` / `imageView` so geometry-free reads
    /// agree with the recorded state.
    ///
    /// NOTE: extension methods cannot be overridden — if a SignalUI subclass
    /// overrides `updateConfiguration()`, this must move into the UIButton
    /// class body (QuillUIKit.swift) as `open func`.
    public func updateConfiguration() {
        guard !quillConfigurationState.isApplyingUpdate else { return }
        if let handler = quillConfigurationState.configurationUpdateHandler {
            quillConfigurationState.isApplyingUpdate = true
            handler(self)
            quillConfigurationState.isApplyingUpdate = false
        }
        guard let configuration = quillConfigurationState.configuration else { return }

        // Configuration-driven buttons derive their content wholly from the
        // configuration, as on Apple. titleLabel is created by its accessor.
        titleLabel?.text = configuration.attributedTitle.map { String($0.characters) }
            ?? configuration.title
        titleLabel?.lineBreakMode = configuration.titleLineBreakMode
        switch configuration.titleAlignment {
        case .automatic:
            break
        case .leading:
            // MODEL HONESTY: no writing-direction resolution on Linux;
            // leading/trailing map to left/right.
            titleLabel?.textAlignment = .left
        case .center:
            titleLabel?.textAlignment = .center
        case .trailing:
            titleLabel?.textAlignment = .right
        }
        if let foregroundColor = configuration.baseForegroundColor {
            titleLabel?.textColor = foregroundColor
        }

        if let image = configuration.image {
            if imageView == nil {
                let imageView = UIImageView(image: nil)
                self.imageView = imageView
                addSubview(imageView)
            }
            imageView?.image = image
        } else {
            imageView?.image = nil
        }
    }

    // MARK: Deprecated classic-layout insets

    /// Pre-iOS-15 inset trio. Faithfully stored configuration: no layout
    /// pass consumes them on Linux yet (deprecated on Apple in favor of
    /// `configuration.contentInsets`).
    public var contentEdgeInsets: UIEdgeInsets {
        get { quillConfigurationState.contentEdgeInsets }
        set { quillConfigurationState.contentEdgeInsets = newValue }
    }

    public var titleEdgeInsets: UIEdgeInsets {
        get { quillConfigurationState.titleEdgeInsets }
        set { quillConfigurationState.titleEdgeInsets = newValue }
    }

    public var imageEdgeInsets: UIEdgeInsets {
        get { quillConfigurationState.imageEdgeInsets }
        set { quillConfigurationState.imageEdgeInsets = newValue }
    }

    /// Pre-iOS-15 automatic image dimming pair (deprecated on Apple in
    /// favor of `UIButton.Configuration`). Faithfully stored with Apple's
    /// default (true); no rendering consumes them on Linux yet.
    public var adjustsImageWhenHighlighted: Bool {
        get { quillConfigurationState.adjustsImageWhenHighlighted }
        set { quillConfigurationState.adjustsImageWhenHighlighted = newValue }
    }

    public var adjustsImageWhenDisabled: Bool {
        get { quillConfigurationState.adjustsImageWhenDisabled }
        set { quillConfigurationState.adjustsImageWhenDisabled = newValue }
    }
}

// `UIBackgroundConfiguration.backgroundInsets` is NSDirectionalEdgeInsets-typed
// (MentionPicker sets it on its list-cell configuration). That type lives in
// this UIKit shim module, so the typed accessor is layered HERE over the
// edge-relative `quillBackgroundInsets` storage in QuillUIKit -- the same split
// used for UIView.directionalLayoutMargins.
public extension UIBackgroundConfiguration {
    var backgroundInsets: NSDirectionalEdgeInsets {
        get {
            let stored = quillBackgroundInsets
            return NSDirectionalEdgeInsets(top: stored.top, leading: stored.left, bottom: stored.bottom, trailing: stored.right)
        }
        set {
            quillBackgroundInsets = UIEdgeInsets(top: newValue.top, left: newValue.leading, bottom: newValue.bottom, right: newValue.trailing)
        }
    }
}

#endif // !os(iOS)
