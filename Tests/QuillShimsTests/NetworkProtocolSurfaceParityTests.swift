import Foundation
import Network
import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class NetworkProtocolSurfaceParityTests: XCTestCase {
    func testEndpointPortProtocolSurfaceMatchesApple() throws {
        let port: NWEndpoint.Port = 443

        assertSendable(port)
        assertHashable(port, .https)
        assertRawRepresentable(port, 443)
        assertDebugStringConvertible(port, "443")
        XCTAssertEqual(String(describing: port), "443")
    }

    func testEndpointHostProtocolSurfaceMatchesApple() {
        let host = NWEndpoint.Host("example.com")

        assertSendable(host)
        assertHashable(host, .name("example.com", nil))
        assertDebugStringConvertible(host, "example.com")
        XCTAssertEqual(String(describing: host), "example.com")
    }

    func testEndpointProtocolSurfaceMatchesApple() {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("example.com"), port: .https)

        assertSendable(endpoint)
        assertHashable(endpoint, .hostPort(host: .name("example.com", nil), port: .https))
        assertDebugStringConvertible(endpoint, "example.com:443")
        XCTAssertEqual(String(describing: endpoint), "example.com:443")
    }

    func testIPAddressProtocolSurfaceMatchesApple() throws {
        let ipv4 = try XCTUnwrap(IPv4Address("192.0.2.1"))
        let ipv4Copy = try XCTUnwrap(IPv4Address(Data([192, 0, 2, 1])))

        assertIPAddressProtocol(ipv4)
        assertSendable(ipv4)
        assertHashable(ipv4, ipv4Copy)
        assertDebugStringConvertible(ipv4, "192.0.2.1")
        XCTAssertEqual(String(describing: ipv4), "192.0.2.1")

        let ipv6 = try XCTUnwrap(IPv6Address("2001:db8::1"))
        let ipv6Copy = try XCTUnwrap(IPv6Address(Data([0x20, 0x01, 0x0d, 0xb8] + Array(repeating: UInt8(0), count: 11) + [0x01])))

        assertIPAddressProtocol(ipv6)
        assertSendable(ipv6)
        assertHashable(ipv6, ipv6Copy)
        assertDebugStringConvertible(ipv6, "2001:db8::1")
        XCTAssertEqual(String(describing: ipv6), "2001:db8::1")
    }

    func testIPv6ScopeProtocolSurfaceMatchesApple() throws {
        let linkLocal = IPv6Address.Scope.linkLocal
        let rawLinkLocal = try XCTUnwrap(IPv6Address.Scope(rawValue: linkLocal.rawValue))

        assertHashable(linkLocal, rawLinkLocal)
        assertRawRepresentable(linkLocal, linkLocal.rawValue)
    }

    func testPathAndInterfaceTypeProtocolSurfaceMatchesApple() {
        assertSendable(NWPath.Status.satisfied)
        assertHashable(NWPath.Status.satisfied, .satisfied)
        XCTAssertEqual(String(describing: NWPath.Status.satisfied), "satisfied")

        assertSendable(NWPath.UnsatisfiedReason.notAvailable)
        assertHashable(NWPath.UnsatisfiedReason.notAvailable, .notAvailable)
        XCTAssertEqual(String(describing: NWPath.UnsatisfiedReason.notAvailable), "notAvailable")

        assertSendable(NWInterface.InterfaceType.loopback)
        assertHashable(NWInterface.InterfaceType.loopback, .loopback)
        XCTAssertEqual(String(describing: NWInterface.InterfaceType.loopback), "loopback")
    }

    func testResolvedInterfaceProtocolSurfaceMatchesApple() throws {
        let loopbackName = try XCTUnwrap(Self.interfaceName(forIndex: 1))
        let namedIPv6Interface = try XCTUnwrap(IPv6Address("fe80::1%\(loopbackName)")?.interface)
        let indexedIPv6Interface = try XCTUnwrap(IPv6Address("fe80::1%1")?.interface)

        assertSendable(namedIPv6Interface)
        assertHashable(namedIPv6Interface, indexedIPv6Interface)
        assertDebugStringConvertible(namedIPv6Interface, loopbackName)
        XCTAssertEqual(namedIPv6Interface.name, loopbackName)
        XCTAssertEqual(namedIPv6Interface.type, .loopback)
        XCTAssertEqual(String(describing: namedIPv6Interface), loopbackName)
    }

    private func assertSendable<T: Sendable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) {
        _ = value
    }

    private func assertHashable<T: Hashable>(
        _ lhs: T,
        _ rhs: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs, rhs, file: file, line: line)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue, file: file, line: line)
    }

    private func assertDebugStringConvertible<T: CustomDebugStringConvertible>(
        _ value: T,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(value.debugDescription, expected, file: file, line: line)
    }

    private func assertRawRepresentable<T: RawRepresentable>(
        _ value: T,
        _ expected: T.RawValue,
        file: StaticString = #filePath,
        line: UInt = #line
    ) where T.RawValue: Equatable {
        XCTAssertEqual(value.rawValue, expected, file: file, line: line)
    }

    private func assertIPAddressProtocol<T: IPAddress>(_ value: T, file: StaticString = #filePath, line: UInt = #line) {
        _ = value
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
