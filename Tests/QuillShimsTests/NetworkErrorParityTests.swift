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

    func testNWErrorCommonPOSIXNetworkPayloadsMatchApple() {
        let cases: [(POSIXErrorCode, Int32, String)] = [
            (.EPIPE, 32, "Broken pipe"),
            (.EADDRINUSE, 48, "Address already in use"),
            (.EADDRNOTAVAIL, 49, "Can't assign requested address"),
            (.ENETDOWN, 50, "Network is down"),
            (.ENETUNREACH, 51, "Network is unreachable"),
            (.ENETRESET, 52, "Network dropped connection on reset"),
            (.ECONNABORTED, 53, "Software caused connection abort"),
            (.ECONNRESET, 54, "Connection reset by peer"),
            (.EISCONN, 56, "Socket is already connected"),
            (.ENOTCONN, 57, "Socket is not connected"),
            (.ESHUTDOWN, 58, "Can't send after socket shutdown"),
            (.ETIMEDOUT, 60, "Operation timed out"),
            (.ECONNREFUSED, 61, "Connection refused"),
            (.EHOSTDOWN, 64, "Host is down"),
            (.EHOSTUNREACH, 65, "No route to host"),
        ]

        for (code, darwinRawValue, message) in cases {
            let error = NWError.posix(code)
            let expected = "POSIXErrorCode(rawValue: \(darwinRawValue)): \(message)"

            XCTAssertEqual(error.debugDescription, expected)
            XCTAssertEqual(String(describing: error), expected)
            XCTAssertEqual(String(reflecting: error), expected)
            XCTAssertEqual(
                error.localizedDescription,
                "The operation couldn’t be completed. (Network.NWError error \(darwinRawValue) - \(message))"
            )
            XCTAssertEqual(error, .posix(code))
        }
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
