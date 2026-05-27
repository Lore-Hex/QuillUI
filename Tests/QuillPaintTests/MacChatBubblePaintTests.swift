import Foundation
import Testing
@testable import QuillPaint

@Suite("MacChatBubblePaint chrome rendering")
struct MacChatBubblePaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 220, height: 52)

    @Test("User bubbles use accent fill, 16pt radius, and trailing alignment")
    func userBubbleChrome() {
        let ctx = RecordingPaintContext()
        MacChatBubblePaint(sender: .user).paint(into: ctx, frame: frame, state: .normal)

        #expect(MacChatBubbleSender.user.alignment == .trailing)
        #expect(MacMetrics.ChatBubble.cornerRadius == 16)
        #expect(MacMetrics.ChatBubble.horizontalPadding == 12)
        #expect(MacMetrics.ChatBubble.verticalPadding == 8)
        #expect(ctx.calls.count == 1)

        guard case let .fillRoundedRect(rect, radius, color) = ctx.calls.first else {
            Issue.record("Expected user bubble to draw one rounded fill")
            return
        }
        #expect(rect == frame)
        #expect(radius == MacMetrics.ChatBubble.cornerRadius)
        #expect(color == MacColors.chatBubbleUserFill)
    }

    @Test("Assistant bubbles use control fill and leading alignment")
    func assistantBubbleChrome() {
        let ctx = RecordingPaintContext()
        MacChatBubblePaint(sender: .assistant).paint(into: ctx, frame: frame, state: .normal)

        #expect(MacChatBubbleSender.assistant.alignment == .leading)
        #expect(ctx.calls.count == 1)

        guard case let .fillRoundedRect(rect, radius, color) = ctx.calls.first else {
            Issue.record("Expected assistant bubble to draw one rounded fill")
            return
        }
        #expect(rect == frame)
        #expect(radius == MacMetrics.ChatBubble.cornerRadius)
        #expect(color == MacColors.chatBubbleAssistantFill)
    }

    @Test("Pressed user bubble overlays the standard pressed darkening")
    func pressedUserBubbleOverlay() {
        let ctx = RecordingPaintContext()
        MacChatBubblePaint(sender: .user).paint(
            into: ctx,
            frame: frame,
            state: PaintControlState(isPressed: true)
        )

        #expect(ctx.calls.count == 2)
        guard case let .fillRoundedRect(_, radius, color) = ctx.calls.last else {
            Issue.record("Expected pressed overlay as the final call")
            return
        }
        #expect(radius == MacMetrics.ChatBubble.cornerRadius)
        #expect(color == MacColors.pressedOverlay)
    }
}
