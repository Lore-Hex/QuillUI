//
// QuillUI Linux shim for Apple's `PassKit` (the Apple Pay subset SSK's donation
// flow uses).
//
// Apple Pay is unavailable on Linux, so this is INERT: `canMakePayments()`
// returns false (the donation UI falls back to card entry), and the payment /
// token objects exist only so the post-authorization parsing code compiles --
// no PKPayment is ever produced on Linux. HONEST STATUS: Apple Pay donations are
// unavailable; only the type surface exists.
//
import Foundation

public struct PKPaymentNetwork: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let visa = PKPaymentNetwork("Visa")
    public static let masterCard = PKPaymentNetwork("MasterCard")
    public static let amex = PKPaymentNetwork("Amex")
    public static let discover = PKPaymentNetwork("Discover")
    public static let JCB = PKPaymentNetwork("JCB")
    public static let chinaUnionPay = PKPaymentNetwork("ChinaUnionPay")
    public static let interac = PKPaymentNetwork("Interac")
    public static let privateLabel = PKPaymentNetwork("PrivateLabel")
    public static let maestro = PKPaymentNetwork("Maestro")
}

public struct PKMerchantCapability: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let capability3DS = PKMerchantCapability(rawValue: 1 << 0)
    public static let capabilityEMV = PKMerchantCapability(rawValue: 1 << 1)
    public static let capabilityCredit = PKMerchantCapability(rawValue: 1 << 2)
    public static let capabilityDebit = PKMerchantCapability(rawValue: 1 << 3)
}

open class PKPaymentSummaryItem: @unchecked Sendable {
    public var label: String
    public var amount: NSDecimalNumber
    public init(label: String, amount: NSDecimalNumber) {
        self.label = label
        self.amount = amount
    }
}

public final class PKPaymentRequest: @unchecked Sendable {
    public var paymentSummaryItems: [PKPaymentSummaryItem] = []
    public var merchantIdentifier: String = ""
    public var merchantCapabilities: PKMerchantCapability = []
    public var countryCode: String = ""
    public var currencyCode: String = ""
    public var supportedNetworks: [PKPaymentNetwork] = []
    public init() {}
}

public final class PKPaymentMethod: @unchecked Sendable {
    public var displayName: String?
    public var network: PKPaymentNetwork?
    public init() {}
}

public final class PKPaymentToken: @unchecked Sendable {
    public var transactionIdentifier: String = ""
    public var paymentData: Data = Data()
    public var paymentMethod: PKPaymentMethod = PKPaymentMethod()
    public init() {}
}

public final class PKPayment: @unchecked Sendable {
    public var token: PKPaymentToken = PKPaymentToken()
    public init() {}
}

public final class PKPaymentAuthorizationController: @unchecked Sendable {
    public init() {}
    /// No Apple Pay on Linux.
    public static func canMakePayments() -> Bool { false }
    public static func canMakePayments(usingNetworks supportedNetworks: [PKPaymentNetwork]) -> Bool { false }
    public static func canMakePayments(
        usingNetworks supportedNetworks: [PKPaymentNetwork],
        capabilities: PKMerchantCapability
    ) -> Bool { false }
}
