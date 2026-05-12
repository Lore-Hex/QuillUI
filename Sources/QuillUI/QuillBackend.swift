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

public protocol QuillBackend {
    static var identifier: QuillBackendIdentifier { get }
    static var descriptor: QuillBackendDescriptor { get }
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
        requested ?? platformDefault
    }

    public static var knownBackends: [QuillBackendDescriptor] {
        QuillBackendIdentifier.allCases.map(descriptor(for:))
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
