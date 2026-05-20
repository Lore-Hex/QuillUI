import Network
import XCTest

final class NetworkPathInterfaceParityTests: XCTestCase {
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
}
