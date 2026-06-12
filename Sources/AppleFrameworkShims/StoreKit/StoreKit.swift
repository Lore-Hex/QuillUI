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

public enum AppStore {
    public static func requestReview() {}
    public static func requestReview<Scene>(in scene: Scene) {
        _ = scene
    }
}

// MARK: - StoreKit 1

public enum SKPaymentTransactionState: Int, Sendable {
    case purchasing = 0
    case purchased = 1
    case failed = 2
    case restored = 3
    case deferred = 4
}

public struct SKError: Error, Sendable {
    public enum Code: Int, Sendable {
        case unknown = 0
        case clientInvalid = 1
        case paymentCancelled = 2
        case paymentInvalid = 3
        case paymentNotAllowed = 4
        case storeProductNotAvailable = 5
        case cloudServicePermissionDenied = 6
        case cloudServiceNetworkConnectionFailed = 7
        case cloudServiceRevoked = 8
    }

    public let code: Code

    public init(_ code: Code = .unknown) {
        self.code = code
    }
}

extension SKError: LocalizedError {
    public var errorDescription: String? {
        switch code {
        case .unknown:
            return "StoreKit is unavailable on Linux."
        case .clientInvalid:
            return "The StoreKit client is invalid."
        case .paymentCancelled:
            return "The payment was cancelled."
        case .paymentInvalid:
            return "The payment is invalid."
        case .paymentNotAllowed:
            return "Payments are not allowed."
        case .storeProductNotAvailable:
            return "The product is not available."
        case .cloudServicePermissionDenied:
            return "Cloud service permission was denied."
        case .cloudServiceNetworkConnectionFailed:
            return "Cloud service network connection failed."
        case .cloudServiceRevoked:
            return "Cloud service access was revoked."
        }
    }
}

open class SKProductSubscriptionPeriod: NSObject, @unchecked Sendable {
    public enum Unit: UInt, Sendable {
        case day = 0
        case week = 1
        case month = 2
        case year = 3
    }

    public let numberOfUnits: Int
    public let unit: Unit

    public init(numberOfUnits: Int = 0, unit: Unit = .month) {
        self.numberOfUnits = numberOfUnits
        self.unit = unit
        super.init()
    }
}

open class SKProduct: NSObject, @unchecked Sendable {
    public let productIdentifier: String
    public let localizedDescription: String
    public let localizedTitle: String
    public let price: NSDecimalNumber
    public let priceLocale: Locale
    public let subscriptionGroupIdentifier: String?
    public let subscriptionPeriod: SKProductSubscriptionPeriod?

    public init(
        productIdentifier: String,
        localizedDescription: String = "",
        localizedTitle: String = "",
        price: NSDecimalNumber = 0,
        priceLocale: Locale = Locale(identifier: "en_US_POSIX"),
        subscriptionGroupIdentifier: String? = nil,
        subscriptionPeriod: SKProductSubscriptionPeriod? = nil
    ) {
        self.productIdentifier = productIdentifier
        self.localizedDescription = localizedDescription
        self.localizedTitle = localizedTitle
        self.price = price
        self.priceLocale = priceLocale
        self.subscriptionGroupIdentifier = subscriptionGroupIdentifier
        self.subscriptionPeriod = subscriptionPeriod
        super.init()
    }
}

open class SKPayment: NSObject, NSCopying, @unchecked Sendable {
    public let productIdentifier: String
    public internal(set) var requestData: Data?
    public internal(set) var quantity: Int
    public internal(set) var applicationUsername: String?

    public init(productIdentifier: String, requestData: Data? = nil, quantity: Int = 1) {
        self.productIdentifier = productIdentifier
        self.requestData = requestData
        self.quantity = quantity
        super.init()
    }

    public convenience init(product: SKProduct) {
        self.init(productIdentifier: product.productIdentifier)
    }

    open func copy(with zone: NSZone? = nil) -> Any {
        let payment = SKMutablePayment(productIdentifier: productIdentifier)
        payment.requestData = requestData
        payment.quantity = quantity
        payment.applicationUsername = applicationUsername
        return payment
    }
}

open class SKMutablePayment: SKPayment, @unchecked Sendable {
    public override var quantity: Int {
        get { super.quantity }
        set { super.quantity = newValue }
    }

    public override var applicationUsername: String? {
        get { super.applicationUsername }
        set { super.applicationUsername = newValue }
    }

    public var simulatesAskToBuyInSandbox: Bool = false

    public override var requestData: Data? {
        get { super.requestData }
        set { super.requestData = newValue }
    }

    public override init(productIdentifier: String, requestData: Data? = nil, quantity: Int = 1) {
        super.init(productIdentifier: productIdentifier, requestData: requestData, quantity: quantity)
    }

    public convenience init(product: SKProduct) {
        self.init(productIdentifier: product.productIdentifier)
    }
}

