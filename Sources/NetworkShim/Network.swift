// Apple `Network` framework shim for Linux. WireGuardKit's
// DNSResolver imports it for NWInterface; we provide a minimal
// surface so upstream compiles unmodified.
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public typealias DNSServiceErrorType = Int32

#if os(Linux)
public typealias OSStatus = Int32
#endif

private func networkEnumDebugDescription<T>(_ type: T.Type, caseName: String) -> String {
    "\(String(reflecting: type)).\(caseName)"
}

public enum NWError: Error, Equatable, Sendable, CustomDebugStringConvertible, LocalizedError {
    case posix(POSIXErrorCode)
    case dns(DNSServiceErrorType)
    case tls(OSStatus)

    public var debugDescription: String {
        let payload = descriptionPayload
        return "\(payload.codeDescription): \(payload.message)"
    }

    public var errorDescription: String? {
        let payload = descriptionPayload
        return "The operation couldn’t be completed. (Network.NWError error \(payload.localizedCode) - \(payload.message))"
    }

    private var descriptionPayload: NWErrorDescriptionPayload {
        switch self {
        case .posix(let code):
            let posix = darwinPOSIXDescription(for: code)
            return NWErrorDescriptionPayload(
                codeDescription: "POSIXErrorCode(rawValue: \(posix.rawValue))",
                localizedCode: posix.rawValue,
                message: posix.message
            )
        case .dns(let code):
            return NWErrorDescriptionPayload(
                codeDescription: "\(code)",
                localizedCode: code,
                message: dnsServiceMessage(for: code)
            )
        case .tls(let status):
            return NWErrorDescriptionPayload(
                codeDescription: "\(status)",
                localizedCode: status,
                message: tlsStatusMessage(for: status)
            )
        }
    }
}

private struct NWErrorDescriptionPayload {
    var codeDescription: String
    var localizedCode: Int32
    var message: String
}

private func darwinPOSIXDescription(for code: POSIXErrorCode) -> (rawValue: Int32, message: String) {
    switch code {
    case .EPIPE:
        return (32, "Broken pipe")
    case .EADDRINUSE:
        return (48, "Address already in use")
    case .EADDRNOTAVAIL:
        return (49, "Can't assign requested address")
    case .ENETDOWN:
        return (50, "Network is down")
    case .ENETUNREACH:
        return (51, "Network is unreachable")
    case .ENETRESET:
        return (52, "Network dropped connection on reset")
    case .ECONNABORTED:
        return (53, "Software caused connection abort")
    case .ECONNRESET:
        return (54, "Connection reset by peer")
    case .EISCONN:
        return (56, "Socket is already connected")
    case .ENOTCONN:
        return (57, "Socket is not connected")
    case .ESHUTDOWN:
        return (58, "Can't send after socket shutdown")
    case .ETIMEDOUT:
        return (60, "Operation timed out")
    case .ECONNREFUSED:
        return (61, "Connection refused")
    case .EHOSTDOWN:
        return (64, "Host is down")
    case .EHOSTUNREACH:
        return (65, "No route to host")
    default:
        let rawValue = Int32(code.rawValue)
        return (rawValue, posixMessage(for: rawValue))
    }
}

private func posixMessage(for rawValue: Int32) -> String {
    guard let messagePointer = strerror(rawValue) else {
        return "Unknown error: \(rawValue)"
    }
    return String(cString: messagePointer)
}

private func dnsServiceMessage(for code: DNSServiceErrorType) -> String {
    switch code {
    default:
        return "Unknown"
    }
}

private func tlsStatusMessage(for status: OSStatus) -> String {
    switch status {
    case -9807:
        return "invalid certificate chain"
    default:
        return "Unknown"
    }
}

public final class NWPathMonitor: @unchecked Sendable {
    public typealias Status = NWPath.Status

    public var pathUpdateHandler: (@Sendable (NWPath) -> Void)?
    public var currentPath: NWPath = NWPath(status: .unsatisfied)
    private let requiredInterfaceType: NWInterface.InterfaceType?

