//===----------------------------------------------------------------------===//
//
//  UIButtonExtras.swift
//  QuillUIKit — the classic UIButton content surface for Linux
//
//  The pre-iOS-15 UIButton API that Signal-iOS's SignalUI compiles against:
//  the per-state content tables (setTitle / setImage / setTitleColor /
//  setAttributedTitle / setBackgroundImage and their getters), the lazily
//  created `titleLabel`, `ButtonType` + `init(type:)`, and the
//  UIBackgroundConfiguration appearance members that
//  `UIButton.Configuration.background` mutates (cornerRadius & co.).
//
//  Honest Linux semantics (same MODEL-not-engine rules as the rest of the
//  module):
//    - Per-state values are faithfully recorded; `current*` resolves the
//      stored `state` with the Apple fallback to `.normal`. With no event
//      backend the control state only changes when code sets it, so the
//      refresh after each mutation is the whole "update pass".
//    - `titleLabel` is created on first access and added as a subview,
//      as on Apple; nothing measures or draws it yet.
//    - The iOS 15 `UIButton.Configuration` surface is NOT here: it is
//      UIEdgeInsets/NSDirectionalEdgeInsets/UIFont-typed and those types
//      live in the UIKit shim module, which depends on this one
//      (Sources/UIKitShim/UIButtonConfiguration.swift layers it on top,
//      the UIScrollViewInsets.swift precedent).
//
//  Storage: the class body lives in QuillUIKit.swift (another owner), and
//  extensions cannot add stored properties, so per-instance state lives in a
//  file-scope side table — the UIScrollViewExtras pattern. A weak `owner`
//  backref guards every read against ObjectIdentifier address reuse, and
//  dead entries are swept on write.
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UIButton.ButtonType

/// Mirror of UIKit's UIButton.ButtonType (ObjC UIButtonType). Top-level enum
/// surfaced through the `UIButton.ButtonType` typealias — exactly Apple's
/// topology, and it keeps the enum out of the @MainActor class's inferred
/// isolation. Raw values match the platform constants.
public enum UIButtonType: Int, Sendable {
    case custom = 0
    case system = 1
    case detailDisclosure = 2
    case infoLight = 3
    case infoDark = 4
    case contactAdd = 5
    case close = 7
}

// MARK: - Side table

// `internal` (not `private`): the `quillButtonState` accessor is internal so the
// class-body `setImage(_:for:)` (QuillUIKit.swift) can reach it; an internal
// property may not expose a private type, so the struct (and its fields) are
// internal too.
struct QuillButtonState {
    /// Backref validating the table entry against address reuse.
    weak var owner: UIButton?

    var buttonType: UIButtonType = .custom
    /// Lazily created by the `titleLabel` accessor; strong, like the view's
    /// hold on any subview.
    var titleLabel: UILabel?

    // Per-state content tables, keyed by UIControl.State.rawValue.
    var titles: [UInt: String] = [:]
    var attributedTitles: [UInt: NSAttributedString] = [:]
    var titleColors: [UInt: UIColor] = [:]
    var images: [UInt: UIImage] = [:]
    var backgroundImages: [UInt: UIImage] = [:]
    var contentInsets: QuillEdgeInsets = .zero
    var imagePadding: CGFloat = 0
}

@MainActor private var quillButtonStates: [ObjectIdentifier: QuillButtonState] = [:]

// MARK: - UIButton classic content surface

extension UIButton {

    public typealias ButtonType = UIButtonType

