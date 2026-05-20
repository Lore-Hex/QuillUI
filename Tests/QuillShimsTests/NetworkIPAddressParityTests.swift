import Foundation
import Network
import XCTest

final class NetworkIPAddressParityTests: XCTestCase {
    func testIPv4ClassifierEdgeMatrixMatchesApple() throws {
        let cases: [IPv4ClassifierCase] = [
            .init("0.0.0.0", [0, 0, 0, 0], false, false, false),
            .init("127.0.0.0", [127, 0, 0, 0], false, false, false),
            .init("127.0.0.1", [127, 0, 0, 1], true, false, false),
            .init("127.0.0.2", [127, 0, 0, 2], false, false, false),
            .init("127.255.255.255", [127, 255, 255, 255], false, false, false),
            .init("128.0.0.1", [128, 0, 0, 1], false, false, false),
            .init("169.254.0.0", [169, 254, 0, 0], false, true, false),
            .init("169.254.1.2", [169, 254, 1, 2], false, true, false),
            .init("169.254.255.255", [169, 254, 255, 255], false, true, false),
            .init("224.0.0.0", [224, 0, 0, 0], false, false, true),
            .init("239.255.255.255", [239, 255, 255, 255], false, false, true),
            .init("240.0.0.0", [240, 0, 0, 0], false, false, false),
            .init("255.255.255.255", [255, 255, 255, 255], false, false, false),
        ]

        for entry in cases {
            let address = try XCTUnwrap(IPv4Address(entry.input), entry.input)

            XCTAssertEqual(Array(address.rawValue), entry.rawValue, entry.input)
            XCTAssertEqual(String(describing: address), entry.input, entry.input)
            XCTAssertEqual(address.debugDescription, entry.input, entry.input)
            XCTAssertEqual(address.isLoopback, entry.isLoopback, entry.input)
            XCTAssertEqual(address.isLinkLocal, entry.isLinkLocal, entry.input)
            XCTAssertEqual(address.isMulticast, entry.isMulticast, entry.input)
        }
    }

    func testIPv6ClassifierEdgeMatrixMatchesApple() throws {
        let cases: [IPv6ClassifierCase] = [
            .init("::", true, false, false, false, nil, false, false, false, nil, false),
            .init("::1", false, true, false, false, nil, false, false, false, nil, false),
            .init("::2", false, false, true, false, "0.0.0.2", false, false, false, nil, false),
            .init("::192.0.2.1", false, false, true, false, "192.0.2.1", false, false, false, nil, false),
            .init("::ffff:192.0.2.1", false, false, false, true, "192.0.2.1", false, false, false, nil, false),
            .init("2002::", false, false, false, false, nil, true, false, false, nil, false),
            .init("2001::", false, false, false, false, nil, false, false, false, nil, false),
            .init("fe7f::", false, false, false, false, nil, false, false, false, nil, false),
            .init("fe80::", false, false, false, false, nil, false, true, false, nil, false),
            .init("febf::", false, false, false, false, nil, false, true, false, nil, false),
            .init("fec0::", false, false, false, false, nil, false, false, false, nil, false),
            .init("fc00::", false, false, false, false, nil, false, false, false, nil, true),
            .init("fdff::", false, false, false, false, nil, false, false, false, nil, true),
            .init("ff00::", false, false, false, false, nil, false, false, true, nil, false),
            .init("ff01::", false, false, false, false, nil, false, false, true, .nodeLocal, false),
            .init("ff02::", false, false, false, false, nil, false, false, true, .linkLocal, false),
            .init("ff05::", false, false, false, false, nil, false, false, true, .siteLocal, false),
            .init("ff08::", false, false, false, false, nil, false, false, true, .organizationLocal, false),
            .init("ff0e::", false, false, false, false, nil, false, false, true, .global, false),
            .init("ff0f::", false, false, false, false, nil, false, false, true, nil, false),
        ]

        for entry in cases {
            let address = try XCTUnwrap(IPv6Address(entry.input), entry.input)

            XCTAssertEqual(String(describing: address), entry.input, entry.input)
            XCTAssertEqual(address.debugDescription, entry.input, entry.input)
            XCTAssertEqual(address.isAny, entry.isAny, entry.input)
            XCTAssertEqual(address.isLoopback, entry.isLoopback, entry.input)
            XCTAssertEqual(address.isIPv4Compatabile, entry.isIPv4Compatabile, entry.input)
            XCTAssertEqual(address.isIPv4Mapped, entry.isIPv4Mapped, entry.input)
            XCTAssertEqual(address.asIPv4.map { String(describing: $0) }, entry.asIPv4Description, entry.input)
            XCTAssertEqual(address.is6to4, entry.is6to4, entry.input)
            XCTAssertEqual(address.isLinkLocal, entry.isLinkLocal, entry.input)
            XCTAssertEqual(address.isMulticast, entry.isMulticast, entry.input)
            XCTAssertEqual(address.multicastScope, entry.multicastScope, entry.input)
            XCTAssertEqual(address.isUniqueLocal, entry.isUniqueLocal, entry.input)
        }
    }