open class SKPaymentTransaction: NSObject, @unchecked Sendable {
    public let payment: SKPayment
    public let transactionState: SKPaymentTransactionState
    public let transactionIdentifier: String?
    public let transactionDate: Date?
    public let original: SKPaymentTransaction?
    public let error: Error?

    public init(
        payment: SKPayment,
        transactionState: SKPaymentTransactionState = .failed,
        transactionIdentifier: String? = nil,
        transactionDate: Date? = nil,
        original: SKPaymentTransaction? = nil,
        error: Error? = SKError(.paymentNotAllowed)
    ) {
        self.payment = payment
        self.transactionState = transactionState
        self.transactionIdentifier = transactionIdentifier
        self.transactionDate = transactionDate
        self.original = original
        self.error = error
        super.init()
    }
}

open class SKRequest: NSObject, @unchecked Sendable {
    public weak var delegate: SKRequestDelegate?

    open func start() {
        delegate?.requestDidFinish(self)
    }

    open func cancel() {}
}

public protocol SKRequestDelegate: AnyObject {
    func requestDidFinish(_ request: SKRequest)
    func request(_ request: SKRequest, didFailWithError error: Error)
}

public extension SKRequestDelegate {
    func requestDidFinish(_ request: SKRequest) {}
    func request(_ request: SKRequest, didFailWithError error: Error) {}
}

open class SKProductsResponse: NSObject, @unchecked Sendable {
    public let products: [SKProduct]
    public let invalidProductIdentifiers: [String]

    public init(products: [SKProduct] = [], invalidProductIdentifiers: [String] = []) {
        self.products = products
        self.invalidProductIdentifiers = invalidProductIdentifiers
        super.init()
    }
}

open class SKProductsRequest: SKRequest, @unchecked Sendable {
    public let productIdentifiers: Set<String>

    public init(productIdentifiers: Set<String>) {
        self.productIdentifiers = productIdentifiers
        super.init()
    }

    open override func start() {
        let response = SKProductsResponse(
            products: [],
            invalidProductIdentifiers: Array(productIdentifiers).sorted()
        )
        let productsDelegate = delegate as? SKProductsRequestDelegate
        productsDelegate?.productsRequest(self, didReceive: response)
        productsDelegate?.requestDidFinish(self)
    }
}

public protocol SKProductsRequestDelegate: SKRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse)
}

public extension SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {}
}

public protocol SKPaymentTransactionObserver: AnyObject {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction])
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue)
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error)
}

public extension SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {}
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {}
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {}
}

private final class WeakPaymentTransactionObserver: @unchecked Sendable {
    weak var value: SKPaymentTransactionObserver?

    init(_ value: SKPaymentTransactionObserver) {
        self.value = value
    }
}

open class SKPaymentQueue: NSObject, @unchecked Sendable {
    private static let shared = SKPaymentQueue()
    private let lock = NSLock()
    private var observers: [WeakPaymentTransactionObserver] = []

    public private(set) var transactions: [SKPaymentTransaction] = []

    open class func `default`() -> SKPaymentQueue {
        shared
    }

    open class func canMakePayments() -> Bool {
        false
    }

    open func add(_ observer: SKPaymentTransactionObserver) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakPaymentTransactionObserver(observer))
    }

    open func remove(_ observer: SKPaymentTransactionObserver) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    open func add(_ payment: SKPayment) {
        let transaction = SKPaymentTransaction(
            payment: payment,
            transactionState: .failed,
            transactionIdentifier: nil,
            transactionDate: Date(),
            original: nil,
            error: SKError(.paymentNotAllowed)
        )
        notifyUpdatedTransactions([transaction])
    }

    open func finishTransaction(_ transaction: SKPaymentTransaction) {
        lock.lock()
        transactions.removeAll { $0 === transaction }
        lock.unlock()
    }

    open func restoreCompletedTransactions() {
        notifyRestoreCompleted()
    }

    open func restoreCompletedTransactions(withApplicationUsername username: String?) {
        _ = username
        notifyRestoreCompleted()
    }

    private func liveObservers() -> [SKPaymentTransactionObserver] {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll { $0.value == nil }
        return observers.compactMap(\.value)
    }

    private func notifyUpdatedTransactions(_ newTransactions: [SKPaymentTransaction]) {
        lock.lock()
        transactions.append(contentsOf: newTransactions)
        observers.removeAll { $0.value == nil }
        let currentObservers = observers.compactMap(\.value)
        lock.unlock()

        for observer in currentObservers {
            observer.paymentQueue(self, updatedTransactions: newTransactions)
        }
    }

    private func notifyRestoreCompleted() {
        for observer in liveObservers() {
            observer.paymentQueueRestoreCompletedTransactionsFinished(self)
        }
    }
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