    /// The instance's state, validated against address reuse on read and
    /// re-stamped with `owner` on write (the UIScrollViewExtras pattern).
    /// `internal` (not `private`): `setImage(_:for:)` lives in the UIButton
    /// CLASS BODY (QuillUIKit.swift) so AvatarImageView can `override` it, and
    /// that override needs to reach this accessor.
    var quillButtonState: QuillButtonState {
        get {
            if let state = quillButtonStates[ObjectIdentifier(self)], state.owner === self {
                return state
            }
            return QuillButtonState(owner: self)
        }
        set {
            // First write from this instance: sweep entries whose owner has
            // deallocated so the table stays bounded by live buttons.
            if quillButtonStates[ObjectIdentifier(self)]?.owner !== self {
                quillButtonStates = quillButtonStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillButtonStates[ObjectIdentifier(self)] = state
        }
    }

    /// Apple resolution order: exact current state, then `.normal`.
    private func quillStateValue<Value>(_ table: [UInt: Value]) -> Value? {
        table[state.rawValue] ?? table[UIControl.State.normal.rawValue]
    }

    // MARK: ButtonType

    public var buttonType: ButtonType {
        quillButtonState.buttonType
    }

    public convenience init(type buttonType: ButtonType) {
        self.init(frame: .zero)
        quillButtonState.buttonType = buttonType
    }

    /// iOS 14+ `UIButton(type:primaryAction:)`. The action (when non-nil) is
    /// registered for `.primaryActionTriggered`, and its title/image seed the
    /// button's `.normal` content — exactly as UIKit's convenience does.
    public convenience init(type buttonType: ButtonType = .system, primaryAction: UIAction?) {
        self.init(type: buttonType)
        if let primaryAction {
            if !primaryAction.title.isEmpty { setTitle(primaryAction.title, for: .normal) }
            if let image = primaryAction.image { setImage(image, for: .normal) }
            addAction(primaryAction, for: .primaryActionTriggered)
        }
    }

    /// `UIButton(frame:primaryAction:)` companion of the above.
    public convenience init(frame: CGRect, primaryAction: UIAction?) {
        self.init(frame: frame)
        if let primaryAction {
            if !primaryAction.title.isEmpty { setTitle(primaryAction.title, for: .normal) }
            if let image = primaryAction.image { setImage(image, for: .normal) }
            addAction(primaryAction, for: .primaryActionTriggered)
        }
    }

    // MARK: titleLabel

    /// The label that shows the current title. Created (and added as a
    /// subview) on first access, as on Apple; optional-typed like the
    /// original so `guard let titleLabel` upstream still compiles.
    public var titleLabel: UILabel? {
        if let label = quillButtonState.titleLabel {
            return label
        }
        let label = UILabel()
        quillButtonState.titleLabel = label
        addSubview(label)
        return label
    }

    // MARK: Per-state titles

    public func setTitle(_ title: String?, for state: UIControl.State) {
        if let title {
            quillButtonState.titles[state.rawValue] = title
        } else {
            quillButtonState.titles.removeValue(forKey: state.rawValue)
        }
        quillRefreshContent()
    }

    public func title(for state: UIControl.State) -> String? {
        quillButtonState.titles[state.rawValue]
    }

    public var currentTitle: String? {
        quillStateValue(quillButtonState.titles)
    }

    public func setAttributedTitle(_ title: NSAttributedString?, for state: UIControl.State) {
        if let title {
            quillButtonState.attributedTitles[state.rawValue] = title
        } else {
            quillButtonState.attributedTitles.removeValue(forKey: state.rawValue)
        }
        quillRefreshContent()
    }

    public func attributedTitle(for state: UIControl.State) -> NSAttributedString? {
        quillButtonState.attributedTitles[state.rawValue]
    }

    public var currentAttributedTitle: NSAttributedString? {
        quillStateValue(quillButtonState.attributedTitles)
    }

    // MARK: Per-state title colors

    public func setTitleColor(_ color: UIColor?, for state: UIControl.State) {
        if let color {
            quillButtonState.titleColors[state.rawValue] = color
        } else {
            quillButtonState.titleColors.removeValue(forKey: state.rawValue)
        }
        quillRefreshContent()
    }

    public func titleColor(for state: UIControl.State) -> UIColor? {
        quillButtonState.titleColors[state.rawValue]
    }

    /// Non-optional on Apple: falls back to the semantic label color when
    /// nothing was recorded (Apple falls back to system defaults too).
    public var currentTitleColor: UIColor {
        if let color = quillStateValue(quillButtonState.titleColors) {
            return color
        }
        // Platform-gated like UILabel.textColor: macOS NSColor spells the
        // semantic color `labelColor`; the Linux RSColor has `label`.
        #if os(macOS)
        return .labelColor
        #else
        return .label
        #endif
    }

    // MARK: Per-state images
    //
    // `setImage(_:for:)` is NOT here: it lives in the UIButton CLASS BODY
    // (QuillUIKit.swift) as `open` so AvatarImageView can override it (an
    // extension method cannot be overridden cross-module). The read side stays
    // in the extension.

    public func image(for state: UIControl.State) -> UIImage? {
        quillButtonState.images[state.rawValue]
    }

    public var currentImage: UIImage? {
        quillStateValue(quillButtonState.images)
    }

    public func setBackgroundImage(_ image: UIImage?, for state: UIControl.State) {
        if let image {
            quillButtonState.backgroundImages[state.rawValue] = image
        } else {
            quillButtonState.backgroundImages.removeValue(forKey: state.rawValue)
        }
    }

    public func backgroundImage(for state: UIControl.State) -> UIImage? {
        quillButtonState.backgroundImages[state.rawValue]
    }

    public var currentBackgroundImage: UIImage? {
        quillStateValue(quillButtonState.backgroundImages)
    }

    // MARK: Measurement hints

    /// QuillUIKit-owned content insets consumed by UIButton.sizeThatFits and
    /// layoutSubviews. The UIKit shim maps both classic contentEdgeInsets and
    /// UIButton.Configuration.contentInsets into this storage.
    public var quillMeasuredContentInsets: QuillEdgeInsets {
        get { quillButtonState.contentInsets }
        set { quillButtonState.contentInsets = newValue }
    }

    /// Spacing between image and title when both are present.
    public var quillMeasuredImagePadding: CGFloat {
        get { quillButtonState.imagePadding }
        set { quillButtonState.imagePadding = max(0, newValue) }
    }

    // MARK: Refresh

    /// Pushes the current-state content into `titleLabel` / `imageView`.
    /// With no event backend the control state never changes on its own, so
    /// running this after every mutation IS Apple's update pass. The label
    /// and image view are only created once there is content for them, so
    /// image-only buttons don't grow a stray empty label.
    /// `internal` (not `private`): the class-body `setImage(_:for:)` calls it.
    func quillRefreshContent() {
        let state = quillButtonState
        if !state.titles.isEmpty || !state.attributedTitles.isEmpty {
            if let attributed = quillStateValue(state.attributedTitles) {
                titleLabel?.attributedText = attributed
                titleLabel?.text = attributed.string
            } else {
                titleLabel?.text = quillStateValue(state.titles)
            }
            if let color = quillStateValue(state.titleColors) {
                titleLabel?.textColor = color
            }
        }
        if !state.images.isEmpty {
            if imageView == nil {
                let imageView = UIImageView(image: nil)
                self.imageView = imageView
                addSubview(imageView)
            }
            imageView?.image = quillStateValue(state.images)
        }
    }
}

// MARK: - UIBackgroundConfiguration appearance members

/// The class body (QuillUIKit.swift, another owner) declares only the list-cell
/// factories; `UIButton.Configuration.background` mutates the appearance
/// members below (`background.cornerRadius = 14` & co. in SignalUI).
///
/// MODEL HONESTY: Apple's UIBackgroundConfiguration is a struct; here it is a
/// pre-existing class, so Configuration copies share one background instance.
/// Nothing renders these values on Linux yet — they are faithfully recorded
/// for a future compositor.
private struct QuillBackgroundConfigurationState {
    weak var owner: UIBackgroundConfiguration?
    var backgroundColor: UIColor?
    var cornerRadius: CGFloat = 0
    var strokeColor: UIColor?
    var strokeWidth: CGFloat = 0
    // Stored as QuillEdgeInsets (== UIEdgeInsets): this module can't name
    // NSDirectionalEdgeInsets (it lives in the UIKit shim). The directional-
    // typed `backgroundInsets` accessor is layered in Sources/UIKitShim.
    var backgroundInsets: QuillEdgeInsets = .zero
    var customView: UIView?
}

/// Not MainActor-bound: Apple's type is a value type usable off-main, and the
/// nonisolated `UIButton.Configuration` factory functions in SignalUI mutate
/// these members. UI configuration construction is single-threaded in
/// practice on Linux (the UISwitch.isOn precedent).
nonisolated(unsafe) private var quillBackgroundConfigurationStates:
    [ObjectIdentifier: QuillBackgroundConfigurationState] = [:]

extension UIBackgroundConfiguration {

