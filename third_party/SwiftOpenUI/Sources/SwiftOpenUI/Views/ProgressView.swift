import Foundation

/// A view that shows progress toward completion.
public struct ProgressView: View {
    public typealias Body = Never

    public let value: Double?
    public let total: Double

    /// Create a determinate progress view (0.0 to total).
    public init(value: Double, total: Double = 1.0) {
        self.value = value
        self.total = total
    }

    public init(_ progress: Progress) {
        self.value = progress.fractionCompleted
        self.total = 1.0
    }

    public init<Label: View>(@ViewBuilder label: () -> Label) {
        _ = label()
        self.value = nil
        self.total = 1.0
    }

    public init<Label: View, CurrentValueLabel: View>(
        value: Double?,
        total: Double = 1.0,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        _ = label()
        _ = currentValueLabel()
        self.value = value
        self.total = total
    }

    public init<Label: View>(value: Double, total: Double = 1.0, @ViewBuilder label: () -> Label) {
        _ = label()
        self.value = value
        self.total = total
    }

    /// Create an indeterminate progress view.
    public init() {
        self.value = nil
        self.total = 1.0
    }

    public var body: Never { fatalError("ProgressView is a primitive view") }
}
