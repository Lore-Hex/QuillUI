import QuillUI

public enum QuillQtRuntimeMode: String, Sendable {
    case native
    case platformFallback
}

public struct QuillQtBackendStatus: Equatable, Sendable {
    public let identifier: QuillBackendIdentifier
    public let mode: QuillQtRuntimeMode
    public let message: String

    public init(
        identifier: QuillBackendIdentifier = .qt,
        mode: QuillQtRuntimeMode,
        message: String
    ) {
        self.identifier = identifier
        self.mode = mode
        self.message = message
    }
}

public enum QuillQtBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .qt

    public static var status: QuillQtBackendStatus {
        QuillQtBackendStatus(
            mode: .platformFallback,
            message: "QuillUIQt is present, but the native Qt renderer is not linked yet; launches use the platform default runtime."
        )
    }

    public static var descriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: identifier)
    }
}

public enum QuillQtApp {
    public static func run<A: App>(_ appType: A.Type) {
        QuillApp.run(appType)
    }
}
