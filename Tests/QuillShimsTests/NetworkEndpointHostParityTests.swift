import XCTest
import Network

final class NetworkEndpointHostParityTests: XCTestCase {
    func testHostStringInitializerClassificationMatchesApple() {
        let cases: [(String, ExpectedHost)] = [
            ("example.com", .name("example.com")),
            ("", .name(".")),
            ("localhost", .name("localhost")),
            ("192.168.1.10", .ipv4([192, 168, 1, 10], "192.168.1.10")),
            ("01.02.03.04", .ipv4([1, 2, 3, 4], "1.2.3.4")),
            ("1", .ipv4([0, 0, 0, 1], "0.0.0.1")),
            ("1.2", .ipv4([1, 0, 0, 2], "1.0.0.2")),
            ("1.2.3", .ipv4([1, 2, 0, 3], "1.2.0.3")),
            ("0x1.2.3.4", .ipv4([1, 2, 3, 4], "1.2.3.4")),
            ("0377.0377.0377.0377", .ipv4([255, 255, 255, 255], "255.255.255.255")),
            ("4294967296", .ipv4([0, 0, 0, 0], "0.0.0.0")),
            ("256.0.0.1", .name("256.0.0.1")),
            ("192.168.1.10 ", .name("192.168.1.10 ")),
            (" 192.168.1.10", .name(" 192.168.1.10")),
            ("::1", .ipv6(Array(repeating: 0, count: 15) + [1], "::1")),
            ("::", .ipv6(Array(repeating: 0, count: 16), "::")),
            (
                "2001:db8::1",
                .ipv6([0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [1], "2001:db8::1")
            ),
            ("::ffff:192.0.2.1", .ipv4([192, 0, 2, 1], "192.0.2.1")),
            ("::192.0.2.1", .ipv6(Array(repeating: 0, count: 12) + [192, 0, 2, 1], "::192.0.2.1")),
            ("::1 ", .name("::1 ")),
            (" ::1", .name(" ::1")),
        ]

        for (input, expected) in cases {
            assertHost(NWEndpoint.Host(input), expected, input)
        }
    }

    func testDirectHostCaseDescriptionsMatchApple() {
        let directHosts: [(NWEndpoint.Host, String)] = [
            (.name("example.com", nil), "example.com"),
            (.name("", nil), ""),
            (.ipv4(IPv4Address("192.168.1.10")!), "192.168.1.10"),
            (.ipv6(IPv6Address("::1")!), "::1"),
        ]

        for (host, expectedDescription) in directHosts {
            XCTAssertEqual(String(describing: host), expectedDescription)
            XCTAssertEqual(host.debugDescription, expectedDescription)
        }
    }

    func testEndpointValueDescriptionsMatchApple() {
        let literalPort: NWEndpoint.Port = 443
        let cases: [(NWEndpoint, String)] = [
            (.hostPort(host: NWEndpoint.Host("example.com"), port: literalPort), "example.com:443"),
            (.hostPort(host: NWEndpoint.Host("192.168.1.10"), port: literalPort), "192.168.1.10:443"),
            (.hostPort(host: NWEndpoint.Host("::1"), port: literalPort), "::1.443"),
            (.hostPort(host: NWEndpoint.Host("::ffff:192.0.2.1"), port: literalPort), "192.0.2.1:443"),
            (.unix(path: "/tmp/socket"), "/tmp/socket"),
            (.unix(path: ""), ""),
            (.service(name: "svc", type: "_http._tcp", domain: "local.", interface: nil), "svc._http._tcp.local."),
            (.service(name: "svc", type: "_http._tcp.", domain: "local.", interface: nil), "svc._http._tcp.local."),
            (.service(name: "svc", type: "http", domain: "local", interface: nil), "svc.httplocal"),
        ]

        for (endpoint, expectedDescription) in cases {
            XCTAssertEqual(String(describing: endpoint), expectedDescription)
            XCTAssertEqual(endpoint.debugDescription, expectedDescription)
        }
    }

    private enum ExpectedHost {
        case name(String)
        case ipv4([UInt8], String)
        case ipv6([UInt8], String)
    }

    private func assertHost(
        _ host: NWEndpoint.Host,
        _ expected: ExpectedHost,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (host, expected) {
        case let (.name(actualName, actualInterface), .name(expectedName)):
            XCTAssertEqual(actualName, expectedName, context, file: file, line: line)
            XCTAssertNil(actualInterface, context, file: file, line: line)
            XCTAssertEqual(String(describing: host), expectedName, context, file: file, line: line)
            XCTAssertEqual(host.debugDescription, expectedName, context, file: file, line: line)
        case let (.ipv4(actualAddress), .ipv4(expectedRawValue, expectedDescription)):
            XCTAssertEqual(Array(actualAddress.rawValue), expectedRawValue, context, file: file, line: line)
            XCTAssertNil(actualAddress.interface, context, file: file, line: line)
            XCTAssertEqual(String(describing: host), expectedDescription, context, file: file, line: line)
            XCTAssertEqual(host.debugDescription, expectedDescription, context, file: file, line: line)
        case let (.ipv6(actualAddress), .ipv6(expectedRawValue, expectedDescription)):
            XCTAssertEqual(Array(actualAddress.rawValue), expectedRawValue, context, file: file, line: line)
            XCTAssertNil(actualAddress.interface, context, file: file, line: line)
            XCTAssertEqual(String(describing: host), expectedDescription, context, file: file, line: line)
            XCTAssertEqual(host.debugDescription, expectedDescription, context, file: file, line: line)
        default:
            XCTFail("Unexpected host classification for \(context): \(host)", file: file, line: line)
        }
    }
}
