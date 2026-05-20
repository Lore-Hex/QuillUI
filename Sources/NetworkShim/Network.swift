// Apple `Network` framework shim for Linux. WireGuardKit's
// DNSResolver imports it for NWInterface; we provide a minimal
// surface so upstream compiles unmodified.
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public final class NWPathMonitor: @unchecked Sendable {
    public typealias Status = NWPath.Status

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
    public enum Status: Hashable, Sendable, CustomStringConvertible {
        case satisfied, unsatisfied, requiresConnection

        public var description: String {
            switch self {
            case .satisfied:
                return "satisfied"
            case .unsatisfied:
                return "unsatisfied"
            case .requiresConnection:
                return "requiresConnection"
            }
        }
    }

    public var status: Status = .satisfied
    public var availableInterfaces: [NWInterface] = []
    public var isExpensive: Bool = false
    public var isConstrained: Bool = false
}

public struct NWInterface: Hashable, Sendable {
    public enum InterfaceType: Hashable, Sendable, CustomStringConvertible {
        case wifi, cellular, wiredEthernet, loopback, other

        public var description: String {
            switch self {
            case .wifi:
                return "wifi"
            case .cellular:
                return "cellular"
            case .wiredEthernet:
                return "wiredEthernet"
            case .loopback:
                return "loopback"
            case .other:
                return "other"
            }
        }
    }
    public var type: InterfaceType
    public init(type: InterfaceType) { self.type = type }
}

// MARK: - IPAddress / NWEndpoint shims for WireGuardKit

public protocol IPAddress {
    var rawValue: Data { get }
    init?(_ rawValue: Data, _ interface: NWInterface?)
    init?(_ string: String)
    var interface: NWInterface? { get }
    var isLoopback: Bool { get }
    var isLinkLocal: Bool { get }
    var isMulticast: Bool { get }
}

private func parseIPv4Component(_ component: Substring) -> UInt64? {
    guard !component.isEmpty else { return nil }

    var digits = component
    let radix: Int
    if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
        digits = digits.dropFirst(2)
        radix = 16
    } else if digits.count > 1 && digits.first == "0" {
        radix = 8
    } else {
        radix = 10
    }

    guard !digits.isEmpty else { return nil }
    guard digits.unicodeScalars.allSatisfy({
        switch radix {
        case 8:
            return (0x30...0x37).contains($0.value)
        case 10:
            return (0x30...0x39).contains($0.value)
        case 16:
            return (0x30...0x39).contains($0.value)
                || (0x41...0x46).contains($0.value)
                || (0x61...0x66).contains($0.value)
        default:
            return false
        }
    }) else { return nil }
    return UInt64(String(digits), radix: radix)
}

private func parseIPv4AddressLiteral(_ string: String) -> Data? {
    let components = string.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(components.count) else { return nil }
    let values = components.compactMap(parseIPv4Component)
    guard values.count == components.count else { return nil }

    let address: UInt64
    switch values.count {
    case 1:
        address = values[0] & 0xffff_ffff
    case 2:
        guard values[0] <= 0xff, values[1] <= 0xff_ffff else { return nil }
        address = (values[0] << 24) | values[1]
    case 3:
        guard values[0] <= 0xff, values[1] <= 0xff, values[2] <= 0xffff else { return nil }
        address = (values[0] << 24) | (values[1] << 16) | values[2]
    case 4:
        guard values.allSatisfy({ $0 <= 0xff }) else { return nil }
        address = (values[0] << 24) | (values[1] << 16) | (values[2] << 8) | values[3]
    default:
        return nil
    }

    return Data([
        UInt8((address >> 24) & 0xff),
        UInt8((address >> 16) & 0xff),
        UInt8((address >> 8) & 0xff),
        UInt8(address & 0xff),
    ])
}

private func parseIPv6AddressLiteral(_ string: String) -> Data? {
    let byteCount = 16
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let result = string.withCString { cString in
        bytes.withUnsafeMutableBytes { buffer in
            inet_pton(AF_INET6, cString, buffer.baseAddress!)
        }
    }
    guard result == 1 else { return nil }
    return Data(bytes)
}

private func formatIPAddressLiteral(_ data: Data, family: Int32) -> String {
    var bytes = [UInt8](data)
    var buffer = [CChar](repeating: 0, count: 46)
    return buffer.withUnsafeMutableBufferPointer { output in
        let result = bytes.withUnsafeMutableBytes { input -> UnsafePointer<CChar>? in
            guard let inputAddress = input.baseAddress else { return nil }
            return inet_ntop(family, inputAddress, output.baseAddress, socklen_t(output.count))
        }
        guard result != nil, let outputAddress = output.baseAddress else { return "" }
        return String(cString: outputAddress)
    }
}

