import Foundation

/// Paints a macOS-style `NSSegmentedControl` into a `PaintContext`.
///
/// Follows the pattern of `MacButtonPaint`, rendering a multi-segment control.
/// Values match macOS 14 Sonoma at 1x.
public struct MacSegmentedControlPaint: PaintControl {
    public var segments: [String]
    public var selectedIndex: Int?

    public init(segments: [String] = ["One", "Two", "Three"], selectedIndex: Int? = 0) {
        self.segments = segments
        self.selectedIndex = selectedIndex
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // 1. Focus ring (behind the control)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.FocusRing.outset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: MacMetrics.SegmentedControl.cornerRadius + 2,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // 2. Main background (the "track")
        let backgroundColor: PaintColor
        if state.isDisabled {
            backgroundColor = PaintColor(
                red: MacColors.control.red,
                green: MacColors.control.green,
                blue: MacColors.control.blue,
                alpha: 0.5
            )
        } else {
            backgroundColor = MacColors.control
        }

        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.SegmentedControl.cornerRadius,
            color: backgroundColor
        )

        // 3. Outer border
        context.strokeRoundedRect(
            frame,
            cornerRadius: MacMetrics.SegmentedControl.cornerRadius,
            color: MacColors.separator,
            lineWidth: MacMetrics.SegmentedControl.borderLineWidth
        )

        if segments.isEmpty { return }

        let segmentWidth = frame.size.width / Double(segments.count)

        // 4. Selection fills and separators
        for (index, _) in segments.enumerated() {
            let segmentFrame = PaintRect(
                x: frame.origin.x + Double(index) * segmentWidth,
                y: frame.origin.y,
                width: segmentWidth,
                height: frame.size.height
            )

            let isSelected = (index == selectedIndex)

            if isSelected {
                let fill: PaintColor
                if state.isDisabled {
                    let base = state.isDefault ? MacColors.accent : MacColors.controlBackground
                    fill = PaintColor(red: base.red, green: base.green, blue: base.blue, alpha: 0.5)
                } else {
                    fill = state.isDefault ? MacColors.accent : MacColors.controlBackground
                }

                let selectionInset: Double = 1
                let selectionFrame = segmentFrame.insetBy(dx: selectionInset, dy: selectionInset)
                context.fillRoundedRect(
                    selectionFrame,
                    cornerRadius: MacMetrics.SegmentedControl.cornerRadius - 1,
                    color: fill
                )
            }

            if index < segments.count - 1 {
                let nextIsSelected = (index + 1 == selectedIndex)
                if !isSelected && !nextIsSelected {
                    let separatorX = segmentFrame.maxX
                    context.strokeLine(
                        from: PaintPoint(x: separatorX, y: segmentFrame.minY + 4),
                        to: PaintPoint(x: separatorX, y: segmentFrame.maxY - 4),
                        color: MacColors.separator,
                        lineWidth: MacMetrics.SegmentedControl.separatorLineWidth
                    )
                }
            }
        }

        // 5. Labels
        for (index, label) in segments.enumerated() {
            let segmentFrame = PaintRect(
                x: frame.origin.x + Double(index) * segmentWidth,
                y: frame.origin.y,
                width: segmentWidth,
                height: frame.size.height
            )

            let isSelected = (index == selectedIndex)
            let font = MacFonts.controlLabel
            let labelSize = PaintTextMetrics.measure(label, font: font)
            let labelPoint = PaintPoint(
                x: segmentFrame.midX - labelSize.width / 2,
                y: segmentFrame.midY - labelSize.height / 2 + MacMetrics.SegmentedControl.labelVerticalOpticalOffset
            )

            let labelColor: PaintColor
            if state.isDisabled {
                labelColor = MacColors.disabledControlText
            } else if isSelected && state.isDefault {
                labelColor = MacColors.defaultButtonText
            } else {
                labelColor = MacColors.controlText
            }

            context.drawText(label, at: labelPoint, font: font, color: labelColor)
        }
    }
}
