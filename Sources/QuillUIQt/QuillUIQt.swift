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

    public static var launchPlan: QuillBackendLaunchPlan {
        QuillBackendRegistry.launchPlan(preferred: identifier)
    }

    public static var status: QuillQtBackendStatus {
        let plan = launchPlan
        let mode: QuillQtRuntimeMode = plan.runtime == .qt ? .native : .platformFallback
        let runtimeName = QuillBackendRegistry.descriptor(for: plan.runtime).displayName
        let message: String
        if plan.usesRuntimeFallback {
            message = "QuillUIQt selected Qt, but the native Qt renderer is not linked yet; launches currently use \(runtimeName)."
        } else {
            message = "QuillUIQt is running through the native Qt renderer."
        }

        return QuillQtBackendStatus(
            mode: mode,
            message: message
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
