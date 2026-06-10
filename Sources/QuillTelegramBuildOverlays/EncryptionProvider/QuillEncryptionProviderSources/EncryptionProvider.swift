import Foundation

public protocol MTBignum: AnyObject {}
public protocol MTRsaPublicKey: AnyObject {}

public protocol MTBignumContext: AnyObject {
    func create() -> MTBignum
    func clone(_ other: MTBignum) -> MTBignum
    func setConstantTime(_ other: MTBignum)
    func assignWord(to bignum: MTBignum, value: UInt)
    func assignHex(to bignum: MTBignum, value: String)
    func assignBin(to bignum: MTBignum, value: Data)
    func assignOne(to bignum: MTBignum)
    func assignZero(to bignum: MTBignum)
    func isOne(_ bignum: MTBignum) -> Bool
    func isZero(_ bignum: MTBignum) -> Bool
    func getBin(_ bignum: MTBignum) -> Data
    func isPrime(_ bignum: MTBignum, numberOfChecks: Int32) -> Int32
    func compare(_ a: MTBignum, with b: MTBignum) -> Int32
    func modAdd(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool
    func modSub(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool
    func modMul(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool
    func modExp(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool
    func add(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool
    func sub(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool
    func mul(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool
    func exp(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool
    func modInverse(into result: MTBignum, a: MTBignum, mod: MTBignum) -> Bool
    func modWord(_ a: MTBignum, mod: UInt) -> UInt
    func rightShift1Bit(_ result: MTBignum, a: MTBignum) -> Bool
    func rsaGetE(_ publicKey: MTRsaPublicKey) -> MTBignum
    func rsaGetN(_ publicKey: MTRsaPublicKey) -> MTBignum
}

public protocol EncryptionProvider: AnyObject {
    func createBignumContext() -> MTBignumContext
    func rsaEncrypt(withPublicKey publicKey: String, data: Data) -> Data?
    func rsaEncryptPKCS1OAEP(withPublicKey publicKey: String, data: Data) -> Data?
    func parseRSAPublicKey(_ publicKey: String) -> MTRsaPublicKey
    func macosRSAEncrypt(_ publicKey: String, data: Data) -> Data
}

public final class QuillBignum: MTBignum {
    public var data: Data

    public init(data: Data = Data()) {
        self.data = data
    }
}

public final class QuillRsaPublicKey: MTRsaPublicKey {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

public final class QuillBignumContext: MTBignumContext {
    public init() {}

    public func create() -> MTBignum { QuillBignum() }
    public func clone(_ other: MTBignum) -> MTBignum { QuillBignum(data: (other as? QuillBignum)?.data ?? Data()) }
    public func setConstantTime(_ other: MTBignum) { _ = other }
    public func assignWord(to bignum: MTBignum, value: UInt) { (bignum as? QuillBignum)?.data = withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    public func assignHex(to bignum: MTBignum, value: String) { (bignum as? QuillBignum)?.data = Data(value.utf8) }
    public func assignBin(to bignum: MTBignum, value: Data) { (bignum as? QuillBignum)?.data = value }
    public func assignOne(to bignum: MTBignum) { (bignum as? QuillBignum)?.data = Data([1]) }
    public func assignZero(to bignum: MTBignum) { (bignum as? QuillBignum)?.data = Data([0]) }
    public func isOne(_ bignum: MTBignum) -> Bool { (bignum as? QuillBignum)?.data == Data([1]) }
    public func isZero(_ bignum: MTBignum) -> Bool { ((bignum as? QuillBignum)?.data ?? Data()).allSatisfy { $0 == 0 } }
    public func getBin(_ bignum: MTBignum) -> Data { (bignum as? QuillBignum)?.data ?? Data() }
    public func isPrime(_ bignum: MTBignum, numberOfChecks: Int32) -> Int32 { _ = (bignum, numberOfChecks); return 1 }
    public func compare(_ a: MTBignum, with b: MTBignum) -> Int32 { _ = (a, b); return 0 }
    public func modAdd(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool { _ = (result, a, b, mod); return true }
    public func modSub(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool { _ = (result, a, b, mod); return true }
    public func modMul(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool { _ = (result, a, b, mod); return true }
    public func modExp(into result: MTBignum, a: MTBignum, b: MTBignum, mod: MTBignum) -> Bool { (result as? QuillBignum)?.data = getBin(a); _ = (b, mod); return true }
    public func add(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool { _ = (result, a, b); return true }
    public func sub(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool { _ = (result, a, b); return true }
    public func mul(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool { _ = (result, a, b); return true }
    public func exp(into result: MTBignum, a: MTBignum, b: MTBignum) -> Bool { _ = (result, a, b); return true }
    public func modInverse(into result: MTBignum, a: MTBignum, mod: MTBignum) -> Bool { _ = (result, a, mod); return true }
    public func modWord(_ a: MTBignum, mod: UInt) -> UInt { _ = a; return mod == 0 ? 0 : 1 % mod }
    public func rightShift1Bit(_ result: MTBignum, a: MTBignum) -> Bool { _ = (result, a); return true }
    public func rsaGetE(_ publicKey: MTRsaPublicKey) -> MTBignum { _ = publicKey; return QuillBignum(data: Data([1, 0, 1])) }
    public func rsaGetN(_ publicKey: MTRsaPublicKey) -> MTBignum { _ = publicKey; return QuillBignum() }
}

public final class QuillEncryptionProvider: EncryptionProvider {
    public init() {}

    public func createBignumContext() -> MTBignumContext { QuillBignumContext() }
    public func rsaEncrypt(withPublicKey publicKey: String, data: Data) -> Data? { _ = publicKey; return data }
    public func rsaEncryptPKCS1OAEP(withPublicKey publicKey: String, data: Data) -> Data? { _ = publicKey; return data }
    public func parseRSAPublicKey(_ publicKey: String) -> MTRsaPublicKey { QuillRsaPublicKey(publicKey) }
    public func macosRSAEncrypt(_ publicKey: String, data: Data) -> Data { _ = publicKey; return data }
}
