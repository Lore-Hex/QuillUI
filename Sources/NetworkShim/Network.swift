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

public struct IPv4Address: IPAddress, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Data
    public init?(_ string: String) {
        guard let rawValue = parseIPv4AddressLiteral(string) else { return nil }
        self.rawValue = rawValue
    }
    /// Apple's matches this signature as `init?(_ rawValue: Data)`, so
    /// upstream code does `IPv4Address(bytes)!`.
    public init?(_ data: Data) {
        guard data.count == 4 else { return nil }
        self.rawValue = data
    }

    public var description: String {
        formatIPAddressLiteral(rawValue, family: AF_INET)
    }
}

public struct IPv6Address: IPAddress, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: Data
    public init?(_ string: String) {
        guard let rawValue = parseIPv6AddressLiteral(string) else { return nil }
        self.rawValue = rawValue
    }
    public init?(_ data: Data) {
        guard data.count == 16 else { return nil }
        self.rawValue = data
    }

    public var description: String {
        formatIPAddressLiteral(rawValue, family: AF_INET6)
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

    public struct Port: Hashable, Sendable, RawRepresentable, ExpressibleByIntegerLiteral, CustomStringConvertible {
        public let rawValue: UInt16
        public init?(_ string: String) {
            guard let rawValue = Self.parsePortString(string) else { return nil }
            self.rawValue = rawValue
        }
        public init?(rawValue: UInt16) { self.rawValue = rawValue }
        public init(integerLiteral value: UInt16) { self.rawValue = value }

        public var description: String {
            String(rawValue)
        }

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
}
