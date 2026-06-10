import Foundation
#if canImport(Glibc)
import Glibc
#endif

private enum QuillOpenSSL {
    typealias EVPDigest = @convention(c) (
        UnsafeRawPointer?,
        Int,
        UnsafeMutablePointer<UInt8>?,
        UnsafeMutablePointer<UInt32>?,
        OpaquePointer?,
        OpaquePointer?
    ) -> Int32
    typealias EVPDigestFactory = @convention(c) () -> OpaquePointer?
    typealias EVPCipherFactory = @convention(c) () -> OpaquePointer?
    typealias EVPCipherContextNew = @convention(c) () -> OpaquePointer?
    typealias EVPCipherContextFree = @convention(c) (OpaquePointer?) -> Void
    typealias EVPCipherInit = @convention(c) (
        OpaquePointer?,
        OpaquePointer?,
        OpaquePointer?,
        UnsafeRawPointer?,
        UnsafeRawPointer?,
        Int32
    ) -> Int32
    typealias EVPCipherUpdate = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<UInt8>?,
        UnsafeMutablePointer<Int32>?,
        UnsafeRawPointer?,
        Int32
    ) -> Int32
    typealias EVPCipherFinal = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<UInt8>?,
        UnsafeMutablePointer<Int32>?
    ) -> Int32
    typealias EVPCipherSetPadding = @convention(c) (OpaquePointer?, Int32) -> Int32

    static let handle: UnsafeMutableRawPointer? = {
        #if canImport(Glibc)
        return dlopen("libcrypto.so.3", RTLD_NOW) ?? dlopen("libcrypto.so", RTLD_NOW)
        #else
        return nil
        #endif
    }()

    static func symbol<Function>(_ name: String, as type: Function.Type = Function.self) -> Function? {
        guard let handle, let raw = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(raw, to: Function.self)
    }

    static func digest(_ bytes: UnsafeRawPointer, count: Int32, factoryName: String, length: Int) -> Data {
        guard
            let digest: EVPDigest = symbol("EVP_Digest"),
            let factory: EVPDigestFactory = symbol(factoryName),
            let digestType = factory()
        else {
            return Data(count: length)
        }

        var output = [UInt8](repeating: 0, count: length)
        var outputLength: UInt32 = 0
        let status = output.withUnsafeMutableBufferPointer { outputBuffer -> Int32 in
            digest(bytes, Swift.max(0, Int(count)), outputBuffer.baseAddress, &outputLength, digestType, nil)
        }
        guard status == 1 else {
            return Data(count: length)
        }
        return Data(output.prefix(Int(outputLength)))
    }

    static func aesCBC(encrypt: Bool, key: Data, iv: Data, data: Data) -> Data? {
        guard key.count == 32, iv.count == 16 else {
            return nil
        }
        guard
            let contextNew: EVPCipherContextNew = symbol("EVP_CIPHER_CTX_new"),
            let contextFree: EVPCipherContextFree = symbol("EVP_CIPHER_CTX_free"),
            let cipherFactory: EVPCipherFactory = symbol("EVP_aes_256_cbc"),
            let cipher = cipherFactory(),
            let cipherInit: EVPCipherInit = symbol("EVP_CipherInit_ex"),
            let cipherUpdate: EVPCipherUpdate = symbol("EVP_CipherUpdate"),
            let cipherFinal: EVPCipherFinal = symbol("EVP_CipherFinal_ex"),
            let setPadding: EVPCipherSetPadding = symbol("EVP_CIPHER_CTX_set_padding"),
            let context = contextNew()
        else {
            return nil
        }
        defer { contextFree(context) }

        var output = [UInt8](repeating: 0, count: data.count + 16)
        var updateLength: Int32 = 0
        var finalLength: Int32 = 0

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    output.withUnsafeMutableBufferPointer { outputBuffer -> Int32 in
                        guard let outputBase = outputBuffer.baseAddress else {
                            return 0
                        }
                        guard cipherInit(context, cipher, nil, keyBytes.baseAddress, ivBytes.baseAddress, encrypt ? 1 : 0) == 1 else {
                            return 0
                        }
                        guard setPadding(context, 0) == 1 else {
                            return 0
                        }
                        guard cipherUpdate(context, outputBase, &updateLength, dataBytes.baseAddress, Int32(data.count)) == 1 else {
                            return 0
                        }
                        return cipherFinal(context, outputBase.advanced(by: Int(updateLength)), &finalLength)
                    }
                }
            }
        }

        guard status == 1 else {
            return nil
        }
        return Data(output.prefix(Int(updateLength + finalLength)))
    }
}

public func CryptoMD5(_ bytes: UnsafeRawPointer, _ count: Int32) -> Data {
    QuillOpenSSL.digest(bytes, count: count, factoryName: "EVP_md5", length: 16)
}

public func CryptoSHA1(_ bytes: UnsafeRawPointer, _ count: Int32) -> Data {
    QuillOpenSSL.digest(bytes, count: count, factoryName: "EVP_sha1", length: 20)
}

public func CryptoSHA256(_ bytes: UnsafeRawPointer, _ count: Int32) -> Data {
    QuillOpenSSL.digest(bytes, count: count, factoryName: "EVP_sha256", length: 32)
}

public func CryptoSHA512(_ bytes: UnsafeRawPointer, _ count: Int32) -> Data {
    QuillOpenSSL.digest(bytes, count: count, factoryName: "EVP_sha512", length: 64)
}

public final class IncrementalMD5 {
    private var data = Data()
    private var completedDigest: Data?

    public init() {}

    public func update(_ data: Data) {
        guard completedDigest == nil else { return }
        self.data.append(data)
    }

    public func update(_ bytes: UnsafeRawPointer, count: Int32) {
        guard completedDigest == nil else { return }
        data.append(bytes.assumingMemoryBound(to: UInt8.self), count: Swift.max(0, Int(count)))
    }

    public func complete() -> Data {
        if let completedDigest {
            return completedDigest
        }
        let digest = data.withUnsafeBytes { bytes -> Data in
            guard let baseAddress = bytes.baseAddress else {
                var empty: UInt8 = 0
                return CryptoMD5(&empty, 0)
            }
            return CryptoMD5(baseAddress, Int32(bytes.count))
        }
        completedDigest = digest
        return digest
    }
}

public func CryptoAES(_ encrypt: Bool, _ key: Data, _ iv: Data, _ data: Data) -> Data? {
    QuillOpenSSL.aesCBC(encrypt: encrypt, key: key, iv: iv, data: data)
}