    public init() {
        self.requiredInterfaceType = nil
    }

    public init(requiredInterfaceType: NWInterface.InterfaceType) {
        self.requiredInterfaceType = requiredInterfaceType
    }

    public func start(queue: DispatchQueue) {
        let handler = pathUpdateHandler
        let path = currentLinuxPath(requiredInterfaceType: requiredInterfaceType)
        currentPath = path
        queue.async { handler?(path) }
    }

    public func cancel() {}
}

public struct NWPath: Sendable {
    public enum Status: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
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

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }
    }

    public enum UnsatisfiedReason: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case notAvailable, cellularDenied, wifiDenied, localNetworkDenied

        public var description: String {
            switch self {
            case .notAvailable:
                return "notAvailable"
            case .cellularDenied:
                return "cellularDenied"
            case .wifiDenied:
                return "wifiDenied"
            case .localNetworkDenied:
                return "localNetworkDenied"
            }
        }

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }
    }

    public var status: Status
    public var unsatisfiedReason: UnsatisfiedReason
    public var availableInterfaces: [NWInterface]
    public var isExpensive: Bool
    public var isConstrained: Bool
    public var supportsIPv4: Bool
    public var supportsIPv6: Bool
    public var supportsDNS: Bool

    public func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        availableInterfaces.contains { $0.type == type }
    }

    init(
        status: Status = .unsatisfied,
        unsatisfiedReason: UnsatisfiedReason = .notAvailable,
        availableInterfaces: [NWInterface] = [],
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        supportsIPv4: Bool = false,
        supportsIPv6: Bool = false,
        supportsDNS: Bool = false
    ) {
        self.status = status
        self.unsatisfiedReason = unsatisfiedReason
        self.availableInterfaces = availableInterfaces
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
        self.supportsDNS = supportsDNS
    }
}

public struct NWInterface: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum InterfaceType: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
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

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
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

public class NWProtocolOptions: @unchecked Sendable {
    init() {}
}

public enum NWProtocolTCP {
    public final class Options: NWProtocolOptions {
        public var noDelay = false
        public var noPush = false
        public var noOptions = false
        public var enableKeepalive = false
        public var keepaliveCount = 0
        public var keepaliveIdle = 0
        public var keepaliveInterval = 0
        public var maximumSegmentSize = 0
        public var connectionTimeout = 0
        public var persistTimeout = 0
        public var connectionDropTime = 0
        public var retransmitFinDrop = false
        public var disableAckStretching = false
        public var enableFastOpen = false
        public var disableECN = false

        public override init() {
            super.init()
        }

        fileprivate func copyForProtocolStack() -> Options {
            let copy = Options()
            copy.noDelay = noDelay
            copy.noPush = noPush
            copy.noOptions = noOptions
            copy.enableKeepalive = enableKeepalive
            copy.keepaliveCount = keepaliveCount
            copy.keepaliveIdle = keepaliveIdle
            copy.keepaliveInterval = keepaliveInterval
            copy.maximumSegmentSize = maximumSegmentSize
            copy.connectionTimeout = connectionTimeout
            copy.persistTimeout = persistTimeout
            copy.connectionDropTime = connectionDropTime
            copy.retransmitFinDrop = retransmitFinDrop
            copy.disableAckStretching = disableAckStretching
            copy.enableFastOpen = enableFastOpen
            copy.disableECN = disableECN
            return copy
        }
    }
}

public enum NWProtocolUDP {
    public final class Options: NWProtocolOptions {
        public var preferNoChecksum = false

        public override init() {
            super.init()
        }

        fileprivate func copyForProtocolStack() -> Options {
            let copy = Options()
            copy.preferNoChecksum = preferNoChecksum
            return copy
        }
    }
}

public enum NWProtocolTLS {
    public final class Options: NWProtocolOptions {
        public override init() {
            super.init()
        }

        fileprivate func copyForProtocolStack() -> Options {
            Options()
        }
    }
}

public enum NWProtocolIP {
    public final class Options: NWProtocolOptions {
        public enum Version: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
            case any, v4, v6