    private var quillBackgroundState: QuillBackgroundConfigurationState {
        get {
            if let state = quillBackgroundConfigurationStates[ObjectIdentifier(self)],
               state.owner === self {
                return state
            }
            return QuillBackgroundConfigurationState(owner: self)
        }
        set {
            if quillBackgroundConfigurationStates[ObjectIdentifier(self)]?.owner !== self {
                quillBackgroundConfigurationStates =
                    quillBackgroundConfigurationStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillBackgroundConfigurationStates[ObjectIdentifier(self)] = state
        }
    }

    /// An empty configuration with no background color or insets.
    public static func clear() -> UIBackgroundConfiguration {
        UIBackgroundConfiguration()
    }

    public var backgroundColor: UIColor? {
        get { quillBackgroundState.backgroundColor }
        set { quillBackgroundState.backgroundColor = newValue }
    }

    public var cornerRadius: CGFloat {
        get { quillBackgroundState.cornerRadius }
        set { quillBackgroundState.cornerRadius = newValue }
    }

    public var strokeColor: UIColor? {
        get { quillBackgroundState.strokeColor }
        set { quillBackgroundState.strokeColor = newValue }
    }

    public var strokeWidth: CGFloat {
        get { quillBackgroundState.strokeWidth }
        set { quillBackgroundState.strokeWidth = newValue }
    }

    /// Edge-relative backing for the directional `backgroundInsets` accessor
    /// layered in Sources/UIKitShim (NSDirectionalEdgeInsets isn't nameable
    /// here). `public` so the shim's layered accessor — in a downstream module —
    /// can read/write it (the `quillLayoutMargins` precedent).
    public var quillBackgroundInsets: QuillEdgeInsets {
        get { quillBackgroundState.backgroundInsets }
        set { quillBackgroundState.backgroundInsets = newValue }
    }

    public var customView: UIView? {
        get { quillBackgroundState.customView }
        set { quillBackgroundState.customView = newValue }
    }
}

#endif // !os(iOS)
