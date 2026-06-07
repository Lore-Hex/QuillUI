//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Value types from Payments/TSPaymentModels.h (a mixed-language dir whose ObjC
// is excluded): TSPaymentAmount, TSPaymentAddress, TSPaymentNotification. The
// fourth class in that header, TSArchivedPaymentInfo, is already ported in
// QuillOWSOutgoingArchivedPaymentMessage.swift, and the TSPayment* enums are in
// TSModelEnums.swift. Porting these lets the Payments Swift + payment-message
// consumers resolve, independent of the dir inclusion.
//
import Foundation

// MARK: - TSPaymentAmount

public class TSPaymentAmount: NSObject, NSSecureCoding, NSCopying {
    public internal(set) var currency: TSPaymentCurrency
    public internal(set) var picoMob: UInt64

    public init(currency: TSPaymentCurrency, picoMob: UInt64) {
        self.currency = currency
        self.picoMob = picoMob
        super.init()
    }

    public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        self.currency = TSPaymentCurrency(rawValue: UInt(bitPattern: Int(coder.decodeInt64(forKey: "currency")))) ?? .unknown
        self.picoMob = UInt64(bitPattern: coder.decodeInt64(forKey: "picoMob"))
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(Int64(bitPattern: UInt64(currency.rawValue)), forKey: "currency")
        coder.encode(Int64(bitPattern: picoMob), forKey: "picoMob")
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        TSPaymentAmount(currency: currency, picoMob: picoMob)
    }

    public override var hash: Int { Int(truncatingIfNeeded: picoMob) ^ Int(currency.rawValue) }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TSPaymentAmount else { return false }
        return currency == other.currency && picoMob == other.picoMob
    }
}

// MARK: - TSPaymentAddress

public class TSPaymentAddress: NSObject {
    public internal(set) var currency: TSPaymentCurrency
    public internal(set) var mobileCoinPublicAddressData: Data

    public init(currency: TSPaymentCurrency, mobileCoinPublicAddressData: Data) {
        self.currency = currency
        self.mobileCoinPublicAddressData = mobileCoinPublicAddressData
        super.init()
    }
}

// MARK: - TSPaymentNotification

public class TSPaymentNotification: NSObject, NSSecureCoding, NSCopying {
    public internal(set) var memoMessage: String?
    public internal(set) var mcReceiptData: Data

    public init(memoMessage: String?, mcReceiptData: Data) {
        self.memoMessage = memoMessage
        self.mcReceiptData = mcReceiptData
        super.init()
    }

    public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        self.memoMessage = coder.decodeObject(of: NSString.self, forKey: "memoMessage") as String?
        self.mcReceiptData = (coder.decodeObject(of: NSData.self, forKey: "mcReceiptData") as Data?) ?? Data()
        super.init()
    }

    public func encode(with coder: NSCoder) {
        if let memoMessage { coder.encode(memoMessage, forKey: "memoMessage") }
        coder.encode(mcReceiptData, forKey: "mcReceiptData")
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        TSPaymentNotification(memoMessage: memoMessage, mcReceiptData: mcReceiptData)
    }

    public override var hash: Int {
        (memoMessage as NSString?)?.hash ?? 0 ^ (mcReceiptData as NSData).hash
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TSPaymentNotification else { return false }
        return memoMessage == other.memoMessage && mcReceiptData == other.mcReceiptData
    }
}
