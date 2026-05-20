import XCTest
import Network

final class NetworkEndpointPortParityTests: XCTestCase {
    func testPortIntegerLiteralRawValueAndDescriptionsMatchApple() {
        let literalPort: NWEndpoint.Port = 443
        assertPort(literalPort, rawValue: 443)
        assertPort(NWEndpoint.Port(rawValue: 0), rawValue: 0)
        assertPort(NWEndpoint.Port(rawValue: 65535), rawValue: 65535)
    }

    func testPortStringParserSeededContractMatchesApple() {
        let validInputs: [(String, UInt16)] = [
            ("0", 0),
            ("-0", 0),
            ("-00", 0),
            ("-000", 0),
            ("+0", 0),
            ("00000", 0),
            ("1", 1),
            ("+1", 1),
            ("+000", 0),
            ("00080", 80),
            (" \t+000", 0),
            (" 80", 80),
            ("\t80", 80),
            ("\n80", 80),
            ("\r80", 80),
            ("\u{0B}80", 80),
            ("\u{0C}80", 80),
            ("51820", 51820),
            ("65535", 65535),
        ]

        for (input, expectedRawValue) in validInputs {
            assertPort(NWEndpoint.Port(input), rawValue: expectedRawValue, input)
        }

        let invalidInputs = [
            "",
            "+",
            "-",
            " ",
            "\t",
            "  ",
            "-1",
            "+-1",
            "65536",
            "999999",
            "80 ",
            "80\n",
            "0x50",
            "1.0",
            "08a",
            "\u{00A0}80",
        ]

        for input in invalidInputs {
            XCTAssertNil(NWEndpoint.Port(input), input)
        }
    }

    func testPortStringParserDeterministicFuzzCorpusMatchesAppleContract() {
        for (index, fuzzCase) in Self.seededPortFuzzCases().enumerated() {
            let context = "fuzz case \(index): \(fuzzCase.input.debugDescription)"
            if let expectedRawValue = fuzzCase.expectedRawValue {
                assertPort(NWEndpoint.Port(fuzzCase.input), rawValue: expectedRawValue, context)
            } else {
                XCTAssertNil(NWEndpoint.Port(fuzzCase.input), context)
            }
        }
    }

    func testWellKnownPortConstantsMatchApple() {
        let knownPorts: [(String, NWEndpoint.Port, UInt16)] = [
            ("any", .any, 0),
            ("ssh", .ssh, 22),
            ("smtp", .smtp, 25),
            ("http", .http, 80),
            ("pop", .pop, 110),
            ("imap", .imap, 143),
            ("https", .https, 443),
            ("imaps", .imaps, 993),
            ("socks", .socks, 1080),
        ]

        for (name, port, rawValue) in knownPorts {
            assertPort(port, rawValue: rawValue, name)
        }
    }

    func testPortValueEqualityAndHashingMatchApple() throws {
        let literalHTTPS: NWEndpoint.Port = 443
        let parsedHTTPS = try XCTUnwrap(NWEndpoint.Port("443"))
        let rawHTTPS = try XCTUnwrap(NWEndpoint.Port(rawValue: 443))
        let parsedHTTP = try XCTUnwrap(NWEndpoint.Port("+00080"))
        let parsedAny = try XCTUnwrap(NWEndpoint.Port("-000"))

        let equalPairs: [(NWEndpoint.Port, NWEndpoint.Port, String)] = [
            (literalHTTPS, .https, "literal https and known constant"),
            (parsedHTTPS, .https, "parsed https and known constant"),
            (rawHTTPS, .https, "raw https and known constant"),
            (parsedHTTP, .http, "signed padded http and known constant"),
            (parsedAny, .any, "negative zero parser and any constant"),
        ]

        for (lhs, rhs, context) in equalPairs {
            XCTAssertEqual(lhs, rhs, context)
            XCTAssertEqual(lhs.hashValue, rhs.hashValue, context)
        }

        XCTAssertNotEqual(NWEndpoint.Port.http, NWEndpoint.Port.https)
        XCTAssertNotEqual(try XCTUnwrap(NWEndpoint.Port(rawValue: 0)), try XCTUnwrap(NWEndpoint.Port(rawValue: 1)))
    }

    private func assertPort(
        _ port: NWEndpoint.Port?,
        rawValue: UInt16,
        _ context: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let port else {
            XCTFail("Expected port \(rawValue) for \(context)", file: file, line: line)
            return
        }

        XCTAssertEqual(port.rawValue, rawValue, context, file: file, line: line)
        XCTAssertEqual(String(describing: port), String(rawValue), context, file: file, line: line)
        XCTAssertEqual(port.debugDescription, String(rawValue), context, file: file, line: line)
    }

    private struct PortFuzzCase {
        let input: String
        let expectedRawValue: UInt16?
    }

    private struct PortFuzzGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func nextInt(upperBound: Int) -> Int {
            Int(next() % UInt64(upperBound))
        }
    }

    private static func seededPortFuzzCases() -> [PortFuzzCase] {
        let prefixes = ["", " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", " \t"]
        let signs = ["", "+", "-"]
        let bodies = [
            "0", "00", "000", "0000", "1", "9", "22", "80", "443", "1080",
            "51820", "65534", "65535", "65536", "65537", "99999",
            "18446744073709551616",
        ]
        let suffixes = ["", " ", "\n", "\t", "a", ".0", "+", "-", "\u{00A0}"]

        var cases: [PortFuzzCase] = []
        for prefix in prefixes {
            for sign in signs {
                for body in bodies {
                    for suffix in suffixes {
                        let input = prefix + sign + body + suffix
                        cases.append(PortFuzzCase(
                            input: input,
                            expectedRawValue: expectedPortRawValueForAppleObservedContract(input)
                        ))
                    }
                }
            }
        }

        let alphabet = [
            "", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "+", "-", " ", "\t", "\n", "\r", "a", "x", ".", "\u{00A0}",
        ]
        var generator = PortFuzzGenerator(state: 0x4e57_506f_7274_0001)
        for _ in 0..<240 {
            var input = ""
            for _ in 0..<generator.nextInt(upperBound: 14) {
                input += alphabet[generator.nextInt(upperBound: alphabet.count)]
            }
            cases.append(PortFuzzCase(
                input: input,
                expectedRawValue: expectedPortRawValueForAppleObservedContract(input)
            ))
        }

        return cases
    }

    private static func expectedPortRawValueForAppleObservedContract(_ input: String) -> UInt16? {
        let scalars = Array(input.unicodeScalars)
        var index = scalars.startIndex

        while index < scalars.endIndex, isCWhitespace(scalars[index]) {
            index = scalars.index(after: index)
        }

        var isNegative = false
        if index < scalars.endIndex {
            if scalars[index] == "+" {
                index = scalars.index(after: index)
            } else if scalars[index] == "-" {
                isNegative = true
                index = scalars.index(after: index)
            }
        }

        guard index < scalars.endIndex else { return nil }

        var value: UInt64 = 0
        while index < scalars.endIndex {
            let scalarValue = scalars[index].value
            guard scalarValue >= 48, scalarValue <= 57 else { return nil }
            let digit = UInt64(scalarValue - 48)
            guard value <= (UInt64(UInt16.max) - digit) / 10 else { return nil }
            value = value * 10 + digit
            index = scalars.index(after: index)
        }

        if isNegative, value != 0 {
            return nil
        }

        return UInt16(value)
    }

    private static func isCWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x20 || (0x09...0x0d).contains(scalar.value)
    }
}
