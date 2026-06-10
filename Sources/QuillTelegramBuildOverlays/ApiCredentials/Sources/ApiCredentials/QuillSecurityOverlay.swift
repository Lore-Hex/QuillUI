#if os(Linux)
import Foundation

typealias CFURL = URL
typealias CFDictionary = [String: Any]
typealias CC_LONG = UInt32

extension FileManager {
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        let sanitized = groupIdentifier
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "." || character == "-" ? character : "_"
            }
        return temporaryDirectory
            .appendingPathComponent("QuillAppGroups", isDirectory: true)
            .appendingPathComponent(String(sanitized), isDirectory: true)
    }
}

final class SecStaticCode {}
final class SecTrust {}
final class SecCertificate {}

struct SecCSFlags: OptionSet {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

let kSecCSSigningInformation: UInt32 = 1 << 1
let kSecCodeInfoTrust = "trust"
let kSecCodeInfoIdentifier = "identifier"
let CC_SHA1_DIGEST_LENGTH: Int32 = 20

@discardableResult
func SecStaticCodeCreateWithPath(
    _ path: CFURL,
    _ flags: SecCSFlags,
    _ staticCode: inout SecStaticCode?
) -> Int32 {
    staticCode = nil
    _ = (path, flags)
    return -1
}

@discardableResult
func SecCodeCopySigningInformation(
    _ code: SecStaticCode,
    _ flags: SecCSFlags,
    _ information: inout CFDictionary?
) -> Int32 {
    information = nil
    _ = (code, flags)
    return -1
}

func SecTrustGetCertificateCount(_ trust: SecTrust) -> Int {
    _ = trust
    return 0
}

func SecTrustGetCertificateAtIndex(_ trust: SecTrust, _ index: Int) -> SecCertificate? {
    _ = (trust, index)
    return nil
}

func SecCertificateCopyData(_ certificate: SecCertificate) -> Data {
    _ = certificate
    return Data()
}

@discardableResult
func CC_SHA1(
    _ data: UnsafeRawBufferPointer,
    _ length: CC_LONG,
    _ digest: inout [UInt8]
) -> UnsafeMutablePointer<UInt8>? {
    _ = (data, length)
    if digest.count < Int(CC_SHA1_DIGEST_LENGTH) {
        digest.append(contentsOf: repeatElement(0, count: Int(CC_SHA1_DIGEST_LENGTH) - digest.count))
    }
    for index in 0..<Int(CC_SHA1_DIGEST_LENGTH) {
        digest[index] = 0
    }
    return digest.withUnsafeMutableBufferPointer { $0.baseAddress }
}
#endif