    func testIPAddressDataInitializersMatchApple() throws {
        XCTAssertNil(IPv4Address(Data([1, 2, 3])))

        let v4 = try XCTUnwrap(IPv4Address(Data([1, 2, 3, 4])))
        XCTAssertEqual(Array(v4.rawValue), [1, 2, 3, 4])
        XCTAssertEqual(String(describing: v4), "1.2.3.4")

        XCTAssertNil(IPv4Address(Data([1, 2, 3, 4, 5])))

        let loopbackRaw = Array(repeating: UInt8(0), count: 15) + [1]
        XCTAssertNil(IPv6Address(Data(Array(repeating: UInt8(0), count: 15))))

        let v6 = try XCTUnwrap(IPv6Address(Data(loopbackRaw)))
        XCTAssertEqual(Array(v6.rawValue), loopbackRaw)
        XCTAssertEqual(String(describing: v6), "::1")

        XCTAssertNil(IPv6Address(Data(Array(repeating: UInt8(0), count: 17))))
    }

    private struct IPv4ClassifierCase {
        let input: String
        let rawValue: [UInt8]
        let isLoopback: Bool
        let isLinkLocal: Bool
        let isMulticast: Bool

        init(
            _ input: String,
            _ rawValue: [UInt8],
            _ isLoopback: Bool,
            _ isLinkLocal: Bool,
            _ isMulticast: Bool
        ) {
            self.input = input
            self.rawValue = rawValue
            self.isLoopback = isLoopback
            self.isLinkLocal = isLinkLocal
            self.isMulticast = isMulticast
        }
    }

    private struct IPv6ClassifierCase {
        let input: String
        let isAny: Bool
        let isLoopback: Bool
        let isIPv4Compatabile: Bool
        let isIPv4Mapped: Bool
        let asIPv4Description: String?
        let is6to4: Bool
        let isLinkLocal: Bool
        let isMulticast: Bool
        let multicastScope: IPv6Address.Scope?
        let isUniqueLocal: Bool

        init(
            _ input: String,
            _ isAny: Bool,
            _ isLoopback: Bool,
            _ isIPv4Compatabile: Bool,
            _ isIPv4Mapped: Bool,
            _ asIPv4Description: String?,
            _ is6to4: Bool,
            _ isLinkLocal: Bool,
            _ isMulticast: Bool,
            _ multicastScope: IPv6Address.Scope?,
            _ isUniqueLocal: Bool
        ) {
            self.input = input
            self.isAny = isAny
            self.isLoopback = isLoopback
            self.isIPv4Compatabile = isIPv4Compatabile
            self.isIPv4Mapped = isIPv4Mapped
            self.asIPv4Description = asIPv4Description
            self.is6to4 = is6to4
            self.isLinkLocal = isLinkLocal
            self.isMulticast = isMulticast
            self.multicastScope = multicastScope
            self.isUniqueLocal = isUniqueLocal
        }
    }
}
