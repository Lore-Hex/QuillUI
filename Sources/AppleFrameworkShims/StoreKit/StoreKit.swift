//
// QuillUI Linux shim for Apple's `StoreKit` (StoreKit 2 async API).
//
// SignalServiceKit's BackupSubscriptionManager fetches the paid-tier backups
// product, purchases it, and listens for transaction updates/entitlements. There
// is no App Store on Linux, so this is INERT: `Product.products(for:)` returns no
// products (so the manager throws MissingProductError), `Transaction.latest /
// .currentEntitlement` return nil, `Transaction.updates` yields nothing, and
// `purchase()` is unreachable (no product) but throws if ever called. In-app
// purchases / paid backups are therefore UNAVAILABLE on Linux. HONEST STATUS:
// no StoreKit transactions ever exist; paid backups cannot be purchased.
//
import Foundation

fileprivate struct StoreKitUnavailableOnLinux: Error, CustomStringConvertible {
    var description: String { "StoreKit is unavailable on Linux (no App Store)." }
}

// MARK: - VerificationResult

/// StoreKit 2's signed-payload wrapper. EXACTLY two cases (consumer switches over
/// `.verified` / `.unverified` with no default).
public enum VerificationResult<SignedType: Sendable>: Sendable {
    case verified(SignedType)
    case unverified(SignedType, VerificationError)

    public struct VerificationError: Error {
        public init() {}
    }

    /// Returns the payload when verified; throws when unverified (matches the
    /// real `payloadValue` the caller uses via `try?`).
    public var payloadValue: SignedType {
        get throws {
            switch self {
            case .verified(let value):
                return value
            case .unverified(_, let error):
                throw error
            }
        }
    }

    /// Always returns the wrapped payload regardless of verification.
    public var unsafePayloadValue: SignedType {
        switch self {
        case .verified(let value): return value
        case .unverified(let value, _): return value
        }
    }
}

// MARK: - Transaction

public struct Transaction: Sendable, Identifiable {
    public let id: UInt64
    public let originalID: UInt64
    public let productID: String
    public let purchaseDate: Date
    public let expirationDate: Date?

    public init(
        id: UInt64 = 0,
        originalID: UInt64 = 0,
        productID: String = "",
        purchaseDate: Date = Date(timeIntervalSince1970: 0),
        expirationDate: Date? = nil
    ) {
        self.id = id
        self.originalID = originalID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
    }

    /// Inert: marking a transaction finished is a no-op on Linux.
    public func finish() async {}

    public static func currentEntitlement(for productID: String) async -> VerificationResult<Transaction>? { nil }
    public static func latest(for productID: String) async -> VerificationResult<Transaction>? { nil }
    public static func all(for productID: String) -> Transactions { Transactions() }

    /// `Transaction.updates` — an async stream that never yields on Linux.
    public static var updates: Transactions { Transactions() }

    public struct Transactions: AsyncSequence, Sendable {
        public typealias Element = VerificationResult<Transaction>
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> VerificationResult<Transaction>? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }
}

// MARK: - Product

public struct Product: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let displayPrice: String

    public init(
        id: String = "",
        displayName: String = "",
        description: String = "",
        displayPrice: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
    }

    /// No App Store on Linux -> no products are ever available.
    public static func products(for identifiers: some Collection<String>) async throws -> [Product] { [] }

    /// Unreachable in practice (no product to purchase), but throws if called.
    public func purchase() async throws -> PurchaseResult {
        throw StoreKitUnavailableOnLinux()
    }

    public enum PurchaseResult {
        case success(VerificationResult<Transaction>)
        case userCancelled
        case pending
    }
}
