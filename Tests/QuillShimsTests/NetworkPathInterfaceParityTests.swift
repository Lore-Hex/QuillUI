import Dispatch
import Foundation
import Network
import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class NetworkPathInterfaceParityTests: XCTestCase {
    func testPathMonitorInitialCurrentPathMatchesApple() {
        for (context, monitor) in Self.makePathMonitors() {
            assertInitialPath(monitor.currentPath, context)
        }
    }

    func testPathMonitorPreStartCancelKeepsInitialCurrentPathMatchingApple() {
        for (context, monitor) in Self.makePathMonitors() {
            monitor.cancel()
            assertInitialPath(monitor.currentPath, context)
        }
    }

    #if os(Linux)
    func testPathMonitorStartReportsCurrentLinuxInterfaceSnapshot() {
        for (context, monitor) in Self.makePathMonitors() {
            let recorder = PathSnapshotRecorder()
            monitor.pathUpdateHandler = { path in
                recorder.record(PathSnapshot(path))
            }

            let queue = DispatchQueue(label: "quillui.network.path.\(context)")
            monitor.start(queue: queue)

            XCTAssertTrue(recorder.wait(timeout: .now() + 2.0), context)
            guard let delivered = recorder.load() else {
                XCTFail("Expected start(queue:) to deliver a path update for \(context)")
                continue
            }

            let current = PathSnapshot(monitor.currentPath)
            XCTAssertEqual(delivered, current, context)
            XCTAssertEqual(current.status == .satisfied, current.supportsIPv4 || current.supportsIPv6, context)
            XCTAssertEqual(current.supportsDNS && current.status != .satisfied, false, context)

            for interfaceType in Self.pathInterfaceTypes {
                let name = String(describing: interfaceType)
                XCTAssertEqual(
                    current.usedInterfaceTypes.contains(name),
                    current.interfaceTypes.contains(name),
                    "\(context) \(name)"
                )
            }
        }
    }
    #endif

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

    #if os(Linux)
    private struct PathSnapshot: Equatable {
        var status: NWPath.Status
        var unsatisfiedReason: NWPath.UnsatisfiedReason
        var interfaceDescriptions: [String]
        var interfaceTypes: [String]
        var usedInterfaceTypes: [String]
        var isExpensive: Bool
        var isConstrained: Bool
        var supportsIPv4: Bool
        var supportsIPv6: Bool
        var supportsDNS: Bool

        init(_ path: NWPath) {
            status = path.status
            unsatisfiedReason = path.unsatisfiedReason
            interfaceDescriptions = path.availableInterfaces
                .map { "\($0.name):\(String(describing: $0.type))" }
                .sorted()
            interfaceTypes = path.availableInterfaces
                .map { String(describing: $0.type) }
                .sorted()
            usedInterfaceTypes = NetworkPathInterfaceParityTests.pathInterfaceTypes
                .filter { path.usesInterfaceType($0) }
                .map { String(describing: $0) }
                .sorted()
            isExpensive = path.isExpensive
            isConstrained = path.isConstrained
            supportsIPv4 = path.supportsIPv4
            supportsIPv6 = path.supportsIPv6
            supportsDNS = path.supportsDNS
        }
    }

    private final class PathSnapshotRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var value: PathSnapshot?

        func record(_ snapshot: PathSnapshot) {
            lock.lock()
            value = snapshot
            lock.unlock()
            semaphore.signal()
        }

        func wait(timeout: DispatchTime) -> Bool {
            semaphore.wait(timeout: timeout) == .success
        }

        func load() -> PathSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
    #endif

    private func assertInitialPath(
        _ path: NWPath,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(path.status, .unsatisfied, context, file: file, line: line)
        XCTAssertEqual(path.unsatisfiedReason, .notAvailable, context, file: file, line: line)
        XCTAssertTrue(path.availableInterfaces.isEmpty, context, file: file, line: line)
        XCTAssertFalse(path.isExpensive, context, file: file, line: line)
        XCTAssertFalse(path.isConstrained, context, file: file, line: line)
        XCTAssertFalse(path.supportsIPv4, context, file: file, line: line)
        XCTAssertFalse(path.supportsIPv6, context, file: file, line: line)
        XCTAssertFalse(path.supportsDNS, context, file: file, line: line)

        for interfaceType in Self.pathInterfaceTypes {
            XCTAssertFalse(path.usesInterfaceType(interfaceType), "\(context) \(interfaceType)", file: file, line: line)
        }
    }

    private static let pathInterfaceTypes: [NWInterface.InterfaceType] = [
        .wifi,
        .cellular,
        .wiredEthernet,
        .loopback,
        .other,
    ]

    private static func makePathMonitors() -> [(String, NWPathMonitor)] {
        [("default", NWPathMonitor())] + pathInterfaceTypes.map {
            (String(describing: $0), NWPathMonitor(requiredInterfaceType: $0))
        }
    }
}
