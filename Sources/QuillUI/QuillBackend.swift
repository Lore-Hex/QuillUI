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
        runtimeAvailability.hasNativeRuntime
    }

    public var runtimeBackend: QuillBackendIdentifier {
        runtimeAvailability.runtime
    }

    public var runtimeDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: runtimeBackend)
    }

    public var runtimeAvailability: QuillBackendRuntimeAvailability {
        QuillBackendRegistry.runtimeAvailability(for: identifier)
    }

    public var usesRuntimeFallback: Bool {
        runtimeAvailability.usesRuntimeFallback
    }

    public var runtimeMode: QuillBackendRuntimeMode {
        runtimeAvailability.mode
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

public struct QuillBackendRuntimeAvailability: Equatable, Sendable {
    public let selected: QuillBackendIdentifier
    public let runtime: QuillBackendIdentifier

    public var selectedDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: selected)
    }

    public var runtimeDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: runtime)
    }

    public var hasNativeRuntime: Bool {
        selected == runtime
    }

    public var usesRuntimeFallback: Bool {
        !hasNativeRuntime
    }

    public var mode: QuillBackendRuntimeMode {
        hasNativeRuntime ? .native : .platformFallback
    }

    public var summary: String {
        QuillBackendRegistry.runtimeSummary(availability: self)
    }

    public var rowValues: [String] {
        [
            selected.rawValue,
            runtime.rawValue,
            mode.rawValue
        ]
    }

    public var tabSeparatedRow: String {
        rowValues.joined(separator: "\t")
    }

    public init(
        selected: QuillBackendIdentifier,
        runtime: QuillBackendIdentifier
    ) {
        self.selected = selected
        self.runtime = runtime
    }
}

public enum QuillBackendRequest: Equatable, Sendable {
    case unspecified
    case valid(QuillBackendIdentifier)
    case invalid(rawValue: String)

    public var identifier: QuillBackendIdentifier? {
        guard case let .valid(identifier) = self else {
            return nil
        }

        return identifier
    }

    public var invalidRawValue: String? {
        guard case let .invalid(rawValue) = self else {
            return nil
        }

        return rawValue
    }
}

public struct QuillBackendLaunchPlan: Equatable, Sendable {
    public let request: QuillBackendRequest
    public let requested: QuillBackendIdentifier?
    public let preferred: QuillBackendIdentifier?
    public let selected: QuillBackendIdentifier
    public let runtime: QuillBackendIdentifier

    public var usesRuntimeFallback: Bool {
        selected != runtime
    }

    public var runtimeMode: QuillBackendRuntimeMode {
        runtimeAvailability.mode
    }

    public var selectedDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: selected)
    }

    public var runtimeDescriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: runtime)
    }

    public var runtimeAvailability: QuillBackendRuntimeAvailability {
        QuillBackendRuntimeAvailability(
            selected: selected,
            runtime: runtime
        )
    }

    public var requestStatusMessage: String? {
        guard let invalidRawValue = request.invalidRawValue else {
            return nil
        }

        return "Unsupported \(QuillBackendRegistry.environmentKey) value \"\(invalidRawValue)\"; using \(selectedDescriptor.displayName)."
    }

    public var statusMessage: String {
        runtimeAvailability.summary
    }

    public var statusMessages: [String] {
        if let requestStatusMessage {
            return [requestStatusMessage, statusMessage]
        }

        return [statusMessage]
    }

    public var displayMessage: String {
        statusMessages.joined(separator: " ")
    }

    public init(
        request: QuillBackendRequest = .unspecified,
        requested: QuillBackendIdentifier?,
        preferred: QuillBackendIdentifier?,
        selected: QuillBackendIdentifier,
        runtime: QuillBackendIdentifier
    ) {
        self.request = request
        self.requested = requested
        self.preferred = preferred
        self.selected = selected
        self.runtime = runtime
    }
}

public struct QuillBackendRuntimeStatus: Equatable, Sendable {
    public let identifier: QuillBackendIdentifier
    public let launchPlan: QuillBackendLaunchPlan
    public let requested: QuillBackendIdentifier?
    public let preferred: QuillBackendIdentifier?
    public let selected: QuillBackendIdentifier
    public let runtime: QuillBackendIdentifier
    public let selectedDescriptor: QuillBackendDescriptor
    public let runtimeDescriptor: QuillBackendDescriptor
    public let runtimeAvailability: QuillBackendRuntimeAvailability
    public let usesRuntimeFallback: Bool
    public let hasNativeRuntime: Bool
    public let mode: QuillBackendRuntimeMode
    public let runtimeMessage: String
    public let messages: [String]
    public let message: String