public struct IPv4Address: IPAddress, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let any = IPv4Address(Data([0, 0, 0, 0]))!
    public static let broadcast = IPv4Address(Data([255, 255, 255, 255]))!
    public static let loopback = IPv4Address(Data([127, 0, 0, 1]))!
    public static let allHostsGroup = IPv4Address(Data([224, 0, 0, 1]))!
    public static let allRoutersGroup = IPv4Address(Data([224, 0, 0, 2]))!
    public static let allReportsGroup = IPv4Address(Data([224, 0, 0, 22]))!
    public static let mdnsGroup = IPv4Address(Data([224, 0, 0, 251]))!

    public var rawValue: Data
    public let interface: NWInterface?

    public init?(_ string: String) {
        guard let rawValue = parseIPv4AddressLiteral(string) else { return nil }
        self.rawValue = rawValue
        self.interface = nil
    }
    /// Apple's matches this signature as `init?(_ rawValue: Data)`, so
    /// upstream code does `IPv4Address(bytes)!`.
    public init?(_ data: Data, _ interface: NWInterface? = nil) {
        guard data.count == 4 else { return nil }
        self.rawValue = data
        self.interface = interface
    }

    public var isLoopback: Bool {
        rawValue.elementsEqual([127, 0, 0, 1])
    }

    public var isLinkLocal: Bool {
        rawValue[0] == 169 && rawValue[1] == 254
    }

    public var isMulticast: Bool {
        (224...239).contains(rawValue[0])
    }

    public var description: String {
        formatIPAddressLiteral(rawValue, family: AF_INET)
    }

    public var debugDescription: String {
        description
    }
}

public struct IPv6Address: IPAddress, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let any = IPv6Address(Data(Array(repeating: UInt8(0), count: 16)))!
    public static let broadcast = IPv6Address(Data(Array(repeating: UInt8(0), count: 16)))!
    public static let loopback = IPv6Address(Data(Array(repeating: UInt8(0), count: 15) + [1]))!
    public static let nodeLocalNodes = IPv6Address(Data([0xff, 0x01] + Array(repeating: UInt8(0), count: 13) + [1]))!
    public static let linkLocalNodes = IPv6Address(Data([0xff, 0x02] + Array(repeating: UInt8(0), count: 13) + [1]))!
    public static let linkLocalRouters = IPv6Address(Data([0xff, 0x02] + Array(repeating: UInt8(0), count: 13) + [2]))!

    public enum Scope: UInt8 {
        case nodeLocal = 1
        case linkLocal = 2
        case siteLocal = 5
        case organizationLocal = 8
        case global = 14
    }

    public var rawValue: Data
    public let interface: NWInterface?

    public init?(_ string: String) {
        guard let rawValue = parseIPv6AddressLiteral(string) else { return nil }
        self.rawValue = rawValue
        self.interface = nil
    }
    public init?(_ data: Data, _ interface: NWInterface? = nil) {
        guard data.count == 16 else { return nil }
        self.rawValue = data
        self.interface = interface
    }

    public var isAny: Bool {
        rawValue.allSatisfy { $0 == 0 }
    }

    public var isLoopback: Bool {
        rawValue.prefix(15).allSatisfy { $0 == 0 } && rawValue[15] == 1
    }

    public var isIPv4Compatabile: Bool {
        rawValue.prefix(12).allSatisfy { $0 == 0 } && !isAny && !isLoopback
    }

    public var isIPv4Mapped: Bool {
        rawValue.prefix(10).allSatisfy { $0 == 0 } && rawValue[10] == 0xff && rawValue[11] == 0xff
    }

    public var asIPv4: IPv4Address? {
        guard isIPv4Compatabile || isIPv4Mapped else { return nil }
        return IPv4Address(Data(rawValue.suffix(4)))
    }

    public var is6to4: Bool {
        rawValue[0] == 0x20 && rawValue[1] == 0x02
    }

    public var isLinkLocal: Bool {
        rawValue[0] == 0xfe && (rawValue[1] & 0xc0) == 0x80
    }

    public var isMulticast: Bool {
        rawValue[0] == 0xff
    }

    public var multicastScope: Scope? {
        guard isMulticast else { return nil }
        return Scope(rawValue: rawValue[1] & 0x0f)
    }

    public var isUniqueLocal: Bool {
        rawValue[0] == 0xfc || rawValue[0] == 0xfd
    }

    public var description: String {
        formatIPAddressLiteral(rawValue, family: AF_INET6)
    }

    public var debugDescription: String {
        description
    }
}

