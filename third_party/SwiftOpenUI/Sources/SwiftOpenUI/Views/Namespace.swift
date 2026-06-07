import Foundation

// Moved from QuillUI so vendored source (AppAccount) sees SwiftUI @Namespace.
@propertyWrapper
public struct Namespace: Sendable {
    public struct ID: Hashable, Sendable {
        private let rawValue = UUID()

        public init() {}
    }

    private var id: ID

    public init() {
        self.id = ID()
    }

    public var wrappedValue: ID {
        get { id }
        set { id = newValue }
    }
}
