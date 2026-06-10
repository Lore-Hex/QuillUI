import Foundation

public enum LogLevel: Sendable {
    case error
    case warn
    case info
    case debug
}

public struct StoreProduct: Identifiable, Sendable {
    public var id: String { productIdentifier }
    public let productIdentifier: String
    public let price: Decimal
    public let localizedPriceString: String

    public init(productIdentifier: String, price: Decimal = 0, localizedPriceString: String = "") {
        self.productIdentifier = productIdentifier
        self.price = price
        self.localizedPriceString = localizedPriceString
    }
}

public struct EntitlementInfo: Sendable {
    public var isActive: Bool
    public init(isActive: Bool = false) {
        self.isActive = isActive
    }
}

public struct EntitlementInfos: Sendable {
    public var active: [String: EntitlementInfo]

    public init(active: [String: EntitlementInfo] = [:]) {
        self.active = active
    }

    public subscript(_ key: String) -> EntitlementInfo? {
        active[key]
    }
}

public struct CustomerInfo: Sendable {
    public var entitlements: EntitlementInfos

    public init(entitlements: EntitlementInfos = EntitlementInfos()) {
        self.entitlements = entitlements
    }
}

public struct PurchaseResultData: Sendable {
    public var userCancelled: Bool
    public init(userCancelled: Bool = true) {
        self.userCancelled = userCancelled
    }
}

public final class Purchases: @unchecked Sendable {
    public nonisolated(unsafe) static var logLevel: LogLevel = .error
    public static let shared = Purchases()

    private init() {}

    public static func configure(withAPIKey apiKey: String) {
        _ = apiKey
    }

    public func getCustomerInfo(_ completion: @escaping (CustomerInfo?, (any Error)?) -> Void) {
        completion(CustomerInfo(), nil)
    }

    public func getProducts(_ productIdentifiers: [String], completion: @escaping ([StoreProduct]) -> Void) {
        completion(productIdentifiers.map { StoreProduct(productIdentifier: $0) })
    }

    public func purchase(product: StoreProduct) async throws -> PurchaseResultData {
        _ = product
        return PurchaseResultData()
    }

    public func restorePurchases(_ completion: @escaping (CustomerInfo?, (any Error)?) -> Void) {
        completion(CustomerInfo(), nil)
    }
}
