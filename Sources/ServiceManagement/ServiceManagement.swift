import Foundation
import QuillKit

// CoreFoundation's CFString isn't surfaced as a Swift type by corelibs Foundation on
// Linux, but WireGuard's AppDelegate does `helperBundleId as CFString` when calling
// SMLoginItemSetEnabled. MUST stay the same underlying type as QuillKit's
// `CFString` (= String): WireGuard's AppDelegate sees both modules, and two
// same-named aliases are unambiguous only while they denote one canonical type
// (aliasing NSString here made every `CFString` reference ambiguous the moment
// QuillKit became visible in that build — the LocalizedStringKey lesson, #524).
// `String as CFString` still compiles, and this file only uses `.description`.
public typealias CFString = String

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
