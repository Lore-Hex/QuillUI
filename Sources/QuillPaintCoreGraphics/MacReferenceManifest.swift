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
            )
        ]
    }
}
#endif