            public var description: String {
                switch self {
                case .any:
                    return "any"
                case .v4:
                    return "v4"
                case .v6:
                    return "v6"
                }
            }

            public var debugDescription: String {
                networkEnumDebugDescription(Self.self, caseName: description)
            }
        }

        public enum AddressPreference: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
            case `default`, temporary, stable

            public var description: String {
                switch self {
                case .default:
                    return "default"
                case .temporary:
                    return "temporary"
                case .stable:
                    return "stable"
                }
            }

            public var debugDescription: String {
                networkEnumDebugDescription(Self.self, caseName: description)
            }
        }

        public var version: Version = .any
        public var hopLimit: UInt8 = 0
        public var useMinimumMTU = false
        public var disableFragmentation = false
        public var shouldCalculateReceiveTime = false
        public var localAddressPreference: AddressPreference = .default
        public var disableMulticastLoopback = false

        override init() {
            super.init()
        }

        fileprivate func copyForProtocolStack() -> Options {
            let copy = Options()
            copy.version = version
            copy.hopLimit = hopLimit
            copy.useMinimumMTU = useMinimumMTU
            copy.disableFragmentation = disableFragmentation
            copy.shouldCalculateReceiveTime = shouldCalculateReceiveTime
            copy.localAddressPreference = localAddressPreference
            copy.disableMulticastLoopback = disableMulticastLoopback
            return copy
        }
    }

    public enum ECN: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case nonECT, ect0, ect1, ce

        public var description: String {
            switch self {
            case .nonECT:
                return "nonECT"
            case .ect0:
                return "ect0"
            case .ect1:
                return "ect1"
            case .ce:
                return "ce"
            }
        }

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }
    }
}

private func copiedProtocolOption(_ option: NWProtocolOptions?) -> NWProtocolOptions? {
    switch option {
    case let options as NWProtocolTCP.Options:
        return options.copyForProtocolStack()
    case let options as NWProtocolUDP.Options:
        return options.copyForProtocolStack()
    case let options as NWProtocolTLS.Options:
        return options.copyForProtocolStack()
    case let options as NWProtocolIP.Options:
        return options.copyForProtocolStack()
    case let option?:
        return option
    case nil:
        return nil
    }
}

private func copiedProtocolOptions(_ options: [NWProtocolOptions]) -> [NWProtocolOptions] {
    options.map { copiedProtocolOption($0) ?? $0 }
}

public final class NWParameters: @unchecked Sendable, CustomDebugStringConvertible {
    public enum Attribution: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case developer, user

