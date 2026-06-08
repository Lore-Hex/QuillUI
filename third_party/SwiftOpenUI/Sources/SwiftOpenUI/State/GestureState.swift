/// Linux stand-in for SwiftUI's `@GestureState`. On Apple platforms the value is
/// driven by an in-flight gesture and resets when it ends; on GTK there is no such
/// gesture pipeline, so the wrapped value simply stays at its initial value
/// (gesture-driven transforms like `scaleEffect(zoom)` degrade to identity).
@propertyWrapper
public struct GestureState<Value> {
    private let initial: Value

    public init(wrappedValue: Value) {
        self.initial = wrappedValue
    }

    public init(initialValue: Value) {
        self.initial = initialValue
    }

    public var wrappedValue: Value { initial }

    public var projectedValue: GestureState<Value> { self }
}
