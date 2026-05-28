import Foundation

/// Cross-cutting state every drawable control consumes. Extending this
/// stays backward-compatible: existing controls ignore new fields, and
/// new controls can opt into using them. Keep additions narrow — control
/// shape (corner radius, font, accent color) lives on per-control style
/// types, not here.
public struct PaintControlState: Equatable, Hashable, Sendable {
    public var isPressed: Bool
    public var isFocused: Bool
    public var isDisabled: Bool
    public var isHovered: Bool
    public var isDefault: Bool
    /// Specifically for MacWindowChromePaint: true if the mouse is hovering
    /// over the traffic lights region.
    public var isHoveringTrafficLights: Bool
    /// True if the control is in a selected state (e.g. a selected sidebar row).
    public var isSelected: Bool

    public init(
        isPressed: Bool = false,
        isFocused: Bool = false,
        isDisabled: Bool = false,
        isHovered: Bool = false,
        isDefault: Bool = false,
        isHoveringTrafficLights: Bool = false,
        isSelected: Bool = false
    ) {
        self.isPressed = isPressed
        self.isFocused = isFocused
        self.isDisabled = isDisabled
        self.isHovered = isHovered
        self.isDefault = isDefault
        self.isHoveringTrafficLights = isHoveringTrafficLights
        self.isSelected = isSelected
    }

    public static let normal = PaintControlState()
}

/// A control that knows how to paint itself into a `PaintContext`.
///
/// Controls are stateless value types; render state is passed in via
/// `PaintControlState`. This makes them trivially testable (no setup
/// teardown) and lets a single instance render once per frame across
/// however many backends are active.
public protocol PaintControl {
    /// Paint the control filling `frame`, in whatever state `state` describes.
    func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState)
}
