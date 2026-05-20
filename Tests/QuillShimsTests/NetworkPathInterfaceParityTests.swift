import Network
import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class NetworkPathInterfaceParityTests: XCTestCase {
    func testPathMonitorInitialCurrentPathMatchesApple() {
        let monitors: [(String, NWPathMonitor)] = [
            ("default", NWPathMonitor()),
            ("wifi", NWPathMonitor(requiredInterfaceType: .wifi)),
            ("cellular", NWPathMonitor(requiredInterfaceType: .cellular)),
            ("wiredEthernet", NWPathMonitor(requiredInterfaceType: .wiredEthernet)),
            ("loopback", NWPathMonitor(requiredInterfaceType: .loopback)),
            ("other", NWPathMonitor(requiredInterfaceType: .other)),
        ]

        for (context, monitor) in monitors {
            let path = monitor.currentPath
            XCTAssertEqual(path.status, .unsatisfied, context)
            XCTAssertEqual(path.unsatisfiedReason, .notAvailable, context)
            XCTAssertTrue(path.availableInterfaces.isEmpty, context)
            XCTAssertFalse(path.isExpensive, context)
            XCTAssertFalse(path.isConstrained, context)
        }
    }

    func testPathStatusStringDescriptionsMatchApple() {
        let cases: [(NWPath.Status, String)] = [
            (.satisfied, "satisfied"),
            (.unsatisfied, "unsatisfied"),
            (.requiresConnection, "requiresConnection"),
        ]

        for (status, expected) in cases {
            XCTAssertEqual(String(describing: status), expected)
        }
    }

    func testPathStatusEqualityAndHashingMatchApple() {
        let equivalentPairs: [(NWPath.Status, NWPath.Status)] = [
            (.satisfied, .satisfied),
            (.unsatisfied, .unsatisfied),
            (.requiresConnection, .requiresConnection),
        ]

        for (lhs, rhs) in equivalentPairs {
            XCTAssertEqual(lhs, rhs)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        }

        XCTAssertNotEqual(NWPath.Status.satisfied, NWPath.Status.unsatisfied)
        XCTAssertNotEqual(NWPath.Status.satisfied, NWPath.Status.requiresConnection)
        XCTAssertNotEqual(NWPath.Status.unsatisfied, NWPath.Status.requiresConnection)
    }

    func testPathUnsatisfiedReasonStringDescriptionsMatchApple() {
        let cases: [(NWPath.UnsatisfiedReason, String)] = [
            (.notAvailable, "notAvailable"),
            (.cellularDenied, "cellularDenied"),
            (.wifiDenied, "wifiDenied"),
            (.localNetworkDenied, "localNetworkDenied"),
        ]

        for (reason, expected) in cases {
            XCTAssertEqual(String(describing: reason), expected)
        }
    }

    func testPathUnsatisfiedReasonEqualityAndHashingMatchApple() {
        let equivalentPairs: [(NWPath.UnsatisfiedReason, NWPath.UnsatisfiedReason)] = [
            (.notAvailable, .notAvailable),
            (.cellularDenied, .cellularDenied),
            (.wifiDenied, .wifiDenied),
            (.localNetworkDenied, .localNetworkDenied),
        ]

        for (lhs, rhs) in equivalentPairs {
            XCTAssertEqual(lhs, rhs)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        }

        XCTAssertNotEqual(NWPath.UnsatisfiedReason.notAvailable, NWPath.UnsatisfiedReason.cellularDenied)
        XCTAssertNotEqual(NWPath.UnsatisfiedReason.notAvailable, NWPath.UnsatisfiedReason.wifiDenied)
        XCTAssertNotEqual(NWPath.UnsatisfiedReason.notAvailable, NWPath.UnsatisfiedReason.localNetworkDenied)
        XCTAssertNotEqual(NWPath.UnsatisfiedReason.cellularDenied, NWPath.UnsatisfiedReason.wifiDenied)
        XCTAssertNotEqual(NWPath.UnsatisfiedReason.cellularDenied, NWPath.UnsatisfiedReason.localNetworkDenied)
        XCTAssertNotEqual(NWPath.UnsatisfiedReason.wifiDenied, NWPath.UnsatisfiedReason.localNetworkDenied)
    }

    func testInterfaceTypeStringDescriptionsMatchApple() {
        let cases: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "wifi"),
            (.cellular, "cellular"),
            (.wiredEthernet, "wiredEthernet"),
            (.loopback, "loopback"),
            (.other, "other"),
        ]

        for (interfaceType, expected) in cases {
            XCTAssertEqual(String(describing: interfaceType), expected)
        }
    }

    func testInterfaceTypeEqualityAndHashingMatchApple() {
        let equivalentPairs: [(NWInterface.InterfaceType, NWInterface.InterfaceType)] = [
            (.wifi, .wifi),
            (.cellular, .cellular),
            (.wiredEthernet, .wiredEthernet),
            (.loopback, .loopback),
            (.other, .other),
        ]

        for (lhs, rhs) in equivalentPairs {
            XCTAssertEqual(lhs, rhs)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        }

        XCTAssertNotEqual(NWInterface.InterfaceType.wifi, NWInterface.InterfaceType.cellular)
        XCTAssertNotEqual(NWInterface.InterfaceType.wifi, NWInterface.InterfaceType.wiredEthernet)
        XCTAssertNotEqual(NWInterface.InterfaceType.wifi, NWInterface.InterfaceType.loopback)
        XCTAssertNotEqual(NWInterface.InterfaceType.wifi, NWInterface.InterfaceType.other)
        XCTAssertNotEqual(NWInterface.InterfaceType.cellular, NWInterface.InterfaceType.wiredEthernet)
        XCTAssertNotEqual(NWInterface.InterfaceType.cellular, NWInterface.InterfaceType.loopback)
        XCTAssertNotEqual(NWInterface.InterfaceType.cellular, NWInterface.InterfaceType.other)
        XCTAssertNotEqual(NWInterface.InterfaceType.wiredEthernet, NWInterface.InterfaceType.loopback)
        XCTAssertNotEqual(NWInterface.InterfaceType.wiredEthernet, NWInterface.InterfaceType.other)
        XCTAssertNotEqual(NWInterface.InterfaceType.loopback, NWInterface.InterfaceType.other)
    }

    func testResolvedScopedInterfaceValuesMatchApple() throws {
        let loopbackName = try XCTUnwrap(Self.interfaceName(forIndex: 1))
        let namedIPv6Interface = try XCTUnwrap(IPv6Address("fe80::1%\(loopbackName)")?.interface)
        let indexedIPv6Interface = try XCTUnwrap(IPv6Address("fe80::1%1")?.interface)
        let namedIPv4Interface = try XCTUnwrap(IPv4Address("192.0.2.1%\(loopbackName)")?.interface)

        guard case let .name(name, hostInterface?) = NWEndpoint.Host("example.com%\(loopbackName)") else {
            return XCTFail("Expected scoped host literal to resolve a named interface")
        }

        XCTAssertEqual(name, "example.com")

        let interfaces = [
            namedIPv6Interface,
            indexedIPv6Interface,
            namedIPv4Interface,
            hostInterface,
        ]

        for interface in interfaces {
            XCTAssertEqual(interface.name, loopbackName)
            XCTAssertEqual(interface.type, .loopback)
            XCTAssertEqual(String(describing: interface), loopbackName)
            XCTAssertEqual(interface.debugDescription, loopbackName)
        }

        let equalPairs: [(NWInterface, NWInterface, String)] = [
            (namedIPv6Interface, indexedIPv6Interface, "IPv6 name and numeric scope"),
            (namedIPv6Interface, namedIPv4Interface, "IPv6 and IPv4 scoped literals"),
            (namedIPv6Interface, hostInterface, "address and host scoped literals"),
        ]

        for (lhs, rhs, context) in equalPairs {
            XCTAssertEqual(lhs, rhs, context)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue, context)
        }
    }

    private static func interfaceName(forIndex index: UInt32) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        let result = buffer.withUnsafeMutableBufferPointer { nameBuffer in
            if_indextoname(index, nameBuffer.baseAddress)
        }
        guard result != nil else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
