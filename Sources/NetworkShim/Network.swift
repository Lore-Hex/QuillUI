// Apple `Network` framework shim for Linux. WireGuardKit's
// DNSResolver imports it for NWInterface; we provide a minimal
// surface so upstream compiles unmodified.
import Foundation

public final class NWPathMonitor: @unchecked Sendable {
    public enum Status: Sendable {
        case satisfied, unsatisfied, requiresConnection
    }

    public var pathUpdateHandler: (@Sendable (NWPath) -> Void)?
    public var currentPath: NWPath = NWPath()

    public init() {}
    public init(requiredInterfaceType: Any) {}

    public func start(queue: DispatchQueue) {
        let handler = pathUpdateHandler
        let path = currentPath
        queue.async { handler?(path) }
    }

    public func cancel() {}
}

public struct NWPath: Sendable {
    public var status: NWPathMonitor.Status = .satisfied
    public var availableInterfaces: [NWInterface] = []
    public var isExpensive: Bool = false
    public var isConstrained: Bool = false
}

public struct NWInterface: Hashable, Sendable {
    public enum InterfaceType: Hashable, Sendable {
        case wifi, cellular, wiredEthernet, loopback, other
    }
    public var type: InterfaceType
    public init(type: InterfaceType) { self.type = type }
}

// MARK: - IPAddress / NWEndpoint shims for WireGuardKit

public protocol IPAddress {
    var rawValue: Data { get }
}

public struct IPv4Address: IPAddress, Hashable, Sendable {
    public var rawValue: Data
    public init?(_ string: String) {
        let parts = string.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        self.rawValue = Data(parts)
    }
    /// Apple's matches this signature as `init?(_ rawValue: Data)`, so
    /// upstream code does `IPv4Address(bytes)!`.
    public init?(_ data: Data) {
        guard data.count == 4 else { return nil }
        self.rawValue = data
    }
}

public struct IPv6Address: IPAddress, Hashable, Sendable {
    public var rawValue: Data
    public init?(_ string: String) {
        // Minimal stub — sufficient for upstream Endpoint/DNS parsing.
        self.rawValue = Data(repeating: 0, count: 16)
    }
    public init?(_ data: Data) {
        guard data.count == 16 else { return nil }
        self.rawValue = data
    }
}

public enum NWEndpoint: Hashable, Sendable {
    public enum Host: Hashable, Sendable {
        case name(String, NWInterface?)
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)

        public init(_ string: String) {
            if let v4 = IPv4Address(string) { self = .ipv4(v4) }
            else if let v6 = IPv6Address(string) { self = .ipv6(v6) }
            else { self = .name(string, nil) }
        }
    }

    public struct Port: Hashable, Sendable {
        public let rawValue: UInt16
        public init?(_ string: String) {
            guard let v = UInt16(string) else { return nil }
            self.rawValue = v
        }
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public init(integerLiteral value: UInt16) { self.rawValue = value }
    }

    case hostPort(host: Host, port: Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    case unix(path: String)
}
