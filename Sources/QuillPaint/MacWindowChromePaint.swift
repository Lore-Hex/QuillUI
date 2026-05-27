import Foundation

/// Paints a macOS-style `NSWindow` titlebar with traffic-light controls.
///
/// Text is intentionally not rendered yet. When `title` is present, the
/// painter emits a centered placeholder region so fixture coverage locks down
/// the title placement contract before the typography pipeline arrives.
public struct MacWindowChromePaint: PaintControl {
    public var title: String?

    public init(title: String? = nil) {
        self.title = title
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        context.fillRect(frame, color: MacColors.windowChromeBackground)

        paintTrafficLights(into: context, frame: frame, state: state)

        if title != nil, let titleFrame = Self.titleStubFrame(in: frame) {
            context.fillRoundedRect(
                titleFrame,
                cornerRadius: MacMetrics.WindowChrome.titleStubCornerRadius,
                color: Self.titleStubColor
            )
        }

        let borderY = frame.maxY - MacMetrics.WindowChrome.borderLineWidth / 2
        context.strokeLine(
            from: PaintPoint(x: frame.minX, y: borderY),
            to: PaintPoint(x: frame.maxX, y: borderY),
            color: MacColors.windowChromeBorderBottom,
            lineWidth: MacMetrics.WindowChrome.borderLineWidth
        )
    }

    static let titleStubColor = PaintColor(r: 0, g: 0, b: 0, a: 46)
    static let trafficLightGlyphColor = PaintColor(r: 0, g: 0, b: 0, a: 120)

    static func titleStubFrame(in frame: PaintRect) -> PaintRect? {
        let width = min(MacMetrics.WindowChrome.titleStubMaxWidth, frame.size.width)
        guard width > 0, MacMetrics.WindowChrome.titleStubHeight > 0 else {
            return nil
        }

        return PaintRect(
            x: frame.midX - width / 2,
            y: frame.midY - MacMetrics.WindowChrome.titleStubHeight / 2,
            width: width,
            height: MacMetrics.WindowChrome.titleStubHeight
        )
    }

    private func paintTrafficLights(
        into context: PaintContext,
        frame: PaintRect,
        state: PaintControlState
    ) {
        let colors = Self.trafficLightColors(isFocused: state.isFocused)
        let frames = Self.trafficLightFrames(in: frame)

        for (index, dotFrame) in frames.enumerated() {
            context.fillRoundedRect(
                dotFrame,
                cornerRadius: MacMetrics.WindowChrome.trafficLightDiameter / 2,
                color: colors[index]
            )

            if state.isHoveringTrafficLights {
                paintGlyph(Self.trafficLightKinds[index], in: dotFrame, into: context)
            }
        }
    }

    static func trafficLightFrames(in frame: PaintRect) -> [PaintRect] {
        let diameter = MacMetrics.WindowChrome.trafficLightDiameter
        let step = diameter + MacMetrics.WindowChrome.buttonSpacing
        let circleY = frame.minY + (frame.size.height - diameter) / 2
        let firstX = frame.minX + MacMetrics.WindowChrome.horizontalPadding

        return (0..<3).map { index in
            PaintRect(
                x: firstX + Double(index) * step,
                y: circleY,
                width: diameter,
                height: diameter
            )
        }
    }

    static func trafficLightColors(isFocused: Bool) -> [PaintColor] {
        if !isFocused {
            return Array(repeating: MacColors.windowChromeUnfocusedDot, count: 3)
        }

        return [
            MacColors.windowCloseRed,
            MacColors.windowMinimizeYellow,
            MacColors.windowMaximizeGreen
        ]
    }

    private enum TrafficLightKind {
        case close
        case minimize
        case maximize
    }

    private static let trafficLightKinds: [TrafficLightKind] = [
        .close,
        .minimize,
        .maximize
    ]

    private func paintGlyph(_ kind: TrafficLightKind, in frame: PaintRect, into context: PaintContext) {
        let inset = MacMetrics.WindowChrome.trafficLightGlyphInset
        let left = frame.minX + inset
        let right = frame.maxX - inset
        let top = frame.minY + inset
        let bottom = frame.maxY - inset
        let midX = frame.midX
        let midY = frame.midY
        let color = Self.trafficLightGlyphColor
        let lineWidth = MacMetrics.WindowChrome.trafficLightGlyphLineWidth

        switch kind {
        case .close:
            context.strokeLine(
                from: PaintPoint(x: left, y: top),
                to: PaintPoint(x: right, y: bottom),
                color: color,
                lineWidth: lineWidth
            )
            context.strokeLine(
                from: PaintPoint(x: right, y: top),
                to: PaintPoint(x: left, y: bottom),
                color: color,
                lineWidth: lineWidth
            )

        case .minimize:
            context.strokeLine(
                from: PaintPoint(x: left, y: midY),
                to: PaintPoint(x: right, y: midY),
                color: color,
                lineWidth: lineWidth
            )

        case .maximize:
            context.strokeLine(
                from: PaintPoint(x: left, y: midY),
                to: PaintPoint(x: right, y: midY),
                color: color,
                lineWidth: lineWidth
            )
            context.strokeLine(
                from: PaintPoint(x: midX, y: top),
                to: PaintPoint(x: midX, y: bottom),
                color: color,
                lineWidth: lineWidth
            )
        }
    }
}
