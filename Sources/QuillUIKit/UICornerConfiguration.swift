// QuillUIKit · UICornerConfiguration / UICornerRadius (iOS 26)
// ============================================================
// The iOS-26 corner API: `UIView.cornerConfiguration` with the
// UICornerConfiguration / UICornerRadius value types. Signal adopts it
// behind `if #available(iOS 26…)` guards everywhere it used to set
// `layer.cornerRadius` (ActionSheetController, InteractiveSheetViewController,
// Toast, ReminderView, LinkPreviewView, ModalActivityIndicatorViewController,
// StickerPickerKeyboard, …); availability checks pass on Linux, so the
// surface must exist with Apple's exact shapes.
//
// Shapes mirror the iOS 26 SDK's Swift overlay (UIKit.swiftmodule
// swiftinterface): both types are structs (the ObjC classes are
// NS_REFINED_FOR_SWIFT), every factory below carries the overlay's
// signature, and UICornerRadius is expressible by float/integer literals.
// One pragmatic deviation: radius parameters are CGFloat where the overlay
// spells Swift.Double — the compiler's implicit Double↔CGFloat bridging is
// Apple-platform magic this repo doesn't rely on, and every Signal call
// site passes CGFloat values or literals.
//
// Honest Linux semantics: a configuration is a faithful VALUE — stored per
// view (side table below), equatable/hashable, and readable by a future
// render pass. Nothing rounds pixels yet. The one live wire: setting a
// configuration whose corners all resolve to a single FIXED radius mirrors
// that radius into `layer.cornerRadius`, keeping the layer model coherent
// for code (and the future renderer) that reads the layer. Capsule and
// container-concentric radii need live geometry to resolve, so they leave
// the layer untouched.

import QuillFoundation

#if os(Linux)
// CALayer for the fixed-radius mirror into UIView.layer (same arrangement
// as QuillUIKit.swift's UIView.layer block).
import QuartzCore
#endif

#if !os(iOS)

// MARK: - UICornerRadius

/// Represents a radius used to round a corner (iOS 26).
///
/// Either a fixed point value or a dynamic "container concentric" radius
/// that a future render pass resolves from the view's geometry and its
/// container's corner rounding.
public struct UICornerRadius: Hashable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, CustomStringConvertible {

    /// The resolution rule. Internal: a future render pass (same package)
    /// switches over it; upstream code only uses the factories.
    enum Resolution: Hashable, Sendable {
        case fixed(CGFloat)
        case containerConcentric(minimum: CGFloat?)
    }

    let resolution: Resolution

    private init(_ resolution: Resolution) {
        self.resolution = resolution
    }

    /// A fixed corner radius in points.
    public static func fixed(_ radius: CGFloat) -> UICornerRadius {
        UICornerRadius(.fixed(radius))
    }

    /// A dynamic corner radius calculated from the geometry of the view and
    /// its container, optionally limited to a minimum radius. (Apple's
    /// overlay defaults `minimum` to nil, standing in for the parameterless
    /// `containerConcentricRadius` too.)
    public static func containerConcentric(minimum: CGFloat? = nil) -> UICornerRadius {
        UICornerRadius(.containerConcentric(minimum: minimum))
    }

    /// `cornerConfiguration = .corners(radius: 24)` works on Apple via these.
    public init(floatLiteral value: FloatLiteralType) {
        self.init(.fixed(CGFloat(value)))
    }

    public init(integerLiteral value: IntegerLiteralType) {
        self.init(.fixed(CGFloat(value)))
    }

    public var description: String {
        switch resolution {
        case .fixed(let radius):
            return "fixed(\(radius))"
        case .containerConcentric(let minimum):
            if let minimum {
                return "containerConcentric(minimum: \(minimum))"
            }
            return "containerConcentric"
        }
    }

    /// The radius when it is statically known (fixed), else nil. Feeds the
    /// layer.cornerRadius mirror below.
    var quillFixedValue: CGFloat? {
        if case .fixed(let radius) = resolution { return radius }
        return nil
    }
}

// MARK: - UICornerConfiguration

/// Defines how corner radii are mapped to the corners of a rectangle
/// (iOS 26). Factories mirror Apple's overlay exactly — including the
/// distinction between `corners(radius:)` (each corner resolves its radius
/// independently) and `uniformCorners(radius:)` (one resolved radius shared
/// by all corners), which only matters for dynamic radii.
public struct UICornerConfiguration: Hashable, Sendable, CustomStringConvertible {

