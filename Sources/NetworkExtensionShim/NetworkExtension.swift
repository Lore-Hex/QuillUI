// Linux NetworkExtension shim. Apple's NetworkExtension framework
// only ships on iOS/macOS — upstream WireGuardKit imports it for
// `NEPacketTunnelNetworkSettings` etc. We provide minimal type stubs
// so the upstream code compiles unmodified on Linux.
import Foundation

/// Why the system stopped a tunnel (passed to `stopTunnel(with:)`).
public enum NEProviderStopReason: Int, Sendable {
    case none = 0, userInitiated = 1, providerFailed = 2, noNetworkAvailable = 3
    case unrecoverableNetworkChange = 4, providerDisabled = 5, authenticationCanceled = 6
    case configurationFailed = 7, idleTimeout = 8, configurationDisabled = 9
    case configurationRemoved = 10, superceded = 11, userLogout = 12, userSwitch = 13
    case connectionFailed = 14, sleep = 15, appUpdate = 16
}

// `open` so WireGuard's PacketTunnelProvider (a different module) can subclass it and
// override the lifecycle hooks. The bodies are compile-stubs — the extension only runs
// on macOS/iOS, never on Linux.
open class NEPacketTunnelProvider: NSObject {
    public var reasserting: Bool = false
    /// The saved provider configuration (cast to NETunnelProviderProtocol by callers).
    open var protocolConfiguration: NEVPNProtocol?
    open func setTunnelNetworkSettings(_ settings: NEPacketTunnelNetworkSettings?, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
    open func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
    }
    open func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    open func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        completionHandler?(nil)
    }
}

public class NEPacketTunnelNetworkSettings: NSObject {
    public var tunnelRemoteAddress: String
    public var ipv4Settings: NEIPv4Settings?
    public var ipv6Settings: NEIPv6Settings?
    public var dnsSettings: NEDNSSettings?
    public var mtu: NSNumber?
    // macOS uses tunnelOverheadBytes (vs iOS's mtu) — WireGuard's PacketTunnelSettingsGenerator.
    public var tunnelOverheadBytes: NSNumber?

    public init(tunnelRemoteAddress: String) {
        self.tunnelRemoteAddress = tunnelRemoteAddress
    }
}

public class NEIPv4Settings: NSObject {
    public var addresses: [String]
    public var subnetMasks: [String]
    public var includedRoutes: [NEIPv4Route]?
    public var excludedRoutes: [NEIPv4Route]?

    public init(addresses: [String], subnetMasks: [String]) {
        self.addresses = addresses
        self.subnetMasks = subnetMasks
    }
}

public class NEIPv4Route: NSObject {
    public var destinationAddress: String
    public var destinationSubnetMask: String
    public var gatewayAddress: String?
    public init(destinationAddress: String, subnetMask: String) {
        self.destinationAddress = destinationAddress
        self.destinationSubnetMask = subnetMask
    }
    public static var `default`: NEIPv4Route { NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0") }
}

public class NEIPv6Settings: NSObject {
    public var addresses: [String]
    public var networkPrefixLengths: [NSNumber]
    public var includedRoutes: [NEIPv6Route]?
    public var excludedRoutes: [NEIPv6Route]?

    public init(addresses: [String], networkPrefixLengths: [NSNumber]) {
        self.addresses = addresses
        self.networkPrefixLengths = networkPrefixLengths
    }
}

public class NEIPv6Route: NSObject {
    public var destinationAddress: String
    public var destinationNetworkPrefixLength: NSNumber
    public var gatewayAddress: String?
    public init(destinationAddress: String, networkPrefixLength: NSNumber) {
        self.destinationAddress = destinationAddress
        self.destinationNetworkPrefixLength = networkPrefixLength
    }
    public static var `default`: NEIPv6Route { NEIPv6Route(destinationAddress: "::", networkPrefixLength: 0) }
}

public class NEDNSSettings: NSObject {
    public var servers: [String]
    public var matchDomains: [String]?
    public var searchDomains: [String]?
    public init(servers: [String]) { self.servers = servers }
}