        public var description: String {
            switch self {
            case .developer:
                return "developer"
            case .user:
                return "user"
            }
        }

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }

        fileprivate var debugToken: String {
            switch self {
            case .developer:
                return "developer"
            case .user:
                return "website"
            }
        }
    }

    public enum ExpiredDNSBehavior: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case systemDefault, allow, prohibit

        public var description: String {
            switch self {
            case .systemDefault:
                return "systemDefault"
            case .allow:
                return "allow"
            case .prohibit:
                return "prohibit"
            }
        }

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }
    }

    public enum MultipathServiceType: Int, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case disabled = 0, handover = 1, interactive = 2, aggregate = 3

        public var description: String {
            switch self {
            case .disabled:
                return "disabled"
            case .handover:
                return "handover"
            case .interactive:
                return "interactive"
            case .aggregate:
                return "aggregate"
            }
        }

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }
    }

    public enum ServiceClass: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case bestEffort, background, interactiveVideo, interactiveVoice, responsiveData, signaling

        public var description: String {
            switch self {
            case .bestEffort:
                return "bestEffort"
            case .background:
                return "background"
            case .interactiveVideo:
                return "interactiveVideo"
            case .interactiveVoice:
                return "interactiveVoice"
            case .responsiveData:
                return "responsiveData"
            case .signaling:
                return "signaling"
            }
        }

        public var debugDescription: String {
            networkEnumDebugDescription(Self.self, caseName: description)
        }

        fileprivate var trafficClass: Int? {
            switch self {
            case .bestEffort:
                return nil
            case .background:
                return 200
            case .interactiveVideo:
                return 700
            case .interactiveVoice:
                return 800
            case .responsiveData:
                return 300
            case .signaling:
                return 10002
            }
        }
    }

    private enum Transport: String {
        case tcp
        case udp
    }

    fileprivate final class ProtocolStackStorage {
        var applicationProtocols: [NWProtocolOptions]
        var transportProtocol: NWProtocolOptions?
        var internetProtocol: NWProtocolOptions?

        init(
            applicationProtocols: [NWProtocolOptions],
            transportProtocol: NWProtocolOptions?,
            internetProtocol: NWProtocolOptions?
        ) {
            self.applicationProtocols = applicationProtocols
            self.transportProtocol = transportProtocol
            self.internetProtocol = internetProtocol
        }
    }

    public final class ProtocolStack: @unchecked Sendable {
        private let storage: ProtocolStackStorage

        fileprivate init(storage: ProtocolStackStorage) {
            self.storage = storage
        }

        public var applicationProtocols: [NWProtocolOptions] {
            get { storage.applicationProtocols }
            set { storage.applicationProtocols = copiedProtocolOptions(newValue) }
        }

        public var transportProtocol: NWProtocolOptions? {
            get { storage.transportProtocol }
            set { storage.transportProtocol = copiedProtocolOption(newValue) }
        }

        public var internetProtocol: NWProtocolOptions? {
            get { storage.internetProtocol }
            set {
                if let newValue {
                    storage.internetProtocol = copiedProtocolOption(newValue)
                }
            }
        }
    }

    private let transport: Transport
    private let usesTLS: Bool
    private let protocolStackStorage: ProtocolStackStorage

    public var requiredInterfaceType: NWInterface.InterfaceType = .other
    private var storedProhibitedInterfaceTypes: [NWInterface.InterfaceType]?
    public var prohibitedInterfaceTypes: [NWInterface.InterfaceType]? {
        get { storedProhibitedInterfaceTypes }
        set {
            if let newValue, newValue.isEmpty {
                storedProhibitedInterfaceTypes = nil
            } else {
                storedProhibitedInterfaceTypes = newValue
            }
        }
    }
    public var requiredLocalEndpoint: NWEndpoint?
    public var allowLocalEndpointReuse = false
    public var includePeerToPeer = false
    public var serviceClass: ServiceClass = .bestEffort
    public var multipathServiceType: MultipathServiceType = .disabled
    public var expiredDNSBehavior: ExpiredDNSBehavior = .systemDefault
    public var allowFastOpen = false
    public var prohibitExpensivePaths = false
    public var prohibitConstrainedPaths = false
    public var requiresDNSSECValidation = false
    public var preferNoProxies = false
    public var attribution: Attribution = .developer

    private init(
        transport: Transport,
        usesTLS: Bool,
        transportProtocol: NWProtocolOptions? = nil,
        applicationProtocols: [NWProtocolOptions] = []
    ) {
        self.transport = transport
        self.usesTLS = usesTLS
        let defaultTransport = transportProtocol ?? {
            switch transport {
            case .tcp:
                return NWProtocolTCP.Options()
            case .udp:
                return NWProtocolUDP.Options()
            }
        }()
        let defaultApplicationProtocols = usesTLS && applicationProtocols.isEmpty
            ? [NWProtocolTLS.Options()]
            : applicationProtocols
        self.protocolStackStorage = ProtocolStackStorage(
            applicationProtocols: copiedProtocolOptions(defaultApplicationProtocols),
            transportProtocol: copiedProtocolOption(defaultTransport),
            internetProtocol: NWProtocolIP.Options()
        )
    }

    public convenience init(tls: NWProtocolTLS.Options?, tcp: NWProtocolTCP.Options) {
        self.init(
            transport: .tcp,
            usesTLS: tls != nil,
            transportProtocol: tcp,
            applicationProtocols: tls.map { [$0] } ?? []
        )
    }

    public convenience init(dtls: NWProtocolTLS.Options?, udp: NWProtocolUDP.Options) {
        self.init(
            transport: .udp,
            usesTLS: dtls != nil,
            transportProtocol: udp,
            applicationProtocols: dtls.map { [$0] } ?? []
        )
    }

    public static var tcp: NWParameters {
        NWParameters(transport: .tcp, usesTLS: false)
    }

    public static var udp: NWParameters {
        NWParameters(transport: .udp, usesTLS: false)
    }

    public static var tls: NWParameters {
        NWParameters(transport: .tcp, usesTLS: true)
    }

    public static var dtls: NWParameters {
        NWParameters(transport: .udp, usesTLS: true)
    }

    public var defaultProtocolStack: ProtocolStack {
        ProtocolStack(storage: protocolStackStorage)
    }

    public var debugDescription: String {
        var components = [transport.rawValue]
        if usesTLS {
            components.append("tls")
        }
        if let trafficClass = serviceClass.trafficClass {
            components.append("traffic class: \(trafficClass)")
        }
        if let requiredLocalEndpoint {
            components.append("local: \(debugDescription(for: requiredLocalEndpoint))")
        }
        if multipathServiceType != .disabled {
            components.append("multipath service: \(multipathServiceType.rawValue)")
        }
        if allowFastOpen {
            components.append("fast-open")
        }
        if prohibitExpensivePaths {
            components.append("no expensive")
        }
        if prohibitConstrainedPaths {
            components.append("no constrained")
        }
        if prohibitedInterfaceTypes?.contains(.cellular) == true {
            components.append("no cellular")
        }
        if preferNoProxies {
            components.append("prefer no proxy")
        }
        components.append("attribution: \(attribution.debugToken)")
        if requiresDNSSECValidation {
            components.append("requires DNSSEC validation")
        }
        return components.joined(separator: ", ")
    }

    private func debugDescription(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .unix(let path):
            return "AF_UNIX:\"\(path)\""
        default:
            return String(describing: endpoint)
        }
    }
}