    /// One case per factory family, so configurations built differently
    /// stay distinguishable (Equatable/Hashable) and a future render pass
    /// can honor each resolution rule. Internal, like UICornerRadius.Resolution.
    enum Model: Hashable, Sendable {
        /// Independent per-corner resolution (`corners(radius:)` populates
        /// all four with the same radius; nil corners keep their current
        /// rounding, per Apple's nullable parameters).
        case corners(topLeft: UICornerRadius?, topRight: UICornerRadius?, bottomLeft: UICornerRadius?, bottomRight: UICornerRadius?)
        /// Capsule: radius scales with the view's size, optionally clamped.
        case capsule(maximumRadius: CGFloat?)
        /// One resolved radius applied to all corners.
        case uniform(UICornerRadius)
        /// `uniformEdges(topRadius:bottomRadius:)`.
        case uniformTopBottom(top: UICornerRadius, bottom: UICornerRadius)
        /// `uniformEdges(leftRadius:rightRadius:)`.
        case uniformLeftRight(left: UICornerRadius, right: UICornerRadius)
        /// `uniformTopRadius(_:bottomLeftRadius:bottomRightRadius:)`.
        case uniformTop(UICornerRadius, bottomLeft: UICornerRadius?, bottomRight: UICornerRadius?)
        /// `uniformBottomRadius(_:topLeftRadius:topRightRadius:)`.
        case uniformBottom(UICornerRadius, topLeft: UICornerRadius?, topRight: UICornerRadius?)
        /// `uniformLeftRadius(_:topRightRadius:bottomRightRadius:)`.
        case uniformLeft(UICornerRadius, topRight: UICornerRadius?, bottomRight: UICornerRadius?)
        /// `uniformRightRadius(_:topLeftRadius:bottomLeftRadius:)`.
        case uniformRight(UICornerRadius, topLeft: UICornerRadius?, bottomLeft: UICornerRadius?)
    }

    let model: Model

    private init(_ model: Model) {
        self.model = model
    }

    /// A configuration that applies the given radius independently to all
    /// corners (a container-concentric radius may resolve differently per
    /// corner).
    public static func corners(radius: UICornerRadius) -> UICornerConfiguration {
        UICornerConfiguration(.corners(topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius))
    }

    /// A configuration with independent radii for each corner. Nil leaves
    /// that corner's rounding unchanged.
    public static func corners(
        topLeftRadius: UICornerRadius?,
        topRightRadius: UICornerRadius?,
        bottomLeftRadius: UICornerRadius?,
        bottomRightRadius: UICornerRadius?
    ) -> UICornerConfiguration {
        UICornerConfiguration(.corners(topLeft: topLeftRadius, topRight: topRightRadius, bottomLeft: bottomLeftRadius, bottomRight: bottomRightRadius))
    }

    /// A configuration that rounds the corners into a capsule shape, scaling
    /// with the view's size and (when given) clamped to `maximumRadius`.
    public static func capsule(maximumRadius: CGFloat? = nil) -> UICornerConfiguration {
        UICornerConfiguration(.capsule(maximumRadius: maximumRadius))
    }

    /// A configuration that applies the given radius uniformly to all
    /// corners (one resolved value shared by every corner).
    public static func uniformCorners(radius: UICornerRadius) -> UICornerConfiguration {
        UICornerConfiguration(.uniform(radius))
    }

    /// `topRadius` uniformly across the top corners, `bottomRadius`
    /// uniformly across the bottom corners.
    public static func uniformEdges(topRadius: UICornerRadius, bottomRadius: UICornerRadius) -> UICornerConfiguration {
        UICornerConfiguration(.uniformTopBottom(top: topRadius, bottom: bottomRadius))
    }

    /// `leftRadius` uniformly across the left corners, `rightRadius`
    /// uniformly across the right corners.
    public static func uniformEdges(leftRadius: UICornerRadius, rightRadius: UICornerRadius) -> UICornerConfiguration {
        UICornerConfiguration(.uniformLeftRight(left: leftRadius, right: rightRadius))
    }

    /// `topRadius` uniformly across the top corners, with optional
    /// independent bottom corners.
    public static func uniformTopRadius(
        _ topRadius: UICornerRadius,
        bottomLeftRadius: UICornerRadius? = nil,
        bottomRightRadius: UICornerRadius? = nil
    ) -> UICornerConfiguration {
        UICornerConfiguration(.uniformTop(topRadius, bottomLeft: bottomLeftRadius, bottomRight: bottomRightRadius))
    }

    /// `bottomRadius` uniformly across the bottom corners, with optional
    /// independent top corners.
    public static func uniformBottomRadius(
        _ bottomRadius: UICornerRadius,
        topLeftRadius: UICornerRadius? = nil,
        topRightRadius: UICornerRadius? = nil
    ) -> UICornerConfiguration {
        UICornerConfiguration(.uniformBottom(bottomRadius, topLeft: topLeftRadius, topRight: topRightRadius))
    }

    /// `leftRadius` uniformly across the left corners, with optional
    /// independent right corners.
    public static func uniformLeftRadius(
        _ leftRadius: UICornerRadius,
        topRightRadius: UICornerRadius? = nil,
        bottomRightRadius: UICornerRadius? = nil
    ) -> UICornerConfiguration {
        UICornerConfiguration(.uniformLeft(leftRadius, topRight: topRightRadius, bottomRight: bottomRightRadius))
    }

