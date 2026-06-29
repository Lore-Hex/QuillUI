import Foundation
import AppKit

public protocol AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool
}

public extension AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        _ = connection
        return false
    }
}

public protocol AppExtension {
    associatedtype Configuration: AppExtensionConfiguration

    var configuration: Configuration { get }
}

public struct AppExtensionIdentity: Hashable, Sendable {
    public var bundleIdentifier: String
    public var localizedName: String

    public init(bundleIdentifier: String, localizedName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName ?? bundleIdentifier
    }

    public static func matching(appExtensionPointIDs: String...) throws -> AsyncStream<[AppExtensionIdentity]> {
        _ = appExtensionPointIDs
        return AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    public static func matching(appExtensionPointIDs: [String]) throws -> AsyncStream<[AppExtensionIdentity]> {
        _ = appExtensionPointIDs
        return AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    public static var availabilityUpdates: AsyncStream<AppExtensionAvailability> {
        AsyncStream { continuation in
            continuation.yield(AppExtensionAvailability())
            continuation.finish()
        }
    }
}

public struct AppExtensionAvailability: Sendable {
    public var disabledCount: Int
    public var unapprovedCount: Int

    public init(disabledCount: Int = 0, unapprovedCount: Int = 0) {
        self.disabledCount = disabledCount
        self.unapprovedCount = unapprovedCount
    }
}

public final class AppExtensionProcess: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var appExtensionIdentity: AppExtensionIdentity

        public init(appExtensionIdentity: AppExtensionIdentity) {
            self.appExtensionIdentity = appExtensionIdentity
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration) async throws {
        self.configuration = configuration
    }

    public func makeXPCConnection() throws -> NSXPCConnection {
        NSXPCConnection(serviceName: configuration.appExtensionIdentity.bundleIdentifier)
    }
}
