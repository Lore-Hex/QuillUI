/// A type that represents part of the UI.
/// Conforming types declare their body as a composition of other views.
///
/// `@MainActor @preconcurrency` is Apple's exact 2024-SDK shape: the whole
/// protocol is main-actor isolated, so conforming types infer type-level
/// isolation (helper methods and computed properties on app view structs are
/// isolated, exactly as on macOS), while `@preconcurrency` downgrades
/// violations from pre-concurrency-shaped code (e.g. nonisolated nested
/// Coordinator classes touching the parent view) to warnings in the Swift 5
/// language mode — which is how unmodified upstream apps compile on Apple.
@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @MainActor @ViewBuilder var body: Body { get }
}

/// A marker protocol for views that have no reactive properties (@State, etc.)
/// and can skip Mirror reflection during rendering.
public protocol PrimitiveView: View {}

/// A view whose rendered descendants are opaque to ancestor metadata discovery.
/// Platform representable hosts use this boundary because their native subtree
/// is not part of the enclosing SwiftUI hierarchy.
public protocol _ViewMetadataExtractionBoundary: View {}

/// A view that produces no content.
public struct EmptyView: View, PrimitiveView {
    public typealias Body = Never
    public var body: Never { fatalError("EmptyView has no body") }
    public init() {}
}

extension Never: View {
    public var body: Never { fatalError() }
}
