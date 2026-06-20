import Foundation
import Combine
import QuillKit

public final class SPUUpdater: @unchecked Sendable {
    private let service: QuillUpdateService

    public var canCheckForUpdates: Bool {
        get { service.canCheckForUpdates }
        set { service.configure(canCheckForUpdates: newValue) }
    }

    public init(service: QuillUpdateService = .shared) {
        self.service = service
    }

    public convenience init(
        hostBundle: Bundle,
        applicationBundle: Bundle,
        userDriver: SPUStandardUserDriver,
        delegate: SPUUpdaterDelegate?
    ) {
        _ = hostBundle
        _ = applicationBundle
        _ = userDriver
        _ = delegate
        self.init()
    }

    public func start() throws {
        service.configure(canCheckForUpdates: true)
    }

    public func checkForUpdates() {
        service.checkForUpdates()
    }
}

public protocol SPUStandardUserDriverDelegate: AnyObject {}
public protocol SPUUpdaterDelegate: AnyObject {}

public final class SPUStandardUserDriver: @unchecked Sendable {
    public let hostBundle: Bundle
    public weak var delegate: SPUStandardUserDriverDelegate?

    public init(hostBundle: Bundle, delegate: SPUStandardUserDriverDelegate?) {
        self.hostBundle = hostBundle
        self.delegate = delegate
    }
}

public final class SPUStandardUpdaterController: @unchecked Sendable {
    public let updater: SPUUpdater

    public init(startingUpdater: Bool, updaterDelegate: Any?, userDriverDelegate: Any?) {
        updater = SPUUpdater()
        if startingUpdater {
            QuillUpdateService.shared.configure(canCheckForUpdates: true)
        }
    }
}
