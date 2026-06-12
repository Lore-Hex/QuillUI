import Foundation
import QuillKit

// CFString deliberately NOT declared here: QuillKit (always visible alongside
// this module — it is our own dependency and re-exported into the WireGuard
// conformance build) is the single owner of the Linux `CFString = String`
// alias. Declaring a second same-named alias here — even to the SAME
// canonical type — left `helperBundleId as CFString` ambiguous for type
// lookup on CI (post-#528 run on main@7773a5b1). One name, one owner.

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

/// Legacy login-item toggle. WireGuard's AppDelegate calls SMLoginItemSetEnabled to
/// (de)register its login helper. Linux tracks the requested state through
/// QuillKit until a native autostart backend is attached.
@discardableResult
public func SMLoginItemSetEnabled(_ identifier: CFString, _ enabled: Bool) -> Bool {
    if enabled {
        QuillLaunchService.shared.register()
    } else {
        QuillLaunchService.shared.unregister()
    }

    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "ServiceManagement",
        operation: "SMLoginItemSetEnabled",
        severity: .info,
        message: "Login item '\(identifier.description)' is tracked by the QuillKit compatibility launch service."
    )
    return true
}