    public init(
        identifier: QuillBackendIdentifier,
        launchPlan: QuillBackendLaunchPlan
    ) {
        self.identifier = identifier
        self.launchPlan = launchPlan
        self.requested = launchPlan.requested
        self.preferred = launchPlan.preferred
        self.selected = launchPlan.selected
        self.runtime = launchPlan.runtime
        self.selectedDescriptor = launchPlan.selectedDescriptor
        self.runtimeDescriptor = launchPlan.runtimeDescriptor
        self.runtimeAvailability = launchPlan.runtimeAvailability
        self.usesRuntimeFallback = launchPlan.usesRuntimeFallback
        self.hasNativeRuntime = launchPlan.runtimeAvailability.hasNativeRuntime
        self.mode = launchPlan.runtimeMode
        self.runtimeMessage = launchPlan.statusMessage
        self.messages = launchPlan.statusMessages
        self.message = launchPlan.displayMessage
    }
}

private final class QuillBackendRuntimeContextStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLaunchPlan: QuillBackendLaunchPlan?

    var launchPlan: QuillBackendLaunchPlan? {
        lock.withLock { storedLaunchPlan }
    }

    func install(_ launchPlan: QuillBackendLaunchPlan?) {
        lock.withLock {
            storedLaunchPlan = launchPlan
        }
    }
}

public enum QuillBackendRuntimeContext {
    private static let storage = QuillBackendRuntimeContextStorage()

    public static var launchPlan: QuillBackendLaunchPlan? {
        storage.launchPlan
    }

    public static var selectedBackend: QuillBackendIdentifier? {
        launchPlan?.selected
    }

    static func install(_ launchPlan: QuillBackendLaunchPlan?) {
        storage.install(launchPlan)
    }
}

public protocol QuillBackend {
    static var identifier: QuillBackendIdentifier { get }
    static var descriptor: QuillBackendDescriptor { get }
    static func initialize()
}

public extension QuillBackend {
    static func initialize() {}

    static var descriptor: QuillBackendDescriptor {
        QuillBackendRegistry.descriptor(for: identifier)
    }

    static var launchPlan: QuillBackendLaunchPlan {
        QuillBackendRegistry.launchPlan(preferred: identifier)
    }

    static var runtimeStatus: QuillBackendRuntimeStatus {
        QuillBackendRegistry.runtimeStatus(preferred: identifier)
    }

    static var status: QuillBackendRuntimeStatus {
        runtimeStatus
    }

    static var runtimeAvailability: QuillBackendRuntimeAvailability {
        launchPlan.runtimeAvailability
    }

    static var runtimeBackend: QuillBackendIdentifier {
        launchPlan.runtime
    }

    static var runtimeMode: QuillBackendRuntimeMode {
        launchPlan.runtimeMode
    }

    static var hasNativeRuntime: Bool {
        runtimeAvailability.hasNativeRuntime
    }

    static var usesRuntimeFallback: Bool {
        launchPlan.usesRuntimeFallback
    }

    static var runtimeMessage: String {
        launchPlan.statusMessage
    }
}

public enum QuillBackendRegistry {
    public static let environmentKey = "QUILLUI_BACKEND"

    public static var platformDefault: QuillBackendIdentifier {
        #if os(Linux)
        return QuillLinuxRuntimeHost.platformFallbackBackend
        #else
        return .swiftUI
        #endif
    }

    public static var nativeRuntimeBackends: [QuillBackendIdentifier] {
        #if os(Linux)
        return QuillLinuxRuntimeHost.supportedBackends
        #else
        return [.swiftUI]
        #endif
    }

    public static var platformRuntimeFallback: QuillBackendIdentifier {
        #if os(Linux)
        return QuillLinuxRuntimeHost.platformFallbackBackend
        #else
        return .swiftUI
        #endif
    }

    public static var requested: QuillBackendIdentifier? {
        requestedBackend(from: ProcessInfo.processInfo.environment)
    }

    public static var environmentRequest: QuillBackendRequest {
        backendRequest(from: ProcessInfo.processInfo.environment)
    }

    public static var launchBackend: QuillBackendIdentifier {
        launchPlan().selected
    }

    public static var knownBackends: [QuillBackendDescriptor] {
        QuillBackendIdentifier.allCases.map(descriptor(for:))
    }

    public static var runtimeAvailabilities: [QuillBackendRuntimeAvailability] {
        QuillBackendIdentifier.allCases.map(runtimeAvailability(for:))
    }

