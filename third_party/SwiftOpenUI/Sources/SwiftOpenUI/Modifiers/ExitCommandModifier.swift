/// A view that installs an Escape/cancel command for its subtree.
public struct ExitCommandView<Content: View>: View {
	public let content: Content
	public let action: (() -> Void)?

	public var body: Content { content }
}

extension View {
	/// Runs `action` when the platform cancel command is invoked.
	public func onExitCommand(perform action: (() -> Void)? = nil) -> ExitCommandView<Self> {
		ExitCommandView(content: self, action: action)
	}
}
