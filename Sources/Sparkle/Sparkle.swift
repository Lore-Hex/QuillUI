import Foundation
import Combine
import QuillKit

public protocol SPUUpdaterDelegate: AnyObject {
    func allowedChannels(for updater: SPUUpdater) -> Set<String>
}

public extension SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        _ = updater
        return []
    }
}

public final class SPUUpdater: NSObject, @unchecked Sendable {
    private let service: QuillUpdateService

    public var automaticallyChecksForUpdates: Bool = false
    public var lastUpdateCheckDate: Date?

    public var canCheckForUpdates: Bool {
        get { service.canCheckForUpdates }
        set { service.configure(canCheckForUpdates: newValue) }
    }

    public init(service: QuillUpdateService = .shared) {
        self.service = service
        super.init()
    }

    public func checkForUpdates() {
        lastUpdateCheckDate = Date()
        service.checkForUpdates()
    }

    public func setFeedURL(_ url: URL?) {
        _ = url
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
