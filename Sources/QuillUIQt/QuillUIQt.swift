import QuillUI

public typealias QuillQtRuntimeMode = QuillBackendRuntimeMode

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

    public static var launchPlan: QuillBackendLaunchPlan {
        QuillBackendRegistry.launchPlan(preferred: identifier)
    }

    public static var status: QuillQtBackendStatus {
        let plan = launchPlan

        return QuillQtBackendStatus(
            mode: plan.runtimeMode,
            message: plan.statusMessage
        )
    }

    public static var descriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: identifier)
    }
}

public enum QuillQtApp {
    public static func run<A: App>(_ appType: A.Type) {
        QuillApp.run(appType, preferredBackend: QuillQtBackend.identifier)
    }
}
