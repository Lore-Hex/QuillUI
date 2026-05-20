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
}
