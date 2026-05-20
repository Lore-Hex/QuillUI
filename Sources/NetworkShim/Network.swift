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
    public var currentPath: NWPath = NWPath(status: .unsatisfied)

    public init() {}
    public init(requiredInterfaceType: NWInterface.InterfaceType) {}

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

    public enum UnsatisfiedReason: Hashable, Sendable {
        case notAvailable, cellularDenied, wifiDenied, localNetworkDenied
    }

    public var status: Status
    public var unsatisfiedReason: UnsatisfiedReason
    public var availableInterfaces: [NWInterface]
    public var isExpensive: Bool
    public var isConstrained: Bool

    init(
        status: Status = .unsatisfied,
        unsatisfiedReason: UnsatisfiedReason = .notAvailable,
        availableInterfaces: [NWInterface] = [],
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.status = status
        self.unsatisfiedReason = unsatisfiedReason
        self.availableInterfaces = availableInterfaces
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

public struct NWInterface: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
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
    public var name: String

    public init(type: InterfaceType) {
        self.type = type
        self.name = type.description
    }

    fileprivate init(name: String, type: InterfaceType = .other) {
        self.type = type
        self.name = name
    }

    public var description: String { name }
    public var debugDescription: String { description }
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

private func ipv4DigitValue(_ scalar: Unicode.Scalar, radix: Int) -> UInt64? {
    let value = scalar.value
    let digit: UInt64?
    switch value {
    case 0x30...0x39:
        digit = UInt64(value - 0x30)
    case 0x41...0x46:
        digit = UInt64(value - 0x41 + 10)
    case 0x61...0x66:
        digit = UInt64(value - 0x61 + 10)
    default:
        digit = nil
    }

    guard let digit, digit < UInt64(radix) else { return nil }
    return digit
}

private func parseIPv4Digits(_ digits: Substring, radix: Int, maximum: UInt64) -> UInt64? {
    guard !digits.isEmpty else { return nil }

    var value: UInt64 = 0
    for scalar in digits.unicodeScalars {
        guard let digit = ipv4DigitValue(scalar, radix: radix) else { return nil }
        guard value <= (maximum - digit) / UInt64(radix) else { return nil }
        value = value * UInt64(radix) + digit
    }
    return value
}

private func parseIPv4DigitsWrapping(_ digits: Substring, radix: Int) -> UInt64? {
    guard !digits.isEmpty else { return nil }

    var value: UInt64 = 0
    for scalar in digits.unicodeScalars {
        guard let digit = ipv4DigitValue(scalar, radix: radix) else { return nil }
        value = (value * UInt64(radix) + digit) & 0xffff_ffff
    }
    return value
}

private func parseIPv4Component(
    _ component: Substring,
    componentIndex: Int,
    componentCount: Int,
    maximum: UInt64
) -> UInt64? {
    guard !component.isEmpty else { return nil }

    var digits = component
    if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
        digits = digits.dropFirst(2)
        if componentCount == 1 {
            return parseIPv4DigitsWrapping(digits, radix: 16)
        }
        if digits.isEmpty {
            guard componentIndex < componentCount - 1 else { return nil }
            return 0
        }
        return parseIPv4Digits(digits, radix: 16, maximum: maximum)
    }

    if componentCount == 1 {
        let radix = digits.count > 1 && digits.first == "0" ? 8 : 10
        return parseIPv4DigitsWrapping(digits, radix: radix)
    }

    if componentCount == 4, digits.count > 1, digits.first == "0" {
        if let decimalValue = parseIPv4Digits(digits, radix: 10, maximum: maximum) {
            return decimalValue
        }
        return parseIPv4Digits(digits, radix: 8, maximum: maximum)
    }

    if digits.count > 1 && digits.first == "0" {
        return parseIPv4Digits(digits, radix: 8, maximum: maximum)
    } else {
        return parseIPv4Digits(digits, radix: 10, maximum: maximum)
    }
}

