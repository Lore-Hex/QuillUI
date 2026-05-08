import Foundation
import Combine

public final class SPUUpdater: @unchecked Sendable {
    public var canCheckForUpdates: Bool = false

    public init() {}

    public func checkForUpdates() {}
}

public final class SPUStandardUpdaterController: @unchecked Sendable {
    public let updater = SPUUpdater()

    public init(startingUpdater: Bool, updaterDelegate: Any?, userDriverDelegate: Any?) {}
}

