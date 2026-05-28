import Foundation
import QuillPaint

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics

/// A single entry in the Mac-reference manifest.
public struct ReferenceEntry {
    public let name: String
    public let control: PaintControl
    public let size: PaintSize
    public let state: PaintControlState

    public init(name: String, control: PaintControl, size: PaintSize, state: PaintControlState) {
        self.name = name
        self.control = control
        self.size = size
        self.state = state
    }
}

/// The canonical list of controls and states that define the "macOS look"
/// for QuillPaint.
///
/// Both the `quill-render-mac-references` tool and `MacReferenceGoldenTests`
/// use this list to ensure they stay in sync.
public enum MacReferenceManifest {
    public static var entries: [ReferenceEntry] {
        let buttonSize = PaintSize(width: 80, height: 22)
        let wideButtonSize = PaintSize(width: 160, height: 22)
        let sidebarRowSize = PaintSize(width: 220, height: 44)
        let chatBubbleSize = PaintSize(width: 220, height: 52)
        let verticalScrollerSize = PaintSize(width: 12, height: 120)
        let horizontalScrollerSize = PaintSize(width: 120, height: 12)

        return [
            ReferenceEntry(
                name: "button-normal",
                control: MacButtonPaint(),
                size: buttonSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "button-pressed",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isPressed: true)
            ),
            ReferenceEntry(
                name: "button-focused",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "button-hovered",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isHovered: true)
            ),
            ReferenceEntry(
                name: "button-disabled",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "button-default",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isDefault: true)
            ),
            ReferenceEntry(
                name: "button-default-pressed",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isPressed: true, isDefault: true)
            ),
            ReferenceEntry(
                name: "button-wide-normal",
                control: MacButtonPaint(),
                size: wideButtonSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "button-wide-focused-default",
                control: MacButtonPaint(),
                size: wideButtonSize,
                state: PaintControlState(isFocused: true, isDefault: true)
            ),
            ReferenceEntry(
                name: "button-labeled-normal",
                control: MacButtonPaint(label: "OK"),
                size: buttonSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "button-labeled-pressed",
                control: MacButtonPaint(label: "OK"),
                size: buttonSize,
                state: PaintControlState(isPressed: true)
            ),
            ReferenceEntry(
                name: "button-labeled-disabled",
                control: MacButtonPaint(label: "OK"),
                size: buttonSize,
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "button-labeled-default",
                control: MacButtonPaint(label: "OK"),
                size: buttonSize,
                state: PaintControlState(isDefault: true)
            ),
            ReferenceEntry(
                name: "button-wide-labeled-normal",
                control: MacButtonPaint(label: "Cancel"),
                size: wideButtonSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "button-wide-labeled-focused-default",
                control: MacButtonPaint(label: "Continue"),
                size: wideButtonSize,
                state: PaintControlState(isFocused: true, isDefault: true)
            ),
            ReferenceEntry(
                name: "sidebar-row-normal",
                control: MacListRowPaint(),
                size: sidebarRowSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "sidebar-row-hovered",
                control: MacListRowPaint(),
                size: sidebarRowSize,
                state: PaintControlState(isHovered: true)
            ),
            ReferenceEntry(
                name: "sidebar-row-selected",
                control: MacListRowPaint(),
                size: sidebarRowSize,
                state: PaintControlState(isSelected: true)
            ),
            ReferenceEntry(
                name: "textfield-normal",
                control: MacTextFieldPaint(),
                size: PaintSize(width: 140, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "textfield-focused",
                control: MacTextFieldPaint(),
                size: PaintSize(width: 140, height: 22),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "textfield-disabled",
                control: MacTextFieldPaint(),
                size: PaintSize(width: 140, height: 22),
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "textfield-wide-normal",
                control: MacTextFieldPaint(),
                size: PaintSize(width: 240, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "windowchrome-focused",
                control: MacWindowChromePaint(),
                size: PaintSize(width: 400, height: 28),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "windowchrome-unfocused",
                control: MacWindowChromePaint(),
                size: PaintSize(width: 400, height: 28),
                state: PaintControlState(isFocused: false)
            ),
            ReferenceEntry(
                name: "windowchrome-focused-hovered-traffic-lights",
                control: MacWindowChromePaint(),
                size: PaintSize(width: 400, height: 28),
                state: PaintControlState(isFocused: true, isHoveringTrafficLights: true)
            ),
            ReferenceEntry(
                name: "windowchrome-with-title",
                control: MacWindowChromePaint(title: "My Window"),
                size: PaintSize(width: 400, height: 28),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "chat-bubble-user-normal",
                control: MacChatBubblePaint(sender: .user),
                size: chatBubbleSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "chat-bubble-assistant-normal",
                control: MacChatBubblePaint(sender: .assistant),
                size: chatBubbleSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "chat-bubble-user-pressed",
                control: MacChatBubblePaint(sender: .user),
                size: chatBubbleSize,
                state: PaintControlState(isPressed: true)
            ),
            ReferenceEntry(
                name: "scroller-vertical-normal",
                control: MacScrollerPaint(orientation: .vertical, progress: 0.35, coverage: 0.3),
                size: verticalScrollerSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "scroller-vertical-hovered",
                control: MacScrollerPaint(orientation: .vertical, progress: 0.35, coverage: 0.3),
                size: verticalScrollerSize,
                state: PaintControlState(isHovered: true)
            ),
            ReferenceEntry(
                name: "scroller-horizontal-normal",
                control: MacScrollerPaint(orientation: .horizontal, progress: 0.35, coverage: 0.3),
                size: horizontalScrollerSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "scroller-vertical-full-coverage",
                control: MacScrollerPaint(orientation: .vertical, progress: 1, coverage: 1),
                size: verticalScrollerSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "slider-horizontal-mid",
                control: MacSliderPaint(orientation: .horizontal, progress: 0.5),
                size: PaintSize(width: 120, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "slider-horizontal-focused",
                control: MacSliderPaint(orientation: .horizontal, progress: 0.5),
                size: PaintSize(width: 120, height: 22),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "slider-vertical-mid",
                control: MacSliderPaint(orientation: .vertical, progress: 0.5),
                size: PaintSize(width: 22, height: 120),
                state: .normal
            ),
            ReferenceEntry(
                name: "slider-disabled",
                control: MacSliderPaint(orientation: .horizontal, progress: 0.5),
                size: PaintSize(width: 120, height: 22),
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "switch-off-normal",
                control: MacSwitchPaint(isOn: false),
                size: PaintSize(width: MacMetrics.Switch.width, height: MacMetrics.Switch.height),
                state: .normal
            ),
            ReferenceEntry(
                name: "switch-on-normal",
                control: MacSwitchPaint(isOn: true),
                size: PaintSize(width: MacMetrics.Switch.width, height: MacMetrics.Switch.height),
                state: .normal
            ),
            ReferenceEntry(
                name: "switch-on-disabled",
                control: MacSwitchPaint(isOn: true),
                size: PaintSize(width: MacMetrics.Switch.width, height: MacMetrics.Switch.height),
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "checkbox-off-normal",
                control: MacCheckboxPaint(value: .off),
                size: PaintSize(width: MacMetrics.Checkbox.size, height: MacMetrics.Checkbox.size),
                state: .normal
            ),
            ReferenceEntry(
                name: "checkbox-on-normal",
                control: MacCheckboxPaint(value: .on),
                size: PaintSize(width: MacMetrics.Checkbox.size, height: MacMetrics.Checkbox.size),
                state: .normal
            ),
            ReferenceEntry(
                name: "checkbox-mixed-normal",
                control: MacCheckboxPaint(value: .mixed),
                size: PaintSize(width: MacMetrics.Checkbox.size, height: MacMetrics.Checkbox.size),
                state: .normal
            ),
            ReferenceEntry(
                name: "checkbox-on-focused",
                control: MacCheckboxPaint(value: .on),
                size: PaintSize(width: MacMetrics.Checkbox.size, height: MacMetrics.Checkbox.size),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "radio-off-normal",
                control: MacRadioButtonPaint(),
                size: PaintSize(width: 16, height: 16),
                state: .normal
            ),
            ReferenceEntry(
                name: "radio-on-normal",
                control: MacRadioButtonPaint(),
                size: PaintSize(width: 16, height: 16),
                state: PaintControlState(isSelected: true)
            ),
            ReferenceEntry(
                name: "radio-on-focused",
                control: MacRadioButtonPaint(),
                size: PaintSize(width: 16, height: 16),
                state: PaintControlState(isFocused: true, isSelected: true)
            ),
            ReferenceEntry(
                name: "searchfield-normal",
                control: MacSearchFieldPaint(),
                size: PaintSize(width: 140, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "searchfield-focused",
                control: MacSearchFieldPaint(),
                size: PaintSize(width: 140, height: 22),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "searchfield-disabled",
                control: MacSearchFieldPaint(),
                size: PaintSize(width: 140, height: 22),
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "searchfield-wide-normal",
                control: MacSearchFieldPaint(),
                size: PaintSize(width: 240, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "progressbar-empty",
                control: MacProgressBarPaint(progress: 0),
                size: PaintSize(width: 120, height: MacMetrics.ProgressBar.regularHeight),
                state: .normal
            ),
            ReferenceEntry(
                name: "progressbar-half",
                control: MacProgressBarPaint(progress: 0.5),
                size: PaintSize(width: 120, height: MacMetrics.ProgressBar.regularHeight),
                state: .normal
            ),
            ReferenceEntry(
                name: "progressbar-full",
                control: MacProgressBarPaint(progress: 1.0),
                size: PaintSize(width: 120, height: MacMetrics.ProgressBar.regularHeight),
                state: .normal
            ),
            ReferenceEntry(
                name: "segmented-first-selected",
                control: MacSegmentedControlPaint(segments: ["One", "Two", "Three"], selectedIndex: 0),
                size: PaintSize(width: 150, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "segmented-middle-selected",
                control: MacSegmentedControlPaint(segments: ["One", "Two", "Three"], selectedIndex: 1),
                size: PaintSize(width: 150, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "segmented-focused",
                control: MacSegmentedControlPaint(segments: ["One", "Two", "Three"], selectedIndex: 0),
                size: PaintSize(width: 150, height: 22),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "segmented-disabled",
                control: MacSegmentedControlPaint(segments: ["One", "Two", "Three"], selectedIndex: 0),
                size: PaintSize(width: 150, height: 22),
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "popupbutton-normal",
                control: MacPopUpButtonPaint(label: "Selection"),
                size: PaintSize(width: 120, height: 22),
                state: .normal
            ),
            ReferenceEntry(
                name: "popupbutton-pressed",
                control: MacPopUpButtonPaint(label: "Selection"),
                size: PaintSize(width: 120, height: 22),
                state: PaintControlState(isPressed: true)
            ),
            ReferenceEntry(
                name: "popupbutton-focused",
                control: MacPopUpButtonPaint(label: "Selection"),
                size: PaintSize(width: 120, height: 22),
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "spinner-normal",
                control: MacSpinnerPaint(),
                size: PaintSize(width: MacMetrics.Spinner.regularSize, height: MacMetrics.Spinner.regularSize),
                state: .normal
            ),
            ReferenceEntry(
                name: "spinner-disabled",
                control: MacSpinnerPaint(),
                size: PaintSize(width: MacMetrics.Spinner.regularSize, height: MacMetrics.Spinner.regularSize),
                state: PaintControlState(isDisabled: true)
            )
        ]
    }
}
#endif
