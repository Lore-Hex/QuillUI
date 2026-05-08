import SwiftUI

public struct ActivityIndicatorView: View {
    public enum IndicatorType: Sendable {
        case rotatingDots(count: Int)
        case growingCircle
    }

    private let isVisible: Binding<Bool>
    private let type: IndicatorType

    public init(isVisible: Binding<Bool>, type: IndicatorType) {
        self.isVisible = isVisible
        self.type = type
    }

    public var body: some View {
        Group {
            if isVisible.wrappedValue {
                switch type {
                case .rotatingDots(let count):
                    Text(String(repeating: ".", count: max(1, count)))
                case .growingCircle:
                    Circle()
                        .fill(Color.primary.opacity(0.7))
                }
            } else {
                EmptyView()
            }
        }
    }
}

