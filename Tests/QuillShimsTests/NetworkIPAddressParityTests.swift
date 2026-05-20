import Foundation
import Network
import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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

    func testIPv4StringInitializerLegacyParserAndSeededFuzzMatchesApple() throws {
        let validCases: [(String, [UInt8])] = [
            ("1", [0, 0, 0, 1]),
            ("010", [0, 0, 0, 8]),
            ("0xffffffff", [255, 255, 255, 255]),
            ("0x100000000", [0, 0, 0, 0]),
            ("4294967296", [0, 0, 0, 0]),
            ("18446744073709551616", [0, 0, 0, 0]),
            ("999999999999999999999999999999", [63, 255, 255, 255]),
            ("1.2", [1, 0, 0, 2]),
            ("1.010", [1, 0, 0, 8]),
            ("1.0x10", [1, 0, 0, 16]),
            ("1.65536", [1, 1, 0, 0]),
            ("1.2.3", [1, 2, 0, 3]),
            ("1.2.0400", [1, 2, 1, 0]),
            ("1.2.0x100", [1, 2, 1, 0]),
            ("0x.0", [0, 0, 0, 0]),
            ("0x.0.0", [0, 0, 0, 0]),
            ("01.02.03.04", [1, 2, 3, 4]),
            ("08.0.0.1", [8, 0, 0, 1]),
            ("010.0.0.1", [10, 0, 0, 1]),
            ("0377.0.0.1", [255, 0, 0, 1]),
            ("0300.0.0.1", [192, 0, 0, 1]),
            ("099.0.0.1", [99, 0, 0, 1]),
            ("0x.0.0.1", [0, 0, 0, 1]),
            ("0x.1.2.3", [0, 1, 2, 3]),
            ("1.0x.2.3", [1, 0, 2, 3]),
            ("1.2.0x.3", [1, 2, 0, 3]),
            ("1.2.3.0377", [1, 2, 3, 255]),
            ("1.2.3.008", [1, 2, 3, 8]),
            ("1.2.3.0xff", [1, 2, 3, 255]),
        ]

        for (input, rawValue) in validCases {
            let address = try XCTUnwrap(IPv4Address(input), input)
            XCTAssertEqual(Array(address.rawValue), rawValue, input)
        }

        let invalidCases = [
            "",
            ".",
            "008",
            "019",
            "0x",
            "1.",
            ".1",
            "1..2",
            "1.2.3.4.5",
            "08.0",
            "08.0.0",
            "1.008",
            "1.2.008",
            "1.2.3.0x",
            "1.2.3.0400",
            "1.2.3.256",
            "1.2.3.0x100",
            "1.2.65536",
            "1.999999999999999999999999999999",
            "1.2.999999999999999999999999999999",
            "1.2.3.999999999999999999999999999999",
            " 1.2.3.4",
            "1.2.3.4 ",
            "+1.2.3.4",
            "-1",
        ]

        for input in invalidCases {
            XCTAssertNil(IPv4Address(input), input)
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

    func testIPAddressEqualityAndHashingMatchApple() throws {
        let loopbackName = try XCTUnwrap(Self.interfaceName(forIndex: 1))

        let v4FromString = try XCTUnwrap(IPv4Address("192.0.2.1"))
        let v4FromData = try XCTUnwrap(IPv4Address(Data([192, 0, 2, 1])))
        let otherV4 = try XCTUnwrap(IPv4Address("192.0.2.2"))
        let scopedV4ByName = try XCTUnwrap(IPv4Address("192.0.2.1%\(loopbackName)"))
        let sameScopedV4ByName = try XCTUnwrap(IPv4Address("192.0.2.1%\(loopbackName)"))

        XCTAssertEqual(v4FromString, v4FromData)
        XCTAssertEqual(v4FromString.hashValue, v4FromData.hashValue)
        XCTAssertNotEqual(v4FromString, otherV4)
        XCTAssertEqual(scopedV4ByName, sameScopedV4ByName)
        XCTAssertEqual(scopedV4ByName.hashValue, sameScopedV4ByName.hashValue)
        XCTAssertNotEqual(scopedV4ByName, v4FromString)

        let v6Raw = [UInt8]([0x20, 0x01, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [1])
        let v6FromString = try XCTUnwrap(IPv6Address("2001:db8::1"))
        let v6FromData = try XCTUnwrap(IPv6Address(Data(v6Raw)))
        let otherV6 = try XCTUnwrap(IPv6Address("2001:db8::2"))
        let scopedV6ByName = try XCTUnwrap(IPv6Address("fe80::1%\(loopbackName)"))
        let scopedV6ByIndex = try XCTUnwrap(IPv6Address("fe80::1%1"))
        let unscopedV6 = try XCTUnwrap(IPv6Address("fe80::1"))

        XCTAssertEqual(v6FromString, v6FromData)
        XCTAssertEqual(v6FromString.hashValue, v6FromData.hashValue)
        XCTAssertNotEqual(v6FromString, otherV6)
        XCTAssertEqual(scopedV6ByName, scopedV6ByIndex)
        XCTAssertEqual(scopedV6ByName.hashValue, scopedV6ByIndex.hashValue)
        XCTAssertNotEqual(scopedV6ByName, unscopedV6)

        let scopeCases: [(IPv6Address.Scope, UInt8)] = [
            (.nodeLocal, 1),
            (.linkLocal, 2),
            (.siteLocal, 5),
            (.organizationLocal, 8),
            (.global, 14),
        ]

        for (scope, rawValue) in scopeCases {
            XCTAssertEqual(scope.rawValue, rawValue)
            let reconstructed = try XCTUnwrap(IPv6Address.Scope(rawValue: rawValue))
            XCTAssertEqual(scope, reconstructed)
            XCTAssertEqual(scope.hashValue, reconstructed.hashValue)
        }

        XCTAssertNotEqual(IPv6Address.Scope.nodeLocal, .linkLocal)
        XCTAssertNil(IPv6Address.Scope(rawValue: 0))
        XCTAssertNil(IPv6Address.Scope(rawValue: 15))
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
