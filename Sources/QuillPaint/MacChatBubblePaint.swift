import Foundation

public enum MacChatBubbleAlignment: String, Equatable, Hashable, Sendable {
    case leading
    case trailing
}

public enum MacChatBubbleSender: String, CaseIterable, Equatable, Hashable, Sendable {
    case user
    case assistant

    public var alignment: MacChatBubbleAlignment {
        switch self {
        case .user:
            return .trailing
        case .assistant:
            return .leading
        }
    }
}

/// Paints Enchanted's macOS chat-bubble chrome into a `PaintContext`.
///
/// Text and role labels are deliberately not painted here. Hosts size the
/// bubble using `MacMetrics.ChatBubble` padding and overlay text content on top
/// of this rounded fill.
public struct MacChatBubblePaint: PaintControl {
    public var sender: MacChatBubbleSender

    public init(sender: MacChatBubbleSender) {
        self.sender = sender
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let cornerRadius = MacMetrics.ChatBubble.cornerRadius

        context.fillRoundedRect(
            frame,
            cornerRadius: cornerRadius,
            color: Self.fillColor(for: sender, state: state)
        )

        if state.isPressed && !state.isDisabled {
            context.fillRoundedRect(
                frame,
                cornerRadius: cornerRadius,
                color: MacColors.pressedOverlay
            )
        }
    }

    static func fillColor(for sender: MacChatBubbleSender, state: PaintControlState) -> PaintColor {
        let baseColor: PaintColor
        switch sender {
        case .user:
            baseColor = MacColors.chatBubbleUserFill
        case .assistant:
            baseColor = MacColors.chatBubbleAssistantFill
        }

        guard state.isDisabled else { return baseColor }
        return PaintColor(
            red: baseColor.red,
            green: baseColor.green,
            blue: baseColor.blue,
            alpha: baseColor.alpha * 0.5
        )
    }
}
