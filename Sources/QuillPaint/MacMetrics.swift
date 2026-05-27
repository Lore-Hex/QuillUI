import Foundation

/// macOS-exact metric tokens for QuillPaint controls.
///
/// Values are sourced from Apple's HIG and `Apple Sample Code` measurements
/// of `NSButton`, `NSTextField`, `NSScroller`, etc. on macOS 14 Sonoma at
/// 1x scale. The goal of `QuillPaint` is to render Linux controls visually
/// identical to these references; do not edit a value here without
/// measuring the corresponding NSControl pixel-by-pixel.
///
/// All units are paint units (1 paint unit = 1 point = 1/72 inch at 1x).
public enum MacMetrics {
    public enum Button {
        /// Corner radius of a standard `.bordered` `NSButton` at regular control size.
        public static let cornerRadius: Double = 5

        /// Inner padding inside the bordered chrome. Used for the focus ring
        /// inset and the hit target's text/image padding.
        public static let horizontalPadding: Double = 12
        public static let verticalPadding: Double = 4

        /// Height of a regular control size button. Mini and small are smaller.
        public static let regularHeight: Double = 22

        /// Line width of the bordered chrome's outline.
        public static let borderLineWidth: Double = 1

        /// Outset of the focus ring from the button's frame.
        public static let focusRingOutset: Double = 3
        public static let focusRingLineWidth: Double = 3
        public static let focusRingCornerRadiusAdjust: Double = 2
    }

    public enum TextField {
        /// Corner radius of a regular `.bezelStyle = .roundedBezel` text field.
        public static let cornerRadius: Double = 4
        public static let horizontalPadding: Double = 5
        public static let verticalPadding: Double = 3
        public static let regularHeight: Double = 22
        public static let borderLineWidth: Double = 1
    }

    public enum FocusRing {
        public static let lineWidth: Double = 3
        /// macOS focus rings have a soft outer halo; the line width above
        /// is the main visible stroke and corresponds to the highlight color
        /// at full opacity.
        public static let outset: Double = 3
    }

    public enum WindowChrome {
        /// Height of the standard macOS titlebar.
        public static let titlebarHeight: Double = 28

        /// Diameter of the traffic-light buttons (close, minimize, maximize).
        public static let trafficLightDiameter: Double = 12

        /// Horizontal spacing between the traffic-light buttons.
        public static let trafficLightSpacing: Double = 8

        /// Horizontal padding from the left edge of the window to the first traffic light.
        public static let horizontalPadding: Double = 20
    }
}

/// macOS system color tokens used by QuillPaint controls.
///
/// Values are the standard appearance ("Aqua") light-mode hexes. Dark mode
/// tokens are a follow-up iteration once the basic control set is rendering
/// correctly on Linux.
public enum MacColors {
    /// `NSColor.controlBackgroundColor` light mode — used for button chrome
    /// fill, text field fill.
    public static let controlBackground = PaintColor(r: 255, g: 255, b: 255)

    /// `NSColor.controlColor` light mode — slightly off-white for non-key
    /// chrome fills.
    public static let control = PaintColor(r: 246, g: 246, b: 246)

    /// `NSColor.separatorColor` light mode — used for control borders.
    public static let separator = PaintColor(r: 0, g: 0, b: 0, a: 24)

    /// `NSColor.controlAccentColor` — default blue (system accent). Apps
    /// can override per user preference.
    public static let accent = PaintColor(r: 0, g: 122, b: 255)

    /// Default-button highlight color when the button is the default action
    /// (the pulsing key button). Matches the accent in modern macOS.
    public static let defaultButtonFill = PaintColor(r: 0, g: 122, b: 255)

    /// Text inside a default button (white on accent).
    public static let defaultButtonText = PaintColor(r: 255, g: 255, b: 255)

    /// Standard button text (`NSColor.controlTextColor`).
    public static let controlText = PaintColor(r: 0, g: 0, b: 0, a: 217)

    /// Disabled control text.
    public static let disabledControlText = PaintColor(r: 0, g: 0, b: 0, a: 64)

    /// Focus ring color at ~50% alpha — approximates macOS' soft halo.
    public static let focusRing = PaintColor(red: 0, green: 122.0 / 255, blue: 255.0 / 255, alpha: 0.5)

    /// Pressed-state overlay color — a subtle darkening applied on top of
    /// the normal control fill while the mouse is down.
    public static let pressedOverlay = PaintColor(red: 0, green: 0, blue: 0, alpha: 0.08)

    /// Hovered-state overlay (rarely visible on macOS — buttons don't have
    /// strong hover states — but kept for hosts that emit it).
    public static let hoveredOverlay = PaintColor(red: 0, green: 0, blue: 0, alpha: 0.03)

    // MARK: - Window Chrome

    /// Traffic light "close" button color (focused).
    public static let windowCloseRed = PaintColor(r: 255, g: 95, b: 87)

    /// Traffic light "minimize" button color (focused).
    public static let windowMinimizeYellow = PaintColor(r: 254, g: 188, b: 46)

    /// Traffic light "maximize" button color (focused).
    public static let windowMaximizeGreen = PaintColor(r: 40, g: 200, b: 64)

    /// Background color for the window titlebar.
    public static let windowChromeBackground = PaintColor(r: 246, g: 246, b: 246)

    /// Bottom border of the window titlebar.
    public static let windowChromeBorderBottom = PaintColor(r: 0, g: 0, b: 0, a: 51)

    /// Color for traffic light dots when the window is unfocused.
    public static let windowChromeUnfocusedDot = PaintColor(r: 206, g: 206, b: 206)
}
