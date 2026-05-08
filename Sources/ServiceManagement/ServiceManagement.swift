import Foundation
import QuillKit

public enum SMAppService {
    public static let mainApp = Service()

    public final class Service: @unchecked Sendable {
        public enum Status: Sendable {
            case enabled
            case requiresApproval
            case notRegistered
            case notFound
        }

        public var status: Status { QuillLaunchService.shared.isEnabled ? .enabled : .notRegistered }

        public init() {}
        public func register() throws { QuillLaunchService.shared.register() }
        public func unregister() throws { QuillLaunchService.shared.unregister() }
    }
}
