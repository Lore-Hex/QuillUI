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
    case reasserting = 4
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

    // Apple exposes the codes directly on NEVPNError (e.g.
    // `NEVPNError(NEVPNError.configurationUnknown)`, `error.code == NEVPNError.configurationInvalid`).
    public static let configurationInvalid = Code.configurationInvalid
    public static let configurationDisabled = Code.configurationDisabled
    public static let connectionFailed = Code.connectionFailed
    public static let configurationStale = Code.configurationStale
    public static let configurationReadWriteFailed = Code.configurationReadWriteFailed
    public static let configurationUnknown = Code.configurationUnknown

    // Lets a `Code` pattern match an `NEVPNError` value in a switch, mirroring
    // Apple's behavior — `switch systemError { case NEVPNError.configurationInvalid: … }`
    // (TunnelErrors.swift maps NE errors to user-facing text this way).
    public static func ~= (pattern: Code, value: NEVPNError) -> Bool {
        value.code == pattern
    }
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
    /// macOS-only on Apple; drops a saved password keychain reference. No-op on
    /// Linux (no system keychain reference to destroy).
    open func destroyConfigurationReference() {}
}

/// Mirrors `NEVPNConnection`: the live status of a configuration. The shadow
/// holds the status; transitions are driven by the (later) runtime layer.
/// Notification names NE posts (TunnelsManager observes these via
/// `NotificationCenter.default.observe(name: .NEVPNStatusDidChange, …)`).
public extension Notification.Name {
    static let NEVPNStatusDidChange = Notification.Name("NEVPNStatusDidChange")
    static let NEVPNConfigurationChange = Notification.Name("NEVPNConfigurationChange")
}

open class NEVPNConnection: NSObject {
    public internal(set) var status: NEVPNStatus = .invalid
    public internal(set) var connectedDate: Date?
    /// The manager that owns this connection. TunnelsManager reads
    /// `session.manager as? NETunnelProviderManager`. Weak to avoid the
    /// manager<->connection retain cycle.
    public internal(set) weak var manager: NEVPNManager?
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
    /// Mirrors `NETunnelProviderSession.startTunnel(options:)` — distinct from
    /// `NEVPNConnection.startVPNTunnel`. No-op on Linux; a runtime layer drives
    /// the real tunnel out-of-band.
    open func startTunnel(options: [String: Any]? = nil) throws {}
    /// Mirrors `NETunnelProviderSession.stopTunnel()`.
    open func stopTunnel() {}
    open func sendProviderMessage(_ messageData: Data, responseHandler: ((Data?) -> Void)? = nil) throws {
        responseHandler?(nil)
    }
}

/// Mirrors `NEOnDemandRuleInterfaceType` — the interface kind a rule matches.
public enum NEOnDemandRuleInterfaceType: Int, Sendable {
    case any = 0
    case wiFi = 1
    case cellular = 2
    case ethernet = 3
}

/// Mirrors `NEOnDemandRuleAction` — what a matched rule does.
public enum NEOnDemandRuleAction: Int, Sendable {
    case connect = 1
    case disconnect = 2
    case evaluateConnection = 3
    case ignore = 4
}

/// Mirrors `NEOnDemandRule` (base). WireGuard builds connect/disconnect rules
/// that match on interface type and (for Wi-Fi) SSID
/// (ActivateOnDemandOption.apply / read-back reads `rule.action`).
open class NEOnDemandRule: NSObject {
    /// What this rule does when matched; set by the concrete subclass.
    /// ActivateOnDemandOption reads `rule.action == .connect`/`.disconnect`.
    public internal(set) var action: NEOnDemandRuleAction = .ignore
    public var interfaceTypeMatch: NEOnDemandRuleInterfaceType = .any
    public var ssidMatch: [String]?
    public override init() { super.init() }
    /// Convenience the app uses: `NEOnDemandRuleConnect(interfaceType: .any)`,
    /// `NEOnDemandRuleDisconnect(interfaceType: .wiFi)`.
    public convenience init(interfaceType: NEOnDemandRuleInterfaceType) {
        self.init()
        self.interfaceTypeMatch = interfaceType
    }
}
public final class NEOnDemandRuleConnect: NEOnDemandRule {
    public override init() { super.init(); action = .connect }
}
public final class NEOnDemandRuleDisconnect: NEOnDemandRule {
    public override init() { super.init(); action = .disconnect }
}

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

    public override init() { super.init(); connection.manager = self }

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
