// Swift overlay for the upstream Objective-C OpenSSLEncryptionProvider island.
// Telegram-Mac instantiates OpenSSLEncryptionProvider() and hands it to
// NetworkInitializationArguments; the bignum/RSA math is inert until a real
// libcrypto-backed implementation lands (the EncryptionProvider overlay's
// QuillBignumContext shape).
@_exported import EncryptionProvider
import Foundation

public final class OpenSSLEncryptionProvider: EncryptionProvider {
    public init() {}

    public func createBignumContext() -> MTBignumContext { QuillBignumContext() }
    public func rsaEncrypt(withPublicKey publicKey: String, data: Data) -> Data? { _ = publicKey; return data }
    public func rsaEncryptPKCS1OAEP(withPublicKey publicKey: String, data: Data) -> Data? { _ = publicKey; return data }
    public func parseRSAPublicKey(_ publicKey: String) -> MTRsaPublicKey { QuillRsaPublicKey(publicKey) }
    public func macosRSAEncrypt(_ publicKey: String, data: Data) -> Data { _ = publicKey; return data }
}
