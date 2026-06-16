import Foundation

// MARK: - Preference / Anchor system
//
// `PreferenceKey` and `onPreferenceChange(_:perform:)` already live in
// `EnvironmentModifiers.swift`. This file adds the rest of SwiftUI's preference
// surface that Signal-iOS source relies on: the `Anchor<Value>` value type and
// its `Source` descriptions, `GeometryProxy`'s anchor subscript, and the
// `preference` / `anchorPreference` / `transformAnchorPreference` view
// modifiers.
//
// On Linux there is no layout-time preference propagation graph: these modifiers
// are inert wrappers that type-check and carry their stored values, but no value
// actually flows up the view tree at render time. They exist so that Signal-iOS
// source that defines and uses preference keys (e.g.
// `SignalUI/Appearance/SwiftUI/ScrollOffset.swift`) compiles unchanged.

// MARK: - Anchor

/// An opaque value derived from an anchor source and a particular view.
///
/// Mirrors SwiftUI's `struct Anchor<Value>`. On Linux the resolved value is
/// captured eagerly (there is no deferred layout pass), so an `Anchor` simply
/// boxes the geometry value it represents — or the zero value when produced
/// from a bare `Source` description with no resolution context.
public struct Anchor<Value> {
    /// The resolved geometry value this anchor represents.
    ///
    /// Internal: backends and `GeometryProxy`'s anchor subscript read this.
    public let value: Value

    public init(value: Value) {
        self.value = value
    }

    /// A type-erased geometry value used to derive an `Anchor`.
    ///
    /// Mirrors SwiftUI's `Anchor<Value>.Source`. It carries an optional concrete
    /// value (when one is known at creation time) plus a "kind" describing which
    /// part of the bounds the anchor refers to, so `geometry[anchor]` can return
    /// something deterministic even with no real layout pass.
    public struct Source {
        /// Describes which geometric feature a point/rect source refers to.
        public enum Kind {
            case unit(UnitPoint)
            case bounds
            case rect(CGRect)
            case point(CGPoint)
        }

        public let kind: Kind

        /// A concrete value, when known when the source was created.
        public let value: Value?

        public init(kind: Kind, value: Value? = nil) {
            self.kind = kind
            self.value = value
        }
    }
}

/// SwiftUI's `Anchor` is not itself `Equatable`, but Signal's `ScrollAnchor`
/// declares `Equatable` with a stored `Anchor<CGPoint>`, which requires the
/// synthesized `==` to compare anchors. Provide conditional conformance so that
/// source compiles; comparison falls back to the boxed value.
extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Anchor<Value>, rhs: Anchor<Value>) -> Bool {
        lhs.value == rhs.value
    }
}

extension Anchor.Source where Value == CGRect {
    /// The bounds rect of the view.
    public static var bounds: Anchor<CGRect>.Source {
        Anchor<CGRect>.Source(kind: .bounds)
    }

    /// A source describing an explicit rect in the local coordinate space.
    public init(_ rect: CGRect) {
        self.init(kind: .rect(rect), value: rect)
    }
}

extension Anchor.Source where Value == CGPoint {
    /// A source describing a unit point within the view's bounds.
    public static func unitPoint(_ unitPoint: UnitPoint) -> Anchor<CGPoint>.Source {
        Anchor<CGPoint>.Source(kind: .unit(unitPoint))
    }

    public static var top: Anchor<CGPoint>.Source { .unitPoint(.top) }
    public static var bottom: Anchor<CGPoint>.Source { .unitPoint(.bottom) }
    public static var leading: Anchor<CGPoint>.Source { .unitPoint(.leading) }
    public static var trailing: Anchor<CGPoint>.Source { .unitPoint(.trailing) }
    public static var center: Anchor<CGPoint>.Source { .unitPoint(.center) }
    public static var topLeading: Anchor<CGPoint>.Source { .unitPoint(.topLeading) }
    public static var topTrailing: Anchor<CGPoint>.Source { .unitPoint(.topTrailing) }
    public static var bottomLeading: Anchor<CGPoint>.Source { .unitPoint(.bottomLeading) }
    public static var bottomTrailing: Anchor<CGPoint>.Source { .unitPoint(.bottomTrailing) }

    /// A source describing an explicit point in the local coordinate space.
    public init(_ point: CGPoint) {
        self.init(kind: .point(point), value: point)
    }
}

// MARK: - GeometryProxy anchor resolution

extension GeometryProxy {
    /// Resolves an `Anchor` to its value in this proxy's coordinate space.
    ///
    /// Mirrors SwiftUI's `subscript<T>(anchor: Anchor<T>) -> T`. With no real
    /// layout pass, the value boxed inside the `Anchor` is returned directly.
    public subscript<T>(anchor: Anchor<T>) -> T {
        anchor.value
    }
}

// MARK: - View preference modifiers

/// A view that publishes a value to a preference key.
public struct _PreferenceWritingView<Content: View, K: PreferenceKey>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: K.Value
    public var body: Never { fatalError("_PreferenceWritingView is a primitive view") }
}

/// A view that derives a preference value from an anchor source.
public struct _AnchorPreferenceView<Content: View, A, K: PreferenceKey>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let source: Anchor<A>.Source
    public let transform: (Anchor<A>) -> K.Value
    public var body: Never { fatalError("_AnchorPreferenceView is a primitive view") }
}

/// A view that mutates the inherited preference value using an anchor source.
public struct _TransformAnchorPreferenceView<Content: View, A, K: PreferenceKey>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let source: Anchor<A>.Source
    public let transform: (inout K.Value, Anchor<A>) -> Void
    public var body: Never { fatalError("_TransformAnchorPreferenceView is a primitive view") }
}

extension View {
    /// Sets a value for the given preference.
    public func preference<K: PreferenceKey>(
        key: K.Type,
        value: K.Value
    ) -> some View {
        _PreferenceWritingView<Self, K>(content: self, value: value)
    }

    /// Sets a value for the given preference, derived from the view's anchor.
    public func anchorPreference<A, K: PreferenceKey>(
        key: K.Type,
        value: Anchor<A>.Source,
        transform: @escaping (Anchor<A>) -> K.Value
    ) -> some View {
        _AnchorPreferenceView<Self, A, K>(content: self, source: value, transform: transform)
    }

    /// Mutates the inherited preference value using the view's anchor.
    public func transformAnchorPreference<A, K: PreferenceKey>(
        key: K.Type,
        value: Anchor<A>.Source,
        transform: @escaping (inout K.Value, Anchor<A>) -> Void
    ) -> some View {
        _TransformAnchorPreferenceView<Self, A, K>(content: self, source: value, transform: transform)
    }

    /// Applies a transformation to the inherited preference value.
    public func transformPreference<K: PreferenceKey>(
        _ key: K.Type,
        _ callback: @escaping (inout K.Value) -> Void
    ) -> some View {
        // Inert on Linux: there is no inherited value to transform here, so we
        // surface a default-seeded value and discard the mutation. Present only
        // so source that calls `transformPreference` type-checks.
        var seed = K.defaultValue
        callback(&seed)
        return _PreferenceWritingView<Self, K>(content: self, value: seed)
    }
}