    /// `rightRadius` uniformly across the right corners, with optional
    /// independent left corners.
    public static func uniformRightRadius(
        _ rightRadius: UICornerRadius,
        topLeftRadius: UICornerRadius? = nil,
        bottomLeftRadius: UICornerRadius? = nil
    ) -> UICornerConfiguration {
        UICornerConfiguration(.uniformRight(rightRadius, topLeft: topLeftRadius, bottomLeft: bottomLeftRadius))
    }

    public var description: String {
        func corner(_ radius: UICornerRadius?) -> String {
            radius.map(\.description) ?? "nil"
        }
        switch model {
        case .corners(let tl, let tr, let bl, let br):
            return "corners(topLeft: \(corner(tl)), topRight: \(corner(tr)), bottomLeft: \(corner(bl)), bottomRight: \(corner(br)))"
        case .capsule(let maximumRadius):
            if let maximumRadius {
                return "capsule(maximumRadius: \(maximumRadius))"
            }
            return "capsule"
        case .uniform(let radius):
            return "uniformCorners(\(radius))"
        case .uniformTopBottom(let top, let bottom):
            return "uniformEdges(top: \(top), bottom: \(bottom))"
        case .uniformLeftRight(let left, let right):
            return "uniformEdges(left: \(left), right: \(right))"
        case .uniformTop(let top, let bl, let br):
            return "uniformTopRadius(\(top), bottomLeft: \(corner(bl)), bottomRight: \(corner(br)))"
        case .uniformBottom(let bottom, let tl, let tr):
            return "uniformBottomRadius(\(bottom), topLeft: \(corner(tl)), topRight: \(corner(tr)))"
        case .uniformLeft(let left, let tr, let br):
            return "uniformLeftRadius(\(left), topRight: \(corner(tr)), bottomRight: \(corner(br)))"
        case .uniformRight(let right, let tl, let bl):
            return "uniformRightRadius(\(right), topLeft: \(corner(tl)), bottomLeft: \(corner(bl)))"
        }
    }

    /// The single FIXED radius every corner resolves to, when one exists
    /// statically (no geometry needed) — the only shape that can be
    /// mirrored into `layer.cornerRadius` without a layout pass.
    var quillUniformFixedRadius: CGFloat? {
        switch model {
        case .uniform(let radius):
            return radius.quillFixedValue
        case .corners(let tl, let tr, let bl, let br):
            guard let value = tl?.quillFixedValue,
                  tr?.quillFixedValue == value,
                  bl?.quillFixedValue == value,
                  br?.quillFixedValue == value else { return nil }
            return value
        case .uniformTopBottom(let top, let bottom):
            guard let value = top.quillFixedValue, bottom.quillFixedValue == value else { return nil }
            return value
        case .uniformLeftRight(let left, let right):
            guard let value = left.quillFixedValue, right.quillFixedValue == value else { return nil }
            return value
        case .capsule, .uniformTop, .uniformBottom, .uniformLeft, .uniformRight:
            return nil
        }
    }
}

// MARK: - UIView.cornerConfiguration

/// Side table for per-view corner configurations, keyed by ObjectIdentifier.
/// Same accepted trade-off as viewPreservesSuperviewLayoutMargins
/// (UIViewMargins.swift): entries for deallocated views are not reclaimed,
/// so a recycled allocation could in principle inherit a stale value; the
/// payload is one small value type per view that ever sets it.
@MainActor private var viewCornerConfigurations: [ObjectIdentifier: UICornerConfiguration] = [:]

extension UIView {

    /// The iOS-26 corner API. Apple declares this `open` on UIView;
    /// extension members can't be `open`, so it is `public` — upstream code
    /// assigns it, never overrides it. Covers UIVisualEffectView and every
    /// other subclass by inheritance, exactly as on Apple.
    ///
    /// Setting a configuration whose corners all resolve to one fixed
    /// radius mirrors it into `layer.cornerRadius` (Linux), keeping the
    /// layer model coherent; dynamic shapes (capsule, containerConcentric)
    /// await a render pass with live geometry. Reading before any set
    /// reports the layer's current fixed rounding, matching Apple's
    /// layer-synced behavior.
    public var cornerConfiguration: UICornerConfiguration {
        get {
            if let stored = viewCornerConfigurations[ObjectIdentifier(self)] {
                return stored
            }
            #if os(Linux)
            return .corners(radius: .fixed(layer.cornerRadius))
            #else
            return .corners(radius: .fixed(0))
            #endif
        }
        set {
            viewCornerConfigurations[ObjectIdentifier(self)] = newValue
            #if os(Linux)
            if let fixedRadius = newValue.quillUniformFixedRadius {
                layer.cornerRadius = fixedRadius
            }
            #endif
        }
    }
}

#endif // !os(iOS)
