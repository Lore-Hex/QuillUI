//
// QuillUI Linux shim for Apple's `CloudKit` framework.
//
// HONEST STATUS: compile-compatible service boundary. The local value surface
// covers common CKContainer/CKDatabase/CKRecord shapes, while all networked
// CloudKit operations report unavailable and record diagnostics. The intended
// production backend is an adapter over OpenCloudKit's CloudKit Web Services
// client once authentication/configuration is modeled in QuillKit.
//
import Foundation
import QuillKit

public let CKErrorDomain = "CKErrorDomain"

public enum QuillCloudKitCompatibility {
    public static let openCloudKitProviderName = "OpenCloudKit"
    public static let openCloudKitRepositoryURL = "https://github.com/cocologics/OpenCloudKit"
    public static let status = "CloudKit Web Services provider documented; not linked by default."

    static func unavailableError(operation: String) -> CKError {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "CloudKit",
            operation: operation,
            severity: .unsupported,
            message: "\(openCloudKitProviderName) backend is not configured yet (\(openCloudKitRepositoryURL))."
        )
        return CKError(.serviceUnavailable)
    }
}

public enum CKAccountStatus: Int, Sendable {
    case couldNotDetermine = 0
    case available = 1
    case restricted = 2
    case noAccount = 3
    case temporarilyUnavailable = 4
}

public struct CKError: Error, CustomNSError, LocalizedError, Sendable {
    public enum Code: Int, Sendable {
        case internalError = 1
        case partialFailure = 2
        case networkUnavailable = 3
        case networkFailure = 4
        case badContainer = 5
        case serviceUnavailable = 6
        case requestRateLimited = 7
        case missingEntitlement = 8
        case notAuthenticated = 9
        case permissionFailure = 10
        case unknownItem = 11
        case invalidArguments = 12
        case resultsTruncated = 13
        case serverRecordChanged = 14
        case serverRejectedRequest = 15
        case assetFileNotFound = 16
        case assetFileModified = 17
        case incompatibleVersion = 18
        case constraintViolation = 19
        case operationCancelled = 20
        case changeTokenExpired = 21
        case batchRequestFailed = 22
        case zoneBusy = 23
        case badDatabase = 24
        case quotaExceeded = 25
        case zoneNotFound = 26
        case limitExceeded = 27
        case userDeletedZone = 28
        case tooManyParticipants = 29
        case alreadyShared = 30
        case referenceViolation = 31
        case managedAccountRestricted = 32
        case participantMayNeedVerification = 33
        case serverResponseLost = 34
    }

    public static let errorDomain = CKErrorDomain

    public let code: Code

    public init(_ code: Code) {
        self.code = code
    }

    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [:] }

    public var errorDescription: String? {
        switch code {
        case .serviceUnavailable:
            return "CloudKit is unavailable on Linux until an OpenCloudKit backend is configured."
        case .notAuthenticated:
            return "CloudKit authentication is unavailable."
        case .missingEntitlement:
            return "CloudKit entitlements are unavailable on Linux."
        default:
            return "CloudKit operation failed with \(code)."
        }
    }
}

public protocol CKRecordValue {}

extension String: CKRecordValue {}
extension NSString: CKRecordValue {}
extension Int: CKRecordValue {}
extension Int64: CKRecordValue {}
extension Double: CKRecordValue {}
extension Bool: CKRecordValue {}
extension NSNumber: CKRecordValue {}
extension Data: CKRecordValue {}
extension NSData: CKRecordValue {}
extension Date: CKRecordValue {}
extension NSDate: CKRecordValue {}
extension URL: CKRecordValue {}
extension UUID: CKRecordValue {}
extension Array: CKRecordValue where Element: CKRecordValue {}
extension Dictionary: CKRecordValue where Key == String, Value: CKRecordValue {}

public final class CKAsset: @unchecked Sendable, CKRecordValue {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public final class CKRecordZone: @unchecked Sendable {
    public struct ID: Hashable, Sendable {
        public static let `default` = ID(zoneName: "_defaultZone", ownerName: "__defaultOwner__")

        public let zoneName: String
        public let ownerName: String

        public init(zoneName: String, ownerName: String = "__defaultOwner__") {
            self.zoneName = zoneName
            self.ownerName = ownerName
        }
    }

    public let zoneID: ID

    public init(zoneName: String) {
        self.zoneID = ID(zoneName: zoneName)
    }

    public init(zoneID: ID) {
        self.zoneID = zoneID
    }

    public static func `default`() -> CKRecordZone {
        CKRecordZone(zoneID: .default)
    }
}

public final class CKRecord: @unchecked Sendable {
    public struct ID: Hashable, Sendable {
        public let recordName: String
        public let zoneID: CKRecordZone.ID

        public init(recordName: String = UUID().uuidString, zoneID: CKRecordZone.ID = .default) {
            self.recordName = recordName
            self.zoneID = zoneID
        }
    }

    public enum ReferenceAction: Int, Sendable {
        case none = 0
        case deleteSelf = 1
    }

    public struct Reference: Sendable, CKRecordValue {
        public let recordID: ID
        public let action: ReferenceAction

        public init(recordID: ID, action: ReferenceAction) {
            self.recordID = recordID
            self.action = action
        }

        public init(record: CKRecord, action: ReferenceAction) {
            self.recordID = record.recordID
            self.action = action
        }
    }

    public let recordType: String
    public let recordID: ID

    private var fields: [String: CKRecordValue]

    public init(recordType: String, recordID: ID = ID()) {
        self.recordType = recordType
        self.recordID = recordID
        self.fields = [:]
    }

    public subscript(key: String) -> CKRecordValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }

