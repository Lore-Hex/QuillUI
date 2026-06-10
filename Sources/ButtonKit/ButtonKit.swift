import SwiftUI

private final class AsyncButtonActionBox: @unchecked Sendable {
    let action: () async throws -> Void

    init(_ action: @escaping () async throws -> Void) {
        self.action = action
    }
}

public struct AsyncButton<Label: View>: View {
    public typealias Action = () async throws -> Void

    private let actionBox: AsyncButtonActionBox
    private let label: Label

    public init(action: @escaping Action, @ViewBuilder label: () -> Label) {
        self.actionBox = AsyncButtonActionBox(action)
        self.label = label()
    }

    public var body: some View {
        let actionBox = actionBox
        Button(action: {
            Task {
                try? await actionBox.action()
            }
        }) {
            label
        }
    }
}

public enum AsyncButtonStyle: Equatable {
    case none
}

public extension View {
    func asyncButtonStyle(_ style: AsyncButtonStyle) -> Self {
        _ = style
        return self
    }

    func disabledWhenLoading() -> Self {
        self
    }
}