private func parseIPv4AddressLiteral(_ string: String) -> (Data, NWInterface?)? {
    if let scoped = splitInterfaceScope(string) {
        guard !scoped.prefix.contains("%"),
              let rawValue = parseUnscopedIPv4AddressLiteral(scoped.prefix)
        else {
            return nil
        }
        return (rawValue, scoped.interface)
    }
    guard let rawValue = parseUnscopedIPv4AddressLiteral(string) else { return nil }
    return (rawValue, nil)
}

private func parseUnscopedIPv4AddressLiteral(_ string: String) -> Data? {
    let components = string.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...4).contains(components.count) else { return nil }
    let maximums: [UInt64]
    switch components.count {
    case 1:
        maximums = [0xffff_ffff]
    case 2:
        maximums = [0xff, 0xff_ffff]
    case 3:
        maximums = [0xff, 0xff, 0xffff]
    case 4:
        maximums = [0xff, 0xff, 0xff, 0xff]
    default:
        return nil
    }

    var values: [UInt64] = []
    values.reserveCapacity(components.count)
    for (index, component) in components.enumerated() {
        guard let value = parseIPv4Component(
            component,
            componentIndex: index,
            componentCount: components.count,
            maximum: maximums[index]
        ) else {
            return nil
        }
        values.append(value)
    }

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

private func parseIPv6AddressLiteral(_ string: String) -> (Data, NWInterface?)? {
    if let scoped = splitInterfaceScope(string) {
        guard let rawValue = parseIPv6AddressBase(scoped.prefix) else { return nil }
        return (rawValue, scoped.interface)
    }

    if let rawValue = parseUnscopedIPv6AddressLiteral(string) {
        return (rawValue, nil)
    }

    if let percent = string.lastIndex(of: "%") {
        let prefix = String(string[..<percent])
        guard !prefix.contains("%"),
              let rawValue = parseUnscopedIPv6AddressLiteral(prefix)
        else {
            return nil
        }
        return (rawValue, nil)
    }

    return nil
}

private func parseIPv6AddressBase(_ string: String) -> Data? {
    if let rawValue = parseUnscopedIPv6AddressLiteral(string) {
        return rawValue
    }

    guard let percent = string.lastIndex(of: "%") else { return nil }
    let prefix = String(string[..<percent])
    let suffix = string[string.index(after: percent)...]
    if suffix.isEmpty {
        guard !prefix.contains("%") else { return nil }
        return parseUnscopedIPv6AddressLiteral(prefix)
    }

    return parseUnscopedIPv6AddressLiteral(prefix)
}

