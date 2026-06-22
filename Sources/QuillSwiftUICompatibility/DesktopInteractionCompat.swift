import Foundation
import SwiftOpenUI

public enum MoveCommandDirection: Hashable {
    case up
    case down
    case left
    case right
}

public struct MoveCommandView<Content: View>: View {
    public let content: Content
    public let action: (MoveCommandDirection) -> Void

    public init(content: Content, action: @escaping (MoveCommandDirection) -> Void) {
        self.content = content
        self.action = action
    }

    public var body: some View {
        content
    }
}

public struct AccessibilityIdentifierView<Content: View>: View {
    public let content: Content
    public let identifier: String

    public init(content: Content, identifier: String) {
        self.content = content
        self.identifier = identifier
    }

    public var body: some View {
        content
    }
}

public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)
}

public extension View {
    func onMoveCommand(
        perform action: @escaping (MoveCommandDirection) -> Void
    ) -> MoveCommandView<Self> {
        MoveCommandView(content: self, action: action)
    }

    func accessibilityIdentifier(_ identifier: String) -> AccessibilityIdentifierView<Self> {
        AccessibilityIdentifierView(content: self, identifier: identifier)
    }

    func popover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge,
        @ViewBuilder content: () -> PopoverContent
    ) -> PopoverView<Self, PopoverContent> {
        _ = arrowEdge
        return popover(isPresented: isPresented, content: content)
    }

    func popover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor,
        arrowEdge: Edge = .top,
        @ViewBuilder content: () -> PopoverContent
    ) -> PopoverView<Self, PopoverContent> {
        _ = attachmentAnchor
        _ = arrowEdge
        return popover(isPresented: isPresented, content: content)
    }
}