private func currentLinuxPath(requiredInterfaceType: NWInterface.InterfaceType?) -> NWPath {
    var firstInterface: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstInterface) == 0, let firstInterface else {
        return NWPath(status: .unsatisfied)
    }
    defer { freeifaddrs(firstInterface) }

    var interfacesByName: [String: NWInterface] = [:]
    var supportsIPv4 = false
    var supportsIPv6 = false

    var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
    while let current = pointer {
        defer { pointer = current.pointee.ifa_next }

        let flags = UInt32(current.pointee.ifa_flags)
        guard flags & UInt32(IFF_UP) != 0,
              let address = current.pointee.ifa_addr,
              let namePointer = current.pointee.ifa_name
        else {
            continue
        }

        let name = String(cString: namePointer)
        let type = interfaceType(forInterfaceName: name)
        guard shouldIncludeInterface(type, requiredInterfaceType: requiredInterfaceType) else {
            continue
        }

        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            supportsIPv4 = true
        case AF_INET6:
            supportsIPv6 = true
        default:
            continue
        }

        interfacesByName[name] = NWInterface(name: name, type: type)
    }

    let availableInterfaces = interfacesByName.values.sorted {
        if $0.name == $1.name {
            return String(describing: $0.type) < String(describing: $1.type)
        }
        return $0.name < $1.name
    }
    let isSatisfied = !availableInterfaces.isEmpty && (supportsIPv4 || supportsIPv6)

    return NWPath(
        status: isSatisfied ? .satisfied : .unsatisfied,
        availableInterfaces: availableInterfaces,
        supportsIPv4: isSatisfied && supportsIPv4,
        supportsIPv6: isSatisfied && supportsIPv6,
        supportsDNS: isSatisfied && linuxResolverLooksConfigured()
    )
}

private func shouldIncludeInterface(
    _ type: NWInterface.InterfaceType,
    requiredInterfaceType: NWInterface.InterfaceType?
) -> Bool {
    if let requiredInterfaceType {
        return type == requiredInterfaceType
    }
    return type != .loopback
}

