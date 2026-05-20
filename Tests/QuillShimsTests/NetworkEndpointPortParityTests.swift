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
            ("+0", 0),
            ("00000", 0),
            ("1", 1),
            ("+1", 1),
            ("00080", 80),
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
}
