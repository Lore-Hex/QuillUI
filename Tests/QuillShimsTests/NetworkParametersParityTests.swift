import XCTest
import Network

final class NetworkParametersParityTests: XCTestCase {
    func testProtocolOptionConstructorsMatchAppleTextSurface() {
        assertOption(NWProtocolTCP.Options(), expectedText: "Network.NWProtocolTCP.Options")
        assertOption(NWProtocolUDP.Options(), expectedText: "Network.NWProtocolUDP.Options")
        assertOption(NWProtocolTLS.Options(), expectedText: "Network.NWProtocolTLS.Options")
    }

    func testProtocolOptionConstructorsReturnDistinctReferenceInstances() {
        XCTAssertTrue(NWProtocolTCP.Options() !== NWProtocolTCP.Options())
        XCTAssertTrue(NWProtocolUDP.Options() !== NWProtocolUDP.Options())
        XCTAssertTrue(NWProtocolTLS.Options() !== NWProtocolTLS.Options())
    }

    func testParameterFactoriesMatchAppleTextSurfaceAndInstanceFreshness() {
        assertParameters(NWParameters.tcp, expectedText: "tcp, attribution: developer")
        assertParameters(NWParameters.udp, expectedText: "udp, attribution: developer")
        assertParameters(NWParameters.tls, expectedText: "tcp, tls, attribution: developer")
        assertParameters(NWParameters.dtls, expectedText: "udp, tls, attribution: developer")

        XCTAssertTrue(NWParameters.tcp !== NWParameters.tcp)
        XCTAssertTrue(NWParameters.udp !== NWParameters.udp)
        XCTAssertTrue(NWParameters.tls !== NWParameters.tls)
        XCTAssertTrue(NWParameters.dtls !== NWParameters.dtls)
    }

    func testParameterInitializersMatchAppleTextSurface() {
        assertParameters(
            NWParameters(tls: nil, tcp: NWProtocolTCP.Options()),
            expectedText: "tcp, attribution: developer"
        )
        assertParameters(
            NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options()),
            expectedText: "tcp, tls, attribution: developer"
        )
        assertParameters(
            NWParameters(dtls: nil, udp: NWProtocolUDP.Options()),
            expectedText: "udp, attribution: developer"
        )
        assertParameters(
            NWParameters(dtls: NWProtocolTLS.Options(), udp: NWProtocolUDP.Options()),
            expectedText: "udp, tls, attribution: developer"
        )
    }

    func testParameterAndProtocolOptionSurfaceIsSendableLikeApple() {
        assertSendable(NWProtocolTCP.Options())
        assertSendable(NWProtocolUDP.Options())
        assertSendable(NWProtocolTLS.Options())
        assertSendable(NWParameters.tcp)
        assertSendable(NWParameters.udp)
        assertSendable(NWParameters.tls)
        assertSendable(NWParameters.dtls)
    }

    private func assertOption(
        _ option: Any,
        expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(describing: option), expectedText, file: file, line: line)
        XCTAssertEqual(String(reflecting: option), expectedText, file: file, line: line)
    }

    private func assertParameters(
        _ parameters: NWParameters,
        expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(describing: parameters), expectedText, file: file, line: line)
        XCTAssertEqual(String(reflecting: parameters), expectedText, file: file, line: line)
        XCTAssertEqual(parameters.debugDescription, expectedText, file: file, line: line)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