private func linuxResolverLooksConfigured() -> Bool {
    guard let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else { return false }
    return contents.split(whereSeparator: \.isNewline).contains { line in
        String(line).trimmingCharacters(in: .whitespaces).hasPrefix("nameserver")
    }
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
    if lowercasedName.hasPrefix("wl")
        || lowercasedName.hasPrefix("wlan")
        || lowercasedName.hasPrefix("wifi")
        || lowercasedName.hasPrefix("ath")
    {
        return .wifi
    }
    if lowercasedName.hasPrefix("wwan")
        || lowercasedName.hasPrefix("rmnet")
        || lowercasedName.hasPrefix("pdp_ip")
        || lowercasedName.hasPrefix("cell")
    {
        return .cellular
    }
    if lowercasedName.hasPrefix("en")
        || lowercasedName.hasPrefix("eth")
        || lowercasedName.hasPrefix("eno")
        || lowercasedName.hasPrefix("ens")
        || lowercasedName.hasPrefix("enp")
    {
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

// MARK: - NWConnection / NWListener
//
// The transport endpoints SignalProxy uses (the local relay/proxy fronting the
// censorship-circumvention path). INERT on Linux: a connection never leaves
// `.setup` (it never actually connects), send-completions fire immediately with
// no error (nothing is transmitted), and receive never delivers data. SignalProxy
// is therefore a no-op on Linux until a real Network backend is wired up.
// HONEST STATUS: the proxy never connects; these exist only so SignalProxy compiles.

public final class NWConnection: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled
    }

    public final class ContentContext: @unchecked Sendable {
        public let identifier: String
        public init(identifier: String) { self.identifier = identifier }
        public static let defaultMessage = ContentContext(identifier: "defaultMessage")
        public static let finalMessage = ContentContext(identifier: "finalMessage")
    }

    public enum SendCompletion {
        case idempotent
        case contentProcessed((NWError?) -> Void)
    }

    public let endpoint: NWEndpoint
    public let parameters: NWParameters
    public var stateUpdateHandler: ((State) -> Void)?
    public var viabilityUpdateHandler: ((Bool) -> Void)?
    public var betterPathUpdateHandler: ((Bool) -> Void)?
    public private(set) var state: State = .setup

    public init(to endpoint: NWEndpoint, using parameters: NWParameters) {
        self.endpoint = endpoint
        self.parameters = parameters
    }
    public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters) {
        self.init(to: .hostPort(host: host, port: port), using: parameters)
    }

    /// Inert: never transitions to `.ready` (no real connection on Linux).
    public func start(queue: DispatchQueue) {}
    public func cancel() {
        state = .cancelled
        stateUpdateHandler?(.cancelled)
    }
    public func forceCancel() { cancel() }
    public func restart() {}

    public func send(
        content: Data?,
        contentContext: ContentContext = .defaultMessage,
        isComplete: Bool = true,
        completion: SendCompletion
    ) {
        // Pretend the write succeeded; nothing is actually transmitted.
        if case let .contentProcessed(handler) = completion {
            handler(nil)
        }
    }

    /// Inert: no data is ever delivered (no isComplete, no error) on Linux.
    public func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping (Data?, ContentContext?, Bool, NWError?) -> Void
    ) {}
}

public final class NWListener: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case ready
        case failed(NWError)
        case cancelled
    }

    public let parameters: NWParameters
    public var stateUpdateHandler: ((State) -> Void)?
    public var newConnectionHandler: ((NWConnection) -> Void)?
    public var port: NWEndpoint.Port?

    public init(using parameters: NWParameters, on port: NWEndpoint.Port = .any) throws {
        self.parameters = parameters
        self.port = port
    }

    /// Inert: never becomes `.ready` (no real listener on Linux).
    public func start(queue: DispatchQueue) {}
    public func cancel() {
        stateUpdateHandler?(.cancelled)
    }
}
