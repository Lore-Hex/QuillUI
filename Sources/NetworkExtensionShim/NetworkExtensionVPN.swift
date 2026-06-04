// NetworkExtension — VPN management surface (Linux shadow).
// ========================================================
// Companion to NetworkExtension.swift (the packet-tunnel *provider* side used by
// WireGuardKit). This is the *management* side that the app uses (WireGuard's
// TunnelsManager): NEVPNManager / NETunnelProviderManager + connection/status.
//
// COMPILE-ONLY: type/API stubs so unmodified macOS app source recompiles on
// Linux. No real VPN behavior — load/save are no-ops whose completion handlers
// fire with `nil` so app flow proceeds; a later runtime layer drives real
// tunnels out-of-band (wg-quick). The SwiftPM target is named `NetworkExtension`
// (added only under `#if os(Linux)` in the manifest), so this shadows Apple's
// framework on Linux and is absent on macOS. Surface driven from real upstream
// usage (TunnelsManager).
import Foundation

/// Mirrors `NEVPNStatus`.
public enum NEVPNStatus: Int, Sendable {
    case invalid = 0
    case disconnected = 1
    case connecting = 2
    case connected = 3
    case reconnecting = 4
    case disconnecting = 5
}

/// Mirrors `NEVPNError` (an `Error` with a small code set).
public struct NEVPNError: Error, Equatable, Sendable {
    public enum Code: Int, Sendable {
        case configurationInvalid = 1
        case configurationDisabled = 2
        case connectionFailed = 3
        case configurationStale = 4
        case configurationReadWriteFailed = 5
        case configurationUnknown = 6
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public var localizedDescription: String { "NEVPNError(\(code))" }
}

/// Base protocol-configuration type (`NEVPNProtocol`). Subclassed by
/// `NETunnelProviderProtocol`.
open class NEVPNProtocol: NSObject {
    public var serverAddress: String?
    public var username: String?
    public var passwordReference: Data?
    public var disconnectOnSleep: Bool = false
    public override init() { super.init() }
}

/// Mirrors `NETunnelProviderProtocol` — the app-side provider configuration.
open class NETunnelProviderProtocol: NEVPNProtocol {
    public var providerConfiguration: [String: Any]?
    public var providerBundleIdentifier: String?
    public override init() { super.init() }
}

/// Mirrors `NEVPNConnection`: the live status of a configuration. The shadow
/// holds the status; transitions are driven by the (later) runtime layer.
open class NEVPNConnection: NSObject {
    public internal(set) var status: NEVPNStatus = .invalid
    public internal(set) var connectedDate: Date?
    /// Posted (by the runtime layer) when `status` changes.
    public static let statusDidChangeNotification = Notification.Name("NEVPNStatusDidChange")

    public override init() { super.init() }
    open func startVPNTunnel() throws {}
    open func startVPNTunnel(options: [String: NSObject]?) throws {}
    open func stopVPNTunnel() {}
}

/// Mirrors `NETunnelProviderSession` — a connection that can exchange messages
/// with its provider extension.
open class NETunnelProviderSession: NEVPNConnection {
    open func sendProviderMessage(_ messageData: Data, responseHandler: ((Data?) -> Void)? = nil) throws {
        responseHandler?(nil)
    }
}

/// Mirrors `NEOnDemandRule` (base). WireGuard builds connect/disconnect rules.
open class NEOnDemandRule: NSObject {
    public override init() { super.init() }
}
public final class NEOnDemandRuleConnect: NEOnDemandRule {}
public final class NEOnDemandRuleDisconnect: NEOnDemandRule {}

/// Mirrors `NEVPNManager`: load/save a VPN configuration + its `connection`.
/// On Linux these persistence calls are no-ops (config lives elsewhere); the
/// completion handlers fire with `nil` error so app flow proceeds.
open class NEVPNManager: NSObject {
    public var isEnabled: Bool = false
    public var isOnDemandEnabled: Bool = false
    public var onDemandRules: [NEOnDemandRule]?
    public var localizedDescription: String?
    public var protocolConfiguration: NEVPNProtocol?
    public let connection: NEVPNConnection = NETunnelProviderSession()

    public override init() { super.init() }

    open func loadFromPreferences(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }
    open func saveToPreferences(completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
    open func removeFromPreferences(completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
}

/// Mirrors `NETunnelProviderManager` — the app-side manager for a packet-tunnel
/// provider. `loadAllFromPreferences` returns the (empty, on Linux) set of saved
/// configurations.
open class NETunnelProviderManager: NEVPNManager {
    public override init() { super.init() }
    open class func loadAllFromPreferences(completionHandler: @escaping ([NETunnelProviderManager]?, Error?) -> Void) {
        completionHandler([], nil)
    }
}
