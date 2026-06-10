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

    public func checkForUpdates() {
        service.checkForUpdates()
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