    public static func runtimeStatus(
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendRuntimeStatus {
        runtimeStatus(request: environmentRequest, preferred: preferredBackend)
    }

    public static func runtimeStatus(
        environment: [String: String],
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendRuntimeStatus {
        runtimeStatus(
            request: backendRequest(from: environment),
            preferred: preferredBackend
        )
    }

    public static func runtimeStatus(
        requested requestedBackend: QuillBackendIdentifier?,
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendRuntimeStatus {
        let request = requestedBackend.map { QuillBackendRequest.valid($0) } ?? .unspecified
        return runtimeStatus(request: request, preferred: preferredBackend)
    }

    public static func runtimeStatus(
        request backendRequest: QuillBackendRequest,
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendRuntimeStatus {
        let launchPlan = launchPlan(request: backendRequest, preferred: preferredBackend)
        return QuillBackendRuntimeStatus(
            identifier: preferredBackend ?? launchPlan.selected,
            launchPlan: launchPlan
        )
    }

    public static func launchPlan(
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        launchPlan(request: environmentRequest, preferred: preferredBackend)
    }

    public static func launchPlan(
        environment: [String: String],
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        launchPlan(
            request: backendRequest(from: environment),
            preferred: preferredBackend
        )
    }

    public static func launchPlan(
        requested requestedBackend: QuillBackendIdentifier?,
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        let request = requestedBackend.map { QuillBackendRequest.valid($0) } ?? .unspecified
        return launchPlan(request: request, preferred: preferredBackend)
    }

    public static func launchPlan(
        request backendRequest: QuillBackendRequest,
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> QuillBackendLaunchPlan {
        let requestedBackend = backendRequest.identifier
        let selectedBackend = requestedBackend ?? preferredBackend ?? platformDefault

        return QuillBackendLaunchPlan(
            request: backendRequest,
            requested: requestedBackend,
            preferred: preferredBackend,
            selected: selectedBackend,
            runtime: runtimeBackend(for: selectedBackend)
        )
    }

    public static func backendScopedEnvironmentValue(
        _ canonical: String,
        gtkLegacy: String,
        qtScoped: String,
        from environment: [String: String],
        preferred preferredBackend: QuillBackendIdentifier? = nil
    ) -> String? {
        let selectedBackend = launchPlan(
            environment: environment,
            preferred: preferredBackend
        ).selected
        let scopedValue: String?

        switch selectedBackend {
        case .qt:
            scopedValue = environment[qtScoped]
        case .gtk, .swiftUI:
            scopedValue = environment[gtkLegacy]
        }

        return environment[canonical] ?? scopedValue
    }

    public static func requestedBackend(
        from environment: [String: String]
    ) -> QuillBackendIdentifier? {
        backendRequest(from: environment).identifier
    }

    public static func backendRequest(
        from environment: [String: String]
    ) -> QuillBackendRequest {
        guard let rawValue = environment[environmentKey],
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .unspecified
        }

        let normalizedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let backend = QuillBackendIdentifier(environmentValue: rawValue) else {
            return .invalid(rawValue: normalizedRawValue)
        }

        return .valid(backend)
    }

    public static func runtimeBackend(
        for selectedBackend: QuillBackendIdentifier
    ) -> QuillBackendIdentifier {
        runtimeAvailability(for: selectedBackend).runtime
    }

    public static func runtimeAvailability(
        for selectedBackend: QuillBackendIdentifier
    ) -> QuillBackendRuntimeAvailability {
        if hasNativeRuntime(for: selectedBackend) {
            return QuillBackendRuntimeAvailability(
                selected: selectedBackend,
                runtime: selectedBackend
            )
        }

        return QuillBackendRuntimeAvailability(
            selected: selectedBackend,
            runtime: platformRuntimeFallback
        )
    }

    public static func hasNativeRuntime(
        for identifier: QuillBackendIdentifier
    ) -> Bool {
        nativeRuntimeBackends.contains(identifier)
    }

    public static func runtimeSummary(
        selected selectedBackend: QuillBackendIdentifier
    ) -> String {
        runtimeAvailability(for: selectedBackend).summary
    }

    public static func runtimeSummary(
        availability: QuillBackendRuntimeAvailability
    ) -> String {
        let selectedDescriptor = availability.selectedDescriptor
        let runtimeDescriptor = availability.runtimeDescriptor

        if availability.usesRuntimeFallback {
            return "\(selectedDescriptor.displayName) selected, but the native renderer is not available yet; launches currently use \(runtimeDescriptor.displayName)."
        }

        return "\(runtimeDescriptor.displayName) native renderer selected."
    }

    public static func runtimeSummary(
        selected selectedBackend: QuillBackendIdentifier,
        runtime runtimeBackend: QuillBackendIdentifier
    ) -> String {
        runtimeSummary(
            availability: QuillBackendRuntimeAvailability(
                selected: selectedBackend,
                runtime: runtimeBackend
            )
        )
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
                runtimeNotes: "Experimental QuillUIQt facade; canonical Linux app products can select generic or product-specific native Qt hosts while module-level facade calls still report the platform fallback."
            )
        }
    }
}
