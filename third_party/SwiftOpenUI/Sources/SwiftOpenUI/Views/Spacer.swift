/// A flexible space that expands along the major axis of its containing stack.
public struct Spacer {
    public typealias Body = Never

    public let minLength: Int?

    public init(minLength: Int? = nil) {
        self.minLength = minLength
    }

    public var body: Never { fatalError("Spacer is a primitive view") }
}

/// A visual element that can be used to separate content.
public struct Divider {
    public typealias Body = Never
    public init() {}
    public var body: Never { fatalError("Divider is a primitive view") }
}

// View conformance lives in an extension (Apple declares it the same
// way for primitive value views): protocol-isolation inference applies
// only to conformances declared on the type itself, so statics like
// Color.accentColor stay nonisolated and remain usable as default
// argument values in nonisolated app code (IceCubes ToastCenter).
extension Spacer: View, PrimitiveView {}

// View conformance lives in an extension (Apple declares it the same
// way for primitive value views): protocol-isolation inference applies
// only to conformances declared on the type itself, so statics like
// Color.accentColor stay nonisolated and remain usable as default
// argument values in nonisolated app code (IceCubes ToastCenter).
extension Divider: View, PrimitiveView {}
