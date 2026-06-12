/// A two-way reference to a value owned by a parent view's @State.
/// Created via `$stateName` (State's projectedValue).
///
/// Binding lifetime is tied to the parent view's render cycle.
/// The get/set closures capture the parent's StateStorage, so mutations
/// flow through the same lock + scheduling path as direct @State writes.
public struct BindingIdentity: Hashable, CustomStringConvertible {
    private let objectIdentifier: ObjectIdentifier
    private let discriminator: Int

    public init(objectIdentifier: ObjectIdentifier, discriminator: Int = 0) {
        self.objectIdentifier = objectIdentifier
        self.discriminator = discriminator
    }

    public var description: String {
        "\(objectIdentifier):\(discriminator)"
    }
}

@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void
    public let quillUIIdentity: BindingIdentity?

    public init(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void,
        quillUIIdentity: BindingIdentity? = nil
    ) {
        self.get = get
        self.set = set
        self.quillUIIdentity = quillUIIdentity
    }

    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    /// Projects self so `$bindingName` returns a `Binding<Value>` (SwiftUI parity).
    public var projectedValue: Binding<Value> { self }

    /// Allows SwiftUI's binding-collection closure spelling:
    /// `ForEach($items) { $item in ... }`.
    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    /// Creates a binding with an immutable value (SwiftUI-compatible).
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// Projects a child binding to a property of `Value` (SwiftUI parity):
    /// enables `$state.property` to yield a two-way `Binding` to that property.
    /// A single `WritableKeyPath` subscript covers both value types and
    /// reference types (`ReferenceWritableKeyPath` is a subtype), so it also
    /// drives `$store.property` where `store` is an `@State`-held object.
    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        let parentGet = get
        let parentSet = set
        return Binding<Subject>(
            get: { parentGet()[keyPath: keyPath] },
            set: { newValue in
                var value = parentGet()
                value[keyPath: keyPath] = newValue
                parentSet(value)
            }
        )
    }
}