    public func object(forKey key: String) -> CKRecordValue? {
        fields[key]
    }

    public func setObject(_ object: CKRecordValue?, forKey key: String) {
        fields[key] = object
    }

    public func allKeys() -> [String] {
        fields.keys.sorted()
    }
}

public final class CKQuery: @unchecked Sendable {
    public let recordType: String
    public let predicate: NSPredicate
    public var sortDescriptors: [NSSortDescriptor]?

    public init(recordType: String, predicate: NSPredicate) {
        self.recordType = recordType
        self.predicate = predicate
    }
}

open class CKSubscription: @unchecked Sendable {
    public struct ID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }
    }

    public enum SubscriptionType: Int, Sendable {
        case query = 1
        case recordZone = 2
        case database = 3
    }

    public let subscriptionID: ID
    public let subscriptionType: SubscriptionType

    public init(subscriptionID: ID, subscriptionType: SubscriptionType) {
        self.subscriptionID = subscriptionID
        self.subscriptionType = subscriptionType
    }
}

public final class CKNotificationInfo: @unchecked Sendable {
    public var alertBody: String?
    public var alertLocalizationKey: String?
    public var soundName: String?
    public var shouldBadge: Bool

    public init() {
        self.shouldBadge = false
    }
}

public final class CKQuerySubscription: CKSubscription, @unchecked Sendable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let firesOnRecordCreation = Options(rawValue: 1 << 0)
        public static let firesOnRecordUpdate = Options(rawValue: 1 << 1)
        public static let firesOnRecordDeletion = Options(rawValue: 1 << 2)
        public static let firesOnce = Options(rawValue: 1 << 3)
    }

    public let recordType: String
    public let predicate: NSPredicate
    public let options: Options
    public var notificationInfo: CKNotificationInfo?

    public init(recordType: String, predicate: NSPredicate, subscriptionID: CKSubscription.ID, options: Options = []) {
        self.recordType = recordType
        self.predicate = predicate
        self.options = options
        super.init(subscriptionID: subscriptionID, subscriptionType: .query)
    }
}

public final class CKDatabaseSubscription: CKSubscription, @unchecked Sendable {
    public var notificationInfo: CKNotificationInfo?

    public init(subscriptionID: CKSubscription.ID) {
        super.init(subscriptionID: subscriptionID, subscriptionType: .database)
    }
}

public final class CKRecordZoneSubscription: CKSubscription, @unchecked Sendable {
    public let zoneID: CKRecordZone.ID
    public var notificationInfo: CKNotificationInfo?

    public init(zoneID: CKRecordZone.ID, subscriptionID: CKSubscription.ID) {
        self.zoneID = zoneID
        super.init(subscriptionID: subscriptionID, subscriptionType: .recordZone)
    }
}

public final class CKDatabase: @unchecked Sendable {
    public enum Scope: Int, Sendable {
        case `public` = 1
        case `private` = 2
        case shared = 3
    }

    public let databaseScope: Scope

    public init(databaseScope: Scope = .private) {
        self.databaseScope = databaseScope
    }

    public func save(_ record: CKRecord, completionHandler: @escaping (CKRecord?, Error?) -> Void) {
        completionHandler(nil, QuillCloudKitCompatibility.unavailableError(operation: "saveRecord"))
    }

    public func save(record: CKRecord, completionHandler: @escaping (CKRecord?, Error?) -> Void) {
        save(record, completionHandler: completionHandler)
    }

    public func fetch(withRecordID recordID: CKRecord.ID, completionHandler: @escaping (CKRecord?, Error?) -> Void) {
        completionHandler(nil, QuillCloudKitCompatibility.unavailableError(operation: "fetchRecord"))
    }

    public func delete(withRecordID recordID: CKRecord.ID, completionHandler: @escaping (CKRecord.ID?, Error?) -> Void) {
        completionHandler(nil, QuillCloudKitCompatibility.unavailableError(operation: "deleteRecord"))
    }

    public func perform(_ query: CKQuery, inZoneWith zoneID: CKRecordZone.ID?, completionHandler: @escaping ([CKRecord]?, Error?) -> Void) {
        completionHandler(nil, QuillCloudKitCompatibility.unavailableError(operation: "performQuery"))
    }

    public func save(_ subscription: CKSubscription, completionHandler: @escaping (CKSubscription?, Error?) -> Void) {
        completionHandler(nil, QuillCloudKitCompatibility.unavailableError(operation: "saveSubscription"))
    }
}

public typealias CKDatabaseScope = CKDatabase.Scope

public final class CKContainer: @unchecked Sendable {
    public let containerIdentifier: String?
    public let publicCloudDatabase: CKDatabase
    public let privateCloudDatabase: CKDatabase
    public let sharedCloudDatabase: CKDatabase

    public init(identifier: String? = nil) {
        self.containerIdentifier = identifier
        self.publicCloudDatabase = CKDatabase(databaseScope: .public)
        self.privateCloudDatabase = CKDatabase(databaseScope: .private)
        self.sharedCloudDatabase = CKDatabase(databaseScope: .shared)
    }

    public static func `default`() -> CKContainer {
        CKContainer()
    }

    public convenience init(containerIdentifier: String) {
        self.init(identifier: containerIdentifier)
    }

    public func accountStatus(completionHandler: @escaping (CKAccountStatus, Error?) -> Void) {
        completionHandler(.couldNotDetermine, QuillCloudKitCompatibility.unavailableError(operation: "accountStatus"))
    }

    public func fetchUserRecordID(completionHandler: @escaping (CKRecord.ID?, Error?) -> Void) {
        completionHandler(nil, QuillCloudKitCompatibility.unavailableError(operation: "fetchUserRecordID"))
    }
}
