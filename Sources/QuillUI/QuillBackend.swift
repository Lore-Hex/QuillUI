import Foundation

public enum QuillBackendIdentifier: String, CaseIterable, Sendable {
    case swiftUI = "swiftui"
    case gtk = "gtk"
    case qt = "qt"

    public init?(environmentValue rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "swiftui", "swift-ui", "apple", "native":
            self = .swiftUI
        case "gtk", "gtk4":
            self = .gtk
        case "qt", "qt6":
            self = .qt
        default:
            return nil
        }
    }
}

public struct QuillBackendDescriptor: Equatable, Sendable {
    public let identifier: QuillBackendIdentifier
    public let displayName: String
    public let isPlatformDefault: Bool
    public let isExperimental: Bool
    public let runtimeNotes: String

    public init(
        identifier: QuillBackendIdentifier,
        displayName: String,
        isPlatformDefault: Bool,
        isExperimental: Bool,
        runtimeNotes: String
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.isPlatformDefault = isPlatformDefault
        self.isExperimental = isExperimental
        self.runtimeNotes = runtimeNotes
    }
}

public enum QuillBackendRuntimeMode: String, Sendable {
    case native
    case platformFallback
}

public struct QuillBackendLaunchPlan: Equatable, Sendable {
    public let requested: QuillBackendIdentifier?
    public let preferred: QuillBackendIdentifier?
    public let selected: QuillBackendIdentifier
    public let runtime: QuillBackendIdentifier

    public var usesRuntimeFallback: Bool {
        selected != runtime
    }

    public var runtimeMode: QuillBackendRuntimeMode {
        usesRuntimeFallback ? .platformFallback : .native
    }

    public var selectedDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: selected)
    }

    public var runtimeDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: runtime)
    }

    public var statusMessage: String {
        if usesRuntimeFallback {
            return "\(selectedDescriptor.displayName) selected, but the native renderer is not available yet; launches currently use \(runtimeDescriptor.displayName)."
        }

        return "\(runtimeDescriptor.displayName) native renderer selected."
    }

    public init(
        requested: QuillBackendIdentifier?,
        preferred: QuillBackendIdentifier?,
        selected: QuillBackendIdentifier,
        runtime: QuillBackendIdentifier
    ) {
        self.requested = requested
        self.preferred = preferred
        self.selected = selected
        self.runtime = runtime
    }
}

public struct QuillBackendRuntimeStatus: Equatable, Sendable {
    public let identifier: QuillBackendIdentifier
    public let launchPlan: QuillBackendLaunchPlan
    public let mode: QuillBackendRuntimeMode
    public let message: String

    public init(
        identifier: QuillBackendIdentifier,
        launchPlan: QuillBackendLaunchPlan
    ) {
        self.identifier = identifier
        self.launchPlan = launchPlan
        self.mode = launchPlan.runtimeMode
        self.message = launchPlan.statusMessage
    }
}

public protocol QuillBackend {
    static var identifier: QuillBackendIdentifier { get }
    static var descriptor: QuillBackendDescriptor { get }
}

public extension QuillBackend {
    static var descriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: identifier)
    }

    static var launchPlan: QuillBackendLaunchPlan {
        QuillBackendRegistry.launchPlan(preferred: identifier)
    }

    static var runtimeStatus: QuillBackendRuntimeStatus {
        QuillBackendRuntimeStatus(
            identifier: identifier,
            launchPlan: launchPlan
        )
    }
}

public enum QuillBackendRegistry {
    public static let environmentKey = "QUILLUI_BACKEND"

    public static var platformDefault: QuillBackendIdentifier {
        #if os(Linux)
        return .gtk
        #else
        return .swiftUI
        #endif
    }

    public static var requested: QuillBackendIdentifier? {
        guard let rawValue = ProcessInfo.processInfo.environment[environmentKey],
              !rawValue.isEmpty
        else {
            return nil
        }

        return QuillBackendIdentifier(environmentValue: rawValue)
    }

    public static var launchBackend: QuillBackendIdentifier {
        launchPlan().selected
    }

    public static var knownBackends: [QuillBackendDescriptor] {
        QuillBackendIdentifier.allCases.map(descriptor(for:))
    }

    public static func launchPlan(
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        let requestedBackend = requested
        let selectedBackend = requestedBackend ?? preferredBackend ?? platformDefault

        return QuillBackendLaunchPlan(
            requested: requestedBackend,
            preferred: preferredBackend,
            selected: selectedBackend,
            runtime: runtimeBackend(for: selectedBackend)
        )
    }

    public static func runtimeBackend(
        for selectedBackend: QuillBackendIdentifier
    ) -> QuillBackendIdentifier {
        #if os(Linux)
        switch selectedBackend {
        case .swiftUI, .gtk, .qt:
            return .gtk
        }
        #else
        switch selectedBackend {
        case .swiftUI, .gtk, .qt:
            return .swiftUI
        }
        #endif
    }

    public static func descriptor(for identifier: QuillBackendIdentifier) -> QuillBackendDescriptor {
        switch identifier {
        case .swiftUI:
            return QuillBackendDescriptor(
                identifier: .swiftUI,
                displayName: "SwiftUI",
                isPlatformDefault: platformDefault == .swiftUI,
                isExperimental: false,
                runtimeNotes: "Native Apple SwiftUI runtime."
            )
        case .gtk:
            return QuillBackendDescriptor(
                identifier: .gtk,
                displayName: "GTK",
                isPlatformDefault: platformDefault == .gtk,
                isExperimental: false,
                runtimeNotes: "Linux default runtime through SwiftOpenUI and BackendGTK4."
            )
        case .qt:
            return QuillBackendDescriptor(
                identifier: .qt,
                displayName: "Qt",
                isPlatformDefault: platformDefault == .qt,
                isExperimental: true,
                runtimeNotes: "Experimental launch surface in QuillUIQt; native Qt renderer is not linked yet."
            )
        }
    }
}