private func parseUnscopedIPv6AddressLiteral(_ string: String) -> Data? {
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

private func splitInterfaceScope(_ string: String) -> (prefix: String, interface: NWInterface)? {
    guard let percent = string.lastIndex(of: "%") else { return nil }
    let scope = String(string[string.index(after: percent)...])
    guard let interface = resolveInterfaceScope(scope) else { return nil }
    return (String(string[..<percent]), interface)
}

private func resolveInterfaceScope(_ scope: String) -> NWInterface? {
    guard !scope.isEmpty else { return nil }

    if scope.allSatisfy(\.isNumber) {
        guard let index = UInt32(scope), index > 0 else { return nil }
        guard let name = interfaceName(forIndex: index) else { return nil }
        return NWInterface(name: name, type: interfaceType(forInterfaceName: name))
    }

    let index = scope.withCString { if_nametoindex($0) }
    guard index != 0 else { return nil }
    return NWInterface(name: scope, type: interfaceType(forInterfaceName: scope))
}

private func interfaceName(forIndex index: UInt32) -> String? {
    var buffer = [CChar](repeating: 0, count: 64)
    let result = buffer.withUnsafeMutableBufferPointer { nameBuffer in
        if_indextoname(index, nameBuffer.baseAddress)
    }
    guard result != nil else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

private func interfaceType(forInterfaceName name: String) -> NWInterface.InterfaceType {
    let lowercasedName = name.lowercased()
    if lowercasedName == "lo" || lowercasedName.hasPrefix("lo") {
        return .loopback
    }
    if lowercasedName.hasPrefix("en") || lowercasedName.hasPrefix("eth") {
        return .wiredEthernet
    }
    return .other
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

private func appendInterfaceScope(_ value: String, _ interface: NWInterface?) -> String {
    guard let interface else { return value }
    return "\(value)%\(interface.name)"
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
        guard let (rawValue, interface) = parseIPv4AddressLiteral(string) else { return nil }
        self.rawValue = rawValue
        self.interface = interface
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
        appendInterfaceScope(formatIPAddressLiteral(rawValue, family: AF_INET), interface)
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
        guard let (rawValue, interface) = parseIPv6AddressLiteral(string) else { return nil }
        self.rawValue = rawValue
        self.interface = interface
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
        return IPv4Address(Data(rawValue.suffix(4)), interface)
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
        appendInterfaceScope(formatIPAddressLiteral(rawValue, family: AF_INET6), interface)
    }

    public var debugDescription: String {
        description
    }
}

public enum NWEndpoint: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Host: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case name(String, NWInterface?)
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)

        public init(_ string: String) {
            if string.isEmpty {
                self = .name(".", nil)
            } else if let v4 = IPv4Address(string) {
                self = .ipv4(v4)
            } else if let v6 = IPv6Address(string) {
                if v6.isIPv4Mapped, let mappedAddress = v6.asIPv4 {
                    self = .ipv4(mappedAddress)
                } else {
                    self = .ipv6(v6)
                }
            } else if let scoped = splitInterfaceScope(string) {
                self = .name(scoped.prefix, scoped.interface)
            } else {
                self = .name(string, nil)
            }
        }

        public var description: String {
            switch self {
            case .name(let name, let interface):
                return appendInterfaceScope(name, interface)
            case .ipv4(let address):
                return address.description
            case .ipv6(let address):
                return address.description
            }
        }

        public var debugDescription: String {
            description
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
        case .service(let name, let type, let domain, let interface):
            return Self.describeService(name: name, type: type, domain: domain, interface: interface)
        case .unix(let path):
            return path
        }
    }

    public var debugDescription: String {
        description
    }

    private static func describeService(name: String, type: String, domain: String, interface: NWInterface?) -> String {
        let normalizedType = trimTrailingDots(type)

        guard isValidDNSServiceType(normalizedType) else {
            return appendInterfaceScope("\(name).\(type)\(domain)", interface)
        }

        var result = ""
        if name.isEmpty {
            if domain.isEmpty {
                result += "."
            }
        } else {
            result += escapeDNSServiceName(name)
            result += "."
        }

        result += normalizedType

        if !domain.isEmpty {
            result += "."
            result += trimTrailingDots(domain)
            result += "."
        }

        if let interface {
            if domain.isEmpty {
                return appendInterfaceScope(result, interface)
            }
            return "\(result)@\(interface.name)"
        }

        return result
    }

    private static func trimTrailingDots(_ value: String) -> String {
        var result = value
        while result.last == "." {
            result.removeLast()
        }
        return result
    }

    private static func isValidDNSServiceType(_ type: String) -> Bool {
        let labels = type.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 2 || (labels.count == 3 && labels.first == "") else {
            return false
        }
        guard let service = labels.dropLast().last,
              let transport = labels.last,
              service.hasPrefix("_") else {
            return false
        }
        return transport == "_tcp" || transport == "_udp"
    }

    private static func escapeDNSServiceName(_ name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars {
            if scalar == "." {
                result += "\\."
            } else if scalar == "\\" {
                result += "\\\\"
            } else if scalar.value <= 0x20 {
                result += String(format: "\\%03u", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
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
