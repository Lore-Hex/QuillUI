import Foundation
import Network
import XCTest

final class NetworkErrorParityTests: XCTestCase {
    func testNWErrorPOSIXSurfaceMatchesApple() {
        let error = NWError.posix(.ECONNREFUSED)

        assertSendable(error)
        assertDebugStringConvertible(error, "POSIXErrorCode(rawValue: 61): Connection refused")
        XCTAssertEqual(String(describing: error), "POSIXErrorCode(rawValue: 61): Connection refused")
        XCTAssertEqual(String(reflecting: error), "POSIXErrorCode(rawValue: 61): Connection refused")
        XCTAssertEqual(error.localizedDescription, "The operation couldn’t be completed. (Network.NWError error 61 - Connection refused)")
        XCTAssertEqual(error, .posix(.ECONNREFUSED))
        XCTAssertNotEqual(error, .posix(.ECONNRESET))
    }

    func testNWErrorTLSSurfaceMatchesApple() {
        let error = NWError.tls(-9807)

        assertSendable(error)
        assertDebugStringConvertible(error, "-9807: invalid certificate chain")
        XCTAssertEqual(String(describing: error), "-9807: invalid certificate chain")
        XCTAssertEqual(String(reflecting: error), "-9807: invalid certificate chain")
        XCTAssertEqual(error.localizedDescription, "The operation couldn’t be completed. (Network.NWError error -9807 - invalid certificate chain)")
        XCTAssertEqual(error, .tls(-9807))
        XCTAssertNotEqual(error, .tls(-9806))
    }

    func testNWErrorDNSSurfaceMatchesApple() {
        let code: DNSServiceErrorType = -65537
        let error = NWError.dns(code)

        assertSendable(error)
        assertDebugStringConvertible(error, "-65537: Unknown")
        XCTAssertEqual(String(describing: error), "-65537: Unknown")
        XCTAssertEqual(String(reflecting: error), "-65537: Unknown")
        XCTAssertEqual(error.localizedDescription, "The operation couldn’t be completed. (Network.NWError error -65537 - Unknown)")
        XCTAssertEqual(error, .dns(code))
        XCTAssertNotEqual(error, .dns(-65538))
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }

    private func assertDebugStringConvertible<T: CustomDebugStringConvertible>(
        _ value: T,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value.debugDescription, expected, file: file, line: line)
    }
}