public enum NWEndpoint: Hashable, Sendable, CustomStringConvertible {
    public enum Host: Hashable, Sendable, CustomStringConvertible {
        case name(String, NWInterface?)
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)

        public init(_ string: String) {
            if let v4 = IPv4Address(string) { self = .ipv4(v4) }
            else if let v6 = IPv6Address(string) { self = .ipv6(v6) }
            else { self = .name(string, nil) }
        }

        public var description: String {
            switch self {
            case .name(let name, _):
                return name
            case .ipv4(let address):
                return address.description
            case .ipv6(let address):
                return address.description
            }
        }
    }

    public struct Port: Hashable, Sendable, RawRepresentable, ExpressibleByIntegerLiteral, CustomDebugStringConvertible {
        public let rawValue: UInt16
        public init?(_ string: String) {
            guard let rawValue = Self.parsePortString(string) else { return nil }
            self.rawValue = rawValue
        }
        public init?(rawValue: UInt16) { self.rawValue = rawValue }
        public init(integerLiteral value: UInt16) { self.rawValue = value }

        public var debugDescription: String {
            String(rawValue)
        }

        public static let any = Port(rawValue: 0)!
        public static let ssh = Port(rawValue: 22)!
        public static let smtp = Port(rawValue: 25)!
        public static let http = Port(rawValue: 80)!
        public static let pop = Port(rawValue: 110)!
        public static let imap = Port(rawValue: 143)!
        public static let https = Port(rawValue: 443)!
        public static let imaps = Port(rawValue: 993)!
        public static let socks = Port(rawValue: 1080)!

        private static func parsePortString(_ string: String) -> UInt16? {
            let scalars = Array(string.unicodeScalars)
            var index = scalars.startIndex

            while index < scalars.endIndex, isCWhitespace(scalars[index]) {
                index = scalars.index(after: index)
            }

            var isNegative = false
            if index < scalars.endIndex {
                if scalars[index] == "+" {
                    index = scalars.index(after: index)
                } else if scalars[index] == "-" {
                    isNegative = true
                    index = scalars.index(after: index)
                }
            }

            guard index < scalars.endIndex else { return nil }

            var value: UInt64 = 0
            while index < scalars.endIndex {
                let scalarValue = scalars[index].value
                guard scalarValue >= 48, scalarValue <= 57 else { return nil }
                value = value * 10 + UInt64(scalarValue - 48)
                guard value <= UInt64(UInt16.max) else { return nil }
                index = scalars.index(after: index)
            }

            if isNegative {
                guard value == 0 else { return nil }
            }
            return UInt16(value)
        }

        private static func isCWhitespace(_ scalar: Unicode.Scalar) -> Bool {
            scalar.value == 0x20 || (0x09...0x0d).contains(scalar.value)
        }
    }

    case hostPort(host: Host, port: Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    case unix(path: String)

    public var description: String {
        switch self {
        case .hostPort(let host, let port):
            let separator = host.isIPv6Literal ? "." : ":"
            return "\(host.description)\(separator)\(String(describing: port))"
        case .service(let name, let type, let domain, _):
            return Self.describeService(name: name, type: type, domain: domain)
        case .unix(let path):
            return path
        }
    }

    private static func describeService(name: String, type: String, domain: String) -> String {
        let normalizedName = trimDots(name)
        let normalizedType = trimDots(type)
        let normalizedDomain = trimDots(domain)

        if normalizedType.isEmpty {
            return [normalizedName, normalizedDomain]
                .filter { !$0.isEmpty }
                .joined(separator: ".")
        }

        let serviceTypeAndDomain: String
        if normalizedDomain.isEmpty {
            serviceTypeAndDomain = normalizedType
        } else if normalizedType.contains(".") {
            serviceTypeAndDomain = "\(normalizedType).\(normalizedDomain)."
        } else {
            serviceTypeAndDomain = "\(normalizedType)\(normalizedDomain)"
        }

        return [normalizedName, serviceTypeAndDomain]
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }

    private static func trimDots(_ value: String) -> String {
        var result = value
        while result.first == "." {
            result.removeFirst()
        }
        while result.last == "." {
            result.removeLast()
        }
        return result
    }
}

private extension NWEndpoint.Host {
    var isIPv6Literal: Bool {
        if case .ipv6 = self {
            return true
        }
        return false
    }
}
