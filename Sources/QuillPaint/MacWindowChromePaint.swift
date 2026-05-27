import Foundation

/// Paints a macOS-style window titlebar (chrome) into a `PaintContext`.
///
/// Draws the standard traffic-light buttons (close, minimize, maximize)
/// at the top-left and an optional centered title.
public struct MacWindowChromePaint: PaintControl {
    public var title: String?

    public init(title: String? = nil) {
        self.title = title
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // 1. Titlebar background
        context.fillRect(frame, color: MacColors.windowChromeBackground)

        // 2. Bottom border
        let borderY = frame.maxY - 1
        context.strokeLine(
            from: PaintPoint(x: frame.minX, y: borderY),
            to: PaintPoint(x: frame.maxX, y: borderY),
            color: MacColors.windowChromeBorderBottom,
            lineWidth: 1
        )

        // 3. Traffic lights
        let diameter = MacMetrics.WindowChrome.trafficLightDiameter
        let spacing = MacMetrics.WindowChrome.trafficLightSpacing
        let padding = MacMetrics.WindowChrome.horizontalPadding
        let centerY = frame.minY + (MacMetrics.WindowChrome.titlebarHeight / 2)
        let circleY = centerY - (diameter / 2)
        let cornerRadius = diameter / 2

        let closeRect = PaintRect(x: frame.minX + padding, y: circleY, width: diameter, height: diameter)
        let minimizeRect = PaintRect(x: closeRect.maxX + spacing, y: circleY, width: diameter, height: diameter)
        let maximizeRect = PaintRect(x: minimizeRect.maxX + spacing, y: circleY, width: diameter, height: diameter)

        if state.isFocused {
            context.fillRoundedRect(closeRect, cornerRadius: cornerRadius, color: MacColors.windowCloseRed)
            context.fillRoundedRect(minimizeRect, cornerRadius: cornerRadius, color: MacColors.windowMinimizeYellow)
            context.fillRoundedRect(maximizeRect, cornerRadius: cornerRadius, color: MacColors.windowMaximizeGreen)
        } else {
            let unfocusedColor = MacColors.windowChromeUnfocusedDot
            context.fillRoundedRect(closeRect, cornerRadius: cornerRadius, color: unfocusedColor)
            context.fillRoundedRect(minimizeRect, cornerRadius: cornerRadius, color: unfocusedColor)
            context.fillRoundedRect(maximizeRect, cornerRadius: cornerRadius, color: unfocusedColor)
        }

        // 4. (Optional) Title stub
        // TODO: Real text rendering once typography ships.
        if title != nil {
            // Stub: paint a small placeholder region in the center
            let titleWidth: Double = 60
            let titleHeight: Double = 12
            let titleRect = PaintRect(
                x: frame.midX - (titleWidth / 2),
                y: centerY - (titleHeight / 2),
                width: titleWidth,
                height: titleHeight
            )
            // We use a very light grey to indicate where text will go
            context.fillRoundedRect(titleRect, cornerRadius: 2, color: MacColors.separator)
        }

        // 5. Hover glyphs (if hovering traffic lights)
        if state.isHoveringTrafficLights {
            // macOS draws subtle symbols (x, -, +) inside the circles on hover.
            // For now, we just indicate their presence by drawing a small
            // inner dot or similar if we wanted to be fancy, but the spec
            // just says "shows the close/minimize/maximize glyphs inside".
            // Since we don't have path drawing or icons yet, we'll skip
            // the actual glyphs or use lines if possible.
            
            // Close: X (two diagonal lines)
            let inset: Double = 3
            context.strokeLine(
                from: PaintPoint(x: closeRect.minX + inset, y: closeRect.minY + inset),
                to: PaintPoint(x: closeRect.maxX - inset, y: closeRect.maxY - inset),
                color: PaintColor(r: 0, g: 0, b: 0, a: 128),
                lineWidth: 1
            )
            context.strokeLine(
                from: PaintPoint(x: closeRect.maxX - inset, y: closeRect.minY + inset),
                to: PaintPoint(x: closeRect.minX + inset, y: closeRect.maxY - inset),
                color: PaintColor(r: 0, g: 0, b: 0, a: 128),
                lineWidth: 1
            )

            // Minimize: - (horizontal line)
            context.strokeLine(
                from: PaintPoint(x: minimizeRect.minX + inset, y: minimizeRect.midY),
                to: PaintPoint(x: minimizeRect.maxX - inset, y: minimizeRect.midY),
                color: PaintColor(r: 0, g: 0, b: 0, a: 128),
                lineWidth: 1
            )

            // Maximize: + (well, macOS uses two triangles/arrows, but + is a good stub)
            // Actually, maximize is often an expansion icon. Let's do a small +
            context.strokeLine(
                from: PaintPoint(x: maximizeRect.minX + inset, y: maximizeRect.midY),
                to: PaintPoint(x: maximizeRect.maxX - inset, y: maximizeRect.midY),
                color: PaintColor(r: 0, g: 0, b: 0, a: 128),
                lineWidth: 1
            )
            context.strokeLine(
                from: PaintPoint(x: maximizeRect.midX, y: maximizeRect.minY + inset),
                to: PaintPoint(x: maximizeRect.midX, y: maximizeRect.maxY - inset),
                color: PaintColor(r: 0, g: 0, b: 0, a: 128),
                lineWidth: 1
            )
        }
    }
}
