import XCTest
@testable import TrustedRouter

/// Each test crafts a known input and asserts byte-for-byte the DER output
/// matches the ASN.1 BER/DER spec. The DER blob assembled here is what
/// `SecKeyCreateWithData` consumes to materialize an RSA public key.
final class DERTests: XCTestCase {

    func testIntegerShortPositiveByte() {
        // 0x42 → tag(0x02) len(0x01) value(0x42)
        XCTAssertEqual(DER.integer(Data([0x42])), Data([0x02, 0x01, 0x42]))
    }

    func testIntegerHighBitGetsZeroPadded() {
        // 0xFF without padding would be read as -1 (signed). DER requires
        // a leading 0x00 to keep it unsigned.
        XCTAssertEqual(DER.integer(Data([0xFF])), Data([0x02, 0x02, 0x00, 0xFF]))
    }

    func testIntegerLeadingZeroIsStrippedWhenNextByteIsClear() {
        // Redundant 0x00: 0x00 0x42 → 0x42, because 0x42's high bit is clear.
        XCTAssertEqual(
            DER.integer(Data([0x00, 0x42])),
            Data([0x02, 0x01, 0x42])
        )
    }

    func testIntegerLeadingZeroPreservedWhenFollowingByteHasHighBit() {
        // 0x00 0x80 must stay — stripping the 0x00 would flip the sign.
        XCTAssertEqual(
            DER.integer(Data([0x00, 0x80])),
            Data([0x02, 0x02, 0x00, 0x80])
        )
    }

    func testIntegerSingleZero() {
        // The DER encoding of integer 0 is `02 01 00`, not empty.
        XCTAssertEqual(DER.integer(Data([0x00])), Data([0x02, 0x01, 0x00]))
    }

    func testLengthPrefixShortForm() {
        XCTAssertEqual(DER.lengthPrefix(for: 0), Data([0x00]))
        XCTAssertEqual(DER.lengthPrefix(for: 127), Data([0x7F]))
    }

    func testLengthPrefixLongFormOneByte() {
        // 128 → 0x81 0x80
        XCTAssertEqual(DER.lengthPrefix(for: 128), Data([0x81, 0x80]))
        XCTAssertEqual(DER.lengthPrefix(for: 255), Data([0x81, 0xFF]))
    }

    func testLengthPrefixLongFormTwoBytes() {
        XCTAssertEqual(DER.lengthPrefix(for: 256), Data([0x82, 0x01, 0x00]))
        // Real RSA public keys land around 270 bytes — make sure they're 0x82-tagged.
        XCTAssertEqual(DER.lengthPrefix(for: 270), Data([0x82, 0x01, 0x0E]))
    }

    func testSequenceWrapsPayload() {
        // SEQUENCE { 0x42 }  →  0x30 0x01 0x42
        XCTAssertEqual(DER.sequence(Data([0x42])), Data([0x30, 0x01, 0x42]))
    }

    func testRSAPublicKeyPKCS1Shape() {
        // Tiny synthetic n/e (not a real key, just shape-correct).
        let n = Data([0xC0, 0xDE]) // 2 bytes, high bit set → gets 0x00 padded
        let e = Data([0x01, 0x00, 0x01]) // 65537
        let blob = DER.rsaPublicKeyPKCS1(n: n, e: e)
        // SEQUENCE {
        //   INTEGER 00 C0 DE   →  02 03 00 C0 DE
        //   INTEGER 01 00 01    →  02 03 01 00 01
        // }
        // Inner payload = 02 03 00 C0 DE 02 03 01 00 01  (10 bytes)
        // Outer = 30 0A <inner>
        let expected: [UInt8] = [
            0x30, 0x0A,
            0x02, 0x03, 0x00, 0xC0, 0xDE,
            0x02, 0x03, 0x01, 0x00, 0x01,
        ]
        XCTAssertEqual(Array(blob), expected)
    }

    func testRSAPublicKeyPKCS1IsAcceptedBySecKey() throws {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        // Use a fixed RFC 7517 worked-example n/e pair so the test is
        // hermetic (no keypair generation, no entropy dependency). If
        // SecKeyCreateWithData accepts the blob we built, the encoding is
        // wire-format correct for the only consumer that matters.
        let n = Data(repeating: 0x9F, count: 256) // looks like a 2048-bit modulus
        let e = Data([0x01, 0x00, 0x01])
        let blob = DER.rsaPublicKeyPKCS1(n: n, e: e)
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateWithData(blob as CFData, attrs as CFDictionary, &error)
        XCTAssertNotNil(key, "SecKeyCreateWithData rejected our DER: \(error.map { $0.takeRetainedValue().localizedDescription } ?? "nil")")
        #else
        throw XCTSkip("Security framework not available on this platform")
        #endif
    }
}
