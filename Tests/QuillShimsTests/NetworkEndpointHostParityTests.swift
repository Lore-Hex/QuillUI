import XCTest
import Network
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class NetworkEndpointHostParityTests: XCTestCase {
    func testHostStringInitializerClassificationMatchesApple() {
        let cases: [(String, ExpectedHost)] = [
            ("example.com", .name("example.com")),
            ("", .name(".")),
            ("localhost", .name("localhost")),
            ("192.168.1.10", .ipv4([192, 168, 1, 10], "192.168.1.10", nil)),
            ("01.02.03.04", .ipv4([1, 2, 3, 4], "1.2.3.4", nil)),
            ("1", .ipv4([0, 0, 0, 1], "0.0.0.1", nil)),
            ("1.2", .ipv4([1, 0, 0, 2], "1.0.0.2", nil)),
            ("1.2.3", .ipv4([1, 2, 0, 3], "1.2.0.3", nil)),
            ("0x1.2.3.4", .ipv4([1, 2, 3, 4], "1.2.3.4", nil)),
            ("0377.0377.0377.0377", .ipv4([255, 255, 255, 255], "255.255.255.255", nil)),
            ("4294967296", .ipv4([0, 0, 0, 0], "0.0.0.0", nil)),
            ("256.0.0.1", .name("256.0.0.1")),
            ("192.168.1.10 ", .name("192.168.1.10 ")),
            (" 192.168.1.10", .name(" 192.168.1.10")),
            ("::1", .ipv6(Array(repeating: 0, count: 15) + [1], "::1", nil)),
            ("::", .ipv6(Array(repeating: 0, count: 16), "::", nil)),
            (
                "2001:db8::1",
                .ipv6([0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [1], "2001:db8::1", nil)
            ),
            ("::ffff:192.0.2.1", .ipv4([192, 0, 2, 1], "192.0.2.1", nil)),
            ("::192.0.2.1", .ipv6(Array(repeating: 0, count: 12) + [192, 0, 2, 1], "::192.0.2.1", nil)),
            ("::1 ", .name("::1 ")),
            (" ::1", .name(" ::1")),
        ]

        for (input, expected) in cases {
            assertHost(NWEndpoint.Host(input), expected, input)
        }
    }

    func testScopedInterfaceHostLiteralsMatchApple() throws {
        let loopbackName = try XCTUnwrap(Self.interfaceName(forIndex: 1))
        let scopedIPv6Bytes = [UInt8]([0xfe, 0x80] + Array(repeating: 0, count: 13) + [1])
        let loopbackIPv6Bytes = [UInt8](Array(repeating: UInt8(0), count: 15) + [1])
        let scopedMappedBytes = [UInt8]([192, 0, 2, 1])
        let cases: [(String, ExpectedHost)] = [
            ("fe80::1%\(loopbackName)", .ipv6(scopedIPv6Bytes, "fe80::1%\(loopbackName)", loopbackName)),
            ("fe80::1%1", .ipv6(scopedIPv6Bytes, "fe80::1%\(loopbackName)", loopbackName)),
            ("fe80::1%", .ipv6(scopedIPv6Bytes, "fe80::1", nil)),
            ("fe80::1%999999", .ipv6(scopedIPv6Bytes, "fe80::1", nil)),
            ("fe80::1%quillui-no-such-interface", .ipv6(scopedIPv6Bytes, "fe80::1", nil)),
            ("fe80::1%%", .name("fe80::1%%")),
            ("::1%", .ipv6(loopbackIPv6Bytes, "::1", nil)),
            ("::1%999999", .ipv6(loopbackIPv6Bytes, "::1", nil)),
            ("192.0.2.1%\(loopbackName)", .ipv4(scopedMappedBytes, "192.0.2.1%\(loopbackName)", loopbackName)),
            ("192.0.2.1%", .name("192.0.2.1%")),
            ("192.0.2.1%999999", .name("192.0.2.1%999999")),
            ("::ffff:192.0.2.1%\(loopbackName)", .ipv4(scopedMappedBytes, "192.0.2.1%\(loopbackName)", loopbackName)),
            ("::ffff:192.0.2.1%", .ipv4(scopedMappedBytes, "192.0.2.1", nil)),
            ("::ffff:192.0.2.1%999999", .ipv4(scopedMappedBytes, "192.0.2.1", nil)),
            ("example.com%\(loopbackName)", .name("example.com", loopbackName)),
            ("example.com%", .name("example.com%")),
            ("example.com%999999", .name("example.com%999999")),
        ]

        for (input, expected) in cases {
            assertHost(NWEndpoint.Host(input), expected, input)
        }

        let directIPv6 = try XCTUnwrap(IPv6Address("fe80::1%\(loopbackName)"))
        XCTAssertEqual(Array(directIPv6.rawValue), scopedIPv6Bytes)
        XCTAssertEqual(String(describing: directIPv6), "fe80::1%\(loopbackName)")
        XCTAssertEqual(directIPv6.interface.map { String(describing: $0) }, loopbackName)

        let directIPv4 = try XCTUnwrap(IPv4Address("192.0.2.1%\(loopbackName)"))
        XCTAssertEqual(Array(directIPv4.rawValue), scopedMappedBytes)
        XCTAssertEqual(String(describing: directIPv4), "192.0.2.1%\(loopbackName)")
        XCTAssertEqual(directIPv4.interface.map { String(describing: $0) }, loopbackName)
    }

    func testScopedHostValueEqualityAndHashingMatchApple() throws {
        let loopbackName = try XCTUnwrap(Self.interfaceName(forIndex: 1))
        let directIPv4 = try XCTUnwrap(IPv4Address("192.0.2.1%\(loopbackName)"))
        let directIPv6 = try XCTUnwrap(IPv6Address("fe80::1%\(loopbackName)"))
        let directInterface = try XCTUnwrap(directIPv6.interface)

        let scopedIPv6ByName = NWEndpoint.Host("fe80::1%\(loopbackName)")
        let scopedIPv6ByIndex = NWEndpoint.Host("fe80::1%1")
        let scopedIPv4ByName = NWEndpoint.Host("192.0.2.1%\(loopbackName)")
        let scopedIPv4FromMapped = NWEndpoint.Host("::ffff:192.0.2.1%\(loopbackName)")
        let scopedName = NWEndpoint.Host("example.com%\(loopbackName)")

        let equalHosts: [(NWEndpoint.Host, NWEndpoint.Host, String)] = [
            (scopedIPv6ByName, scopedIPv6ByIndex, "scoped IPv6 name and numeric scope"),
            (scopedIPv6ByName, .ipv6(directIPv6), "scoped IPv6 direct value"),
            (scopedIPv4ByName, .ipv4(directIPv4), "scoped IPv4 direct value"),
            (scopedIPv4FromMapped, .ipv4(directIPv4), "scoped IPv4-mapped IPv6 literal"),
            (scopedName, .name("example.com", directInterface), "scoped DNS direct value"),
        ]

        for (lhs, rhs, context) in equalHosts {
            XCTAssertEqual(lhs, rhs, context)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue, context)
        }

        XCTAssertNotEqual(scopedIPv6ByName, NWEndpoint.Host("fe80::1"))
        XCTAssertNotEqual(scopedIPv4ByName, NWEndpoint.Host("192.0.2.1"))
        XCTAssertNotEqual(scopedName, NWEndpoint.Host("example.com"))
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

    func testHostValueEqualityAndHashingMatchApple() throws {
        let ipv4 = try XCTUnwrap(IPv4Address("192.0.2.1"))
        let ipv6 = try XCTUnwrap(IPv6Address("2001:db8::1"))
        let ipv4Mapped = try XCTUnwrap(IPv4Address("192.0.2.1"))
        let ipv4Compatible = try XCTUnwrap(IPv6Address("::192.0.2.1"))

        let equalHosts: [(NWEndpoint.Host, NWEndpoint.Host, String)] = [
            (NWEndpoint.Host("example.com"), .name("example.com", nil), "DNS name"),
            (NWEndpoint.Host(""), .name(".", nil), "empty-string DNS root normalization"),
            (NWEndpoint.Host("192.0.2.1"), .ipv4(ipv4), "IPv4 literal"),
            (NWEndpoint.Host("2001:db8::1"), .ipv6(ipv6), "IPv6 literal"),
            (NWEndpoint.Host("::ffff:192.0.2.1"), .ipv4(ipv4Mapped), "IPv4-mapped IPv6 literal"),
            (NWEndpoint.Host("::192.0.2.1"), .ipv6(ipv4Compatible), "IPv4-compatible IPv6 literal"),
        ]

        for (lhs, rhs, context) in equalHosts {
            XCTAssertEqual(lhs, rhs, context)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue, context)
        }

        XCTAssertNotEqual(NWEndpoint.Host("example.com"), NWEndpoint.Host("example.org"))
        XCTAssertNotEqual(NWEndpoint.Host("example.com"), NWEndpoint.Host("Example.com"))
        XCTAssertNotEqual(NWEndpoint.Host("192.0.2.1"), NWEndpoint.Host("192.0.2.2"))
        XCTAssertNotEqual(NWEndpoint.Host("::1"), NWEndpoint.Host("::"))
        XCTAssertNotEqual(NWEndpoint.Host("::ffff:192.0.2.1"), NWEndpoint.Host("::192.0.2.1"))
    }

    func testEndpointValueEqualityAndHashingMatchApple() throws {
        let port: NWEndpoint.Port = 443
        let ipv4 = try XCTUnwrap(IPv4Address("192.0.2.1"))
        let ipv6 = try XCTUnwrap(IPv6Address("2001:db8::1"))
        let loopbackName = try XCTUnwrap(Self.interfaceName(forIndex: 1))
        let scopedIPv6 = try XCTUnwrap(IPv6Address("fe80::1%\(loopbackName)"))

        let equalEndpoints: [(NWEndpoint, NWEndpoint, String)] = [
            (
                .hostPort(host: NWEndpoint.Host("example.com"), port: port),
                .hostPort(host: .name("example.com", nil), port: .https),
                "host-port DNS name"
            ),
            (
                .hostPort(host: NWEndpoint.Host("192.0.2.1"), port: port),
                .hostPort(host: .ipv4(ipv4), port: .https),
                "host-port IPv4 literal"
            ),
            (
                .hostPort(host: NWEndpoint.Host("2001:db8::1"), port: port),
                .hostPort(host: .ipv6(ipv6), port: .https),
                "host-port IPv6 literal"
            ),
            (
                .hostPort(host: NWEndpoint.Host("::ffff:192.0.2.1"), port: port),
                .hostPort(host: .ipv4(ipv4), port: .https),
                "host-port IPv4-mapped IPv6 literal"
            ),
            (
                .hostPort(host: NWEndpoint.Host("fe80::1%\(loopbackName)"), port: port),
                .hostPort(host: .ipv6(scopedIPv6), port: .https),
                "host-port scoped IPv6 literal"
            ),
            (
                .service(name: "svc", type: "_http._tcp", domain: "local.", interface: nil),
                .service(name: "svc", type: "_http._tcp", domain: "local.", interface: nil),
                "service exact value"
            ),
            (
                .unix(path: "/tmp/socket"),
                .unix(path: "/tmp/socket"),
                "Unix path exact value"
            ),
        ]

        for (lhs, rhs, context) in equalEndpoints {
            XCTAssertEqual(lhs, rhs, context)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue, context)
        }

        XCTAssertNotEqual(
            NWEndpoint.hostPort(host: NWEndpoint.Host("example.com"), port: port),
            NWEndpoint.hostPort(host: NWEndpoint.Host("example.org"), port: port)
        )
        XCTAssertNotEqual(
            NWEndpoint.hostPort(host: NWEndpoint.Host("example.com"), port: port),
            NWEndpoint.hostPort(host: NWEndpoint.Host("example.com"), port: .http)
        )
        XCTAssertNotEqual(
            NWEndpoint.hostPort(host: NWEndpoint.Host("fe80::1%\(loopbackName)"), port: port),
            NWEndpoint.hostPort(host: NWEndpoint.Host("fe80::1"), port: port)
        )
        XCTAssertNotEqual(
            NWEndpoint.service(name: "svc", type: "_http._tcp", domain: "local.", interface: nil),
            NWEndpoint.service(name: "other", type: "_http._tcp", domain: "local.", interface: nil)
        )
        XCTAssertNotEqual(
            NWEndpoint.service(name: "svc", type: "_http._tcp", domain: "local.", interface: nil),
            NWEndpoint.service(name: "svc", type: "_mesh._udp", domain: "local.", interface: nil)
        )
        XCTAssertNotEqual(
            NWEndpoint.unix(path: "/tmp/socket"),
            NWEndpoint.unix(path: "/tmp/other")
        )
        XCTAssertNotEqual(
            NWEndpoint.hostPort(host: NWEndpoint.Host("example.com"), port: port),
            NWEndpoint.unix(path: "example.com:443")
        )
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
            (.service(name: "", type: "_http._tcp", domain: "local", interface: nil), "_http._tcp.local."),
            (.service(name: "", type: "_http._tcp", domain: "", interface: nil), "._http._tcp"),
            (.service(name: "", type: "http", domain: "local", interface: nil), ".httplocal"),
            (.service(name: "svc.", type: "_http._tcp", domain: "local", interface: nil), "svc\\.._http._tcp.local."),
            (.service(name: "a.b", type: "_http._tcp", domain: "local", interface: nil), "a\\.b._http._tcp.local."),
            (.service(name: "a..b.", type: "_http._tcp", domain: "local", interface: nil), "a\\.\\.b\\.._http._tcp.local."),
            (.service(name: ".svc", type: "_http._tcp", domain: "local", interface: nil), "\\.svc._http._tcp.local."),
            (.service(name: "a b", type: "_http._tcp", domain: "local", interface: nil), "a\\032b._http._tcp.local."),
            (.service(name: "a\\b", type: "_http._tcp", domain: "local", interface: nil), "a\\\\b._http._tcp.local."),
            (.service(name: "svc", type: "_mesh._udp", domain: "example.com.", interface: nil), "svc._mesh._udp.example.com."),
            (.service(name: "svc", type: "_mesh._udp.example.com", domain: "local", interface: nil), "svc._mesh._udp.example.comlocal"),
            (.service(name: "svc", type: "_mesh._sctp", domain: "local", interface: nil), "svc._mesh._sctplocal"),
            (.service(name: "svc", type: "_http._tcp", domain: ".local", interface: nil), "svc._http._tcp..local."),
            (.service(name: "svc.", type: "._http._tcp.", domain: ".local.", interface: nil), "svc\\..._http._tcp..local."),
            (.service(name: ".", type: ".", domain: ".", interface: nil), "...."),
        ]

        for (endpoint, expectedDescription) in cases {
            XCTAssertEqual(String(describing: endpoint), expectedDescription)
            XCTAssertEqual(endpoint.debugDescription, expectedDescription)
        }
    }

    private enum ExpectedHost {
        case name(String, String? = nil)
        case ipv4([UInt8], String, String?)
        case ipv6([UInt8], String, String?)
    }

    private func assertHost(
        _ host: NWEndpoint.Host,
        _ expected: ExpectedHost,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (host, expected) {
        case let (.name(actualName, actualInterface), .name(expectedName, expectedInterface)):
            XCTAssertEqual(actualName, expectedName, context, file: file, line: line)
            XCTAssertEqual(actualInterface.map { String(describing: $0) }, expectedInterface, context, file: file, line: line)
            let expectedDescription = expectedInterface.map { "\(expectedName)%\($0)" } ?? expectedName
            XCTAssertEqual(String(describing: host), expectedDescription, context, file: file, line: line)
            XCTAssertEqual(host.debugDescription, expectedDescription, context, file: file, line: line)
        case let (.ipv4(actualAddress), .ipv4(expectedRawValue, expectedDescription, expectedInterface)):
            XCTAssertEqual(Array(actualAddress.rawValue), expectedRawValue, context, file: file, line: line)
            XCTAssertEqual(actualAddress.interface.map { String(describing: $0) }, expectedInterface, context, file: file, line: line)
            XCTAssertEqual(String(describing: host), expectedDescription, context, file: file, line: line)
            XCTAssertEqual(host.debugDescription, expectedDescription, context, file: file, line: line)
        case let (.ipv6(actualAddress), .ipv6(expectedRawValue, expectedDescription, expectedInterface)):
            XCTAssertEqual(Array(actualAddress.rawValue), expectedRawValue, context, file: file, line: line)
            XCTAssertEqual(actualAddress.interface.map { String(describing: $0) }, expectedInterface, context, file: file, line: line)
            XCTAssertEqual(String(describing: host), expectedDescription, context, file: file, line: line)
            XCTAssertEqual(host.debugDescription, expectedDescription, context, file: file, line: line)
        default:
            XCTFail("Unexpected host classification for \(context): \(host)", file: file, line: line)
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
