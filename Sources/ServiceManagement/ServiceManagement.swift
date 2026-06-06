import Foundation
import QuillKit

// CoreFoundation's CFString isn't surfaced as a Swift type by corelibs Foundation on
// Linux, but WireGuard's AppDelegate does `helperBundleId as CFString` when calling
// SMLoginItemSetEnabled. NSString is toll-free-bridged to CFString and supports
// `String as NSString` on Linux, so alias it. (Exported via `import ServiceManagement`.)
public typealias CFString = NSString

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
/// (de)register its login helper. No launch-services backend on Linux → compile-stub
/// returning false (the macOS app uses the real SM framework).
@discardableResult
public func SMLoginItemSetEnabled(_ identifier: CFString, _ enabled: Bool) -> Bool { false }
