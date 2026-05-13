import Foundation

public enum QuillBackendIdentifier: String, CaseIterable, Sendable {
    case swiftUI = "swiftui"
    case gtk = "gtk"
    case qt = "qt"

    public init?(environmentValue rawValue: String) {
        guard let identifier = Self.aliases[Self.normalizedEnvironmentValue(rawValue)] else {
            return nil
        }

        self = identifier
    }

    private static let aliases: [String: QuillBackendIdentifier] = [
        "swiftui": .swiftUI,
        "swift-ui": .swiftUI,
        "apple": .swiftUI,
        "native": .swiftUI,
        "gtk": .gtk,
        "gtk4": .gtk,
        "qt": .qt,
        "qt6": .qt
    ]

    private static func normalizedEnvironmentValue(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

public struct QuillBackendDescriptor: Equatable, Sendable {
    public let identifier: QuillBackendIdentifier
    public let displayName: String
    public let isPlatformDefault: Bool
    public let isExperimental: Bool
    public let runtimeNotes: String

    public var hasNativeRuntime: Bool {
        QuillBackendRegistry.hasNativeRuntime(for: identifier)
    }

    public var runtimeBackend: QuillBackendIdentifier {
        QuillBackendRegistry.runtimeBackend(for: identifier)
    }

    public var runtimeDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: runtimeBackend)
    }

    public var usesRuntimeFallback: Bool {
        runtimeBackend != identifier
    }

    public var runtimeMode: QuillBackendRuntimeMode {
        usesRuntimeFallback ? .platformFallback : .native
    }

    public var runtimeSummary: String {
        QuillBackendRegistry.runtimeSummary(selected: identifier)
    }

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
        QuillBackendRegistry.runtimeSummary(selected: selected, runtime: runtime)
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

    static var status: QuillBackendRuntimeStatus {
        runtimeStatus
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

    public static var nativeRuntimeBackends: [QuillBackendIdentifier] {
        #if os(Linux)
        return [.gtk]
        #else
        return [.swiftUI]
        #endif
    }

    public static var platformRuntimeFallback: QuillBackendIdentifier {
        #if os(Linux)
        return .gtk
        #else
        return .swiftUI
        #endif
    }

    public static var requested: QuillBackendIdentifier? {
        requestedBackend(from: ProcessInfo.processInfo.environment)
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
        launchPlan(requested: requested, preferred: preferredBackend)
    }

    public static func launchPlan(
        environment: [String: String],
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        launchPlan(
            requested: requestedBackend(from: environment),
            preferred: preferredBackend
        )
    }

    public static func launchPlan(
        requested requestedBackend: QuillBackendIdentifier?,
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        let selectedBackend = requestedBackend ?? preferredBackend ?? platformDefault

        return QuillBackendLaunchPlan(
            requested: requestedBackend,
            preferred: preferredBackend,
            selected: selectedBackend,
            runtime: runtimeBackend(for: selectedBackend)
        )
    }

    public static func requestedBackend(
        from environment: [String: String]
    ) -> QuillBackendIdentifier? {
        guard let rawValue = environment[environmentKey],
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return QuillBackendIdentifier(environmentValue: rawValue)
    }

    public static func runtimeBackend(
        for selectedBackend: QuillBackendIdentifier
    ) -> QuillBackendIdentifier {
        if hasNativeRuntime(for: selectedBackend) {
            return selectedBackend
        }

        return platformRuntimeFallback
    }

    public static func hasNativeRuntime(
        for identifier: QuillBackendIdentifier
    ) -> Bool {
        nativeRuntimeBackends.contains(identifier)
    }

    public static func runtimeSummary(
        selected selectedBackend: QuillBackendIdentifier
    ) -> String {
        runtimeSummary(
            selected: selectedBackend,
            runtime: runtimeBackend(for: selectedBackend)
        )
    }

    public static func runtimeSummary(
        selected selectedBackend: QuillBackendIdentifier,
        runtime runtimeBackend: QuillBackendIdentifier
    ) -> String {
        let selectedDescriptor = descriptor(for: selectedBackend)
        let runtimeDescriptor = descriptor(for: runtimeBackend)

        if selectedBackend != runtimeBackend {
            return "\(selectedDescriptor.displayName) selected, but the native renderer is not available yet; launches currently use \(runtimeDescriptor.displayName)."
        }

        return "\(runtimeDescriptor.displayName) native renderer selected."
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
