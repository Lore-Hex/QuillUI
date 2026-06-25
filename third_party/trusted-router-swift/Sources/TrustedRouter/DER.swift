import Foundation

/// Minimal ASN.1 DER encoders for the bits we need to assemble an RSA
/// public key from a JWK's `n` / `e` parameters into the PKCS#1 format
/// that Security.framework's `SecKeyCreateWithData` accepts:
///
///     RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
///
/// Extracted so the encoding can be unit-tested in isolation. Public-but-
/// underscored to signal "stable contract for the test suite, not a
/// general-purpose ASN.1 library."
public enum DER {

    /// Encode an unsigned big-endian byte sequence as an ASN.1 DER INTEGER.
    /// Canonical form: strip redundant leading zeros where the *next* byte
    /// has the high bit clear; prepend 0x00 if the high bit of the first
    /// byte is set so the value isn't read as negative.
    public static func integer(_ unsigned: Data) -> Data {
        var bytes = unsigned
        while bytes.count > 1, bytes[0] == 0, bytes[1] < 0x80 {
            bytes.removeFirst()
        }
        if let first = bytes.first, first >= 0x80 {
            bytes.insert(0, at: 0)
        }
        return Data([0x02]) + lengthPrefix(for: bytes.count) + bytes
    }

    /// Wrap an arbitrary payload in an ASN.1 DER SEQUENCE.
    public static func sequence(_ payload: Data) -> Data {
        Data([0x30]) + lengthPrefix(for: payload.count) + payload
    }

    /// DER length octet(s): short form (single byte) for lengths < 128;
    /// long form (`0x80 | numBytes` followed by big-endian length) otherwise.
    public static func lengthPrefix(for count: Int) -> Data {
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        // Long-form: strip leading zeros to produce the minimal big-endian
        // encoding of `count`.
        var length = withUnsafeBytes(of: UInt32(count).bigEndian) { Data($0) }
        while length.first == 0 { length.removeFirst() }
        return Data([0x80 | UInt8(length.count)]) + length
    }

    /// Assemble a PKCS#1 `RSAPublicKey` DER blob from the JWK n/e pair.
    public static func rsaPublicKeyPKCS1(n: Data, e: Data) -> Data {
        sequence(integer(n) + integer(e))
    }
}
