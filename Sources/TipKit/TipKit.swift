import SwiftUI

public protocol Tip: Sendable {}

public struct TipView<T: Tip>: View {
    public init(_ tip: T) {}
    public var body: some View { EmptyView() }
}
