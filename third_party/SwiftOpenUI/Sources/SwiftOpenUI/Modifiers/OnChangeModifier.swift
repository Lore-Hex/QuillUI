/// Fires an action when the observed value changes between renders.
///
/// The action fires during rendering when the current value differs
/// from the value at the previous render. Uses a namespace + counter-keyed
/// dictionary to persist previous values. The counter is reset at the
/// start of each render pass by the ViewHost calling `resetOnChangeTracking()`.
public struct OnChangeView<Content: View, V: Equatable>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let action: (V) -> Void

    public init(content: Content, value: V, action: @escaping (V) -> Void) {
        self.content = content
        self.value = value
        self.action = action
    }

    public var body: Never { fatalError() }
}

/// Two-argument variant of `OnChangeView`: the action receives both
/// the old and the new value, matching SwiftUI's iOS 17+ form
/// `onChange(of:) { oldValue, newValue in … }`.
public struct OnChangeTwoArgView<Content: View, V: Equatable>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let action: (V, V) -> Void

    public init(content: Content, value: V, action: @escaping (V, V) -> Void) {
        self.content = content
        self.value = value
        self.action = action
    }

    public var body: Never { fatalError() }
}

/// `onChange(of:initial:)` is a distinct primitive so adding the newer SwiftUI
/// overload does not change the stored layout of the original public view type.
public struct InitialOnChangeView<Content: View, V: Equatable>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let initial: Bool
    public let action: (V) -> Void

    public init(content: Content, value: V, initial: Bool, action: @escaping (V) -> Void) {
        self.content = content
        self.value = value
        self.initial = initial
        self.action = action
    }

    public var body: Never { fatalError() }
}

public struct InitialOnChangeTwoArgView<Content: View, V: Equatable>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let initial: Bool
    public let action: (V, V) -> Void

    public init(content: Content, value: V, initial: Bool, action: @escaping (V, V) -> Void) {
        self.content = content
        self.value = value
        self.initial = initial
        self.action = action
    }

    public var body: Never { fatalError() }
}

extension View {
    /// Adds an action to perform when the given value changes.
    /// Single-argument form — matches SwiftUI's pre-iOS-17 API.
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> OnChangeView<Self, V> {
        OnChangeView(content: self, value: value, action: action)
    }

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping () -> Void
    ) -> InitialOnChangeView<Self, V> {
        InitialOnChangeView(content: self, value: value, initial: initial) { _ in action() }
    }

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping (V) -> Void
    ) -> InitialOnChangeView<Self, V> {
        InitialOnChangeView(content: self, value: value, initial: initial, action: action)
    }

    /// Adds an action to perform when the given value changes.
    /// Two-argument form — matches SwiftUI's iOS 17+ API where the
    /// closure receives both the previous and the new value.
    ///
    /// ```swift
    /// .onChange(of: appState.selectedAction) { oldValue, newValue in
    ///     // side effects based on the transition
    /// }
    /// ```
    @_disfavoredOverload
    public func onChange<V: Equatable>(
        of value: V,
        _ action: @escaping (V, V) -> Void
    ) -> OnChangeTwoArgView<Self, V> {
        OnChangeTwoArgView(content: self, value: value, action: action)
    }

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping (V, V) -> Void
    ) -> InitialOnChangeTwoArgView<Self, V> {
        InitialOnChangeTwoArgView(content: self, value: value, initial: initial, action: action)
    }
}

// MARK: - onChange value tracking

/// Global counter to generate unique keys for onChange instances
/// within a single render pass. Reset at the start of each rebuild.
/// Not thread-safe — works for single-threaded rendering only.
private var _onChangeCounter: Int = 0

private struct OnChangeStorageKey: Hashable {
    let namespace: String
    let index: Int
}

/// Global storage for previous onChange values, keyed by backend-provided
/// render namespace plus render-pass counter. Backends call
/// `onChangeCheckAndFire` during rendering.
private var _onChangePreviousValues: [OnChangeStorageKey: Any] = [:]

/// Reset the onChange counter at the start of a render pass.
/// Does NOT clear stored values — they persist across rebuilds.
public func resetOnChangeTracking() {
    _onChangeCounter = 0
}

/// Clear all onChange state. Called between tests or when a host is destroyed.
public func clearOnChangeState() {
    _onChangeCounter = 0
    _onChangePreviousValues.removeAll()
}

/// Check if a value changed since last render and fire the action if so.
/// Called by backend renderers for each OnChangeView encountered.
/// Returns the current counter key (for testing).
@discardableResult
public func onChangeCheckAndFire<V: Equatable>(
    namespace: String = "default",
    value: V,
    action: (V) -> Void
) -> Int {
    onChangeCheckAndFire(
        namespace: namespace,
        value: value,
        initial: false,
        action: action
    )
}

@discardableResult
public func onChangeCheckAndFire<V: Equatable>(
    namespace: String = "default",
    value: V,
    initial: Bool,
    action: (V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(value)
        }
    } else if initial {
        action(value)
    }
    // Store current value for next render pass
    _onChangePreviousValues[storageKey] = value

    return key
}

/// Two-argument variant of `onChangeCheckAndFire`. The action is
/// called with `(oldValue, newValue)` when the value has changed
/// since the previous render. Uses the same counter-keyed storage
/// as the single-argument form, so the two variants share the
/// render-pass reset contract.
@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    namespace: String = "default",
    value: V,
    action: (V, V) -> Void
) -> Int {
    onChangeCheckAndFireTwoArg(
        namespace: namespace,
        value: value,
        initial: false,
        action: action
    )
}

@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    namespace: String = "default",
    value: V,
    initial: Bool,
    action: (V, V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(previous, value)
        }
    } else if initial {
        action(value, value)
    }
    _onChangePreviousValues[storageKey] = value

    return key
}
