//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful Swift port of the root of the model hierarchy, originally
// Storage/TSYapDatabaseObject.{h,m} + Storage/BaseModel.h (ObjC, excluded on
// Linux). Hundreds of Swift files subclass this spine; on Apple it is imported
// via the SignalServiceKit umbrella, on Linux it must exist as same-module Swift.
//
// Behaviour mirrors the original .m exactly: UUID uniqueId, atomic-ish grdbId
// (an NSNumber row id), the three designated initializers + initWithCoder, the
// encodeIds / copyAndAssignIds helpers, exact-class hash/isEqual, the no-op
// data-store write hooks, and the SDSRecordDelegate updateRowId/clear/replace.
//
// RUNTIME NOTE (NSKeyedArchiver): on Apple these archive under their ObjC class
// names. Pure-Swift classes archive under mangled Swift names; when we wire the
// smoke/runtime target we must register class-name aliases for on-disk
// compatibility. That is a runtime wall, not a compile wall — tracked separately.
//
import Foundation

// MARK: - SDSRecordDelegate (declared in TSYapDatabaseObject.h)

/// Lets a freshly-inserted GRDB record hand its assigned row id back to the model.
public protocol SDSRecordDelegate: AnyObject {
    func updateRowId(_ rowId: Int64)
}

// MARK: - TSYapDatabaseObject

open class TSYapDatabaseObject: NSObject, SDSRecordDelegate {

    /// The unique identifier of the stored object. The setter is module-internal
    /// (ObjC exposed it readonly + settable via a class extension); SSK subclasses
    /// and the SDS layer assign it within the module.
    public internal(set) var uniqueId: String

    /// The GRDB row id. Should only ever be accessed within a GRDB write
    /// transaction (the original was `atomic`; writes here are confined to a
    /// write transaction so a bare property is sufficient).
    public internal(set) var grdbId: NSNumber?

    open class func generateUniqueId() -> String {
        UUID().uuidString
    }

    // MARK: Initializers

    public required override init() {
        self.uniqueId = TSYapDatabaseObject.generateUniqueId()
        self.grdbId = nil
        super.init()
    }

    public init(uniqueId: String) {
        if !uniqueId.isEmpty {
            self.uniqueId = uniqueId
        } else {
            owsFailDebug("Invalid uniqueId.")
            self.uniqueId = TSYapDatabaseObject.generateUniqueId()
        }
        self.grdbId = nil
        super.init()
    }

    public init(grdbId: Int64, uniqueId: String) {
        if !uniqueId.isEmpty {
            self.uniqueId = uniqueId
        } else {
            owsFailDebug("Invalid uniqueId.")
            self.uniqueId = TSYapDatabaseObject.generateUniqueId()
        }
        self.grdbId = NSNumber(value: grdbId)
        super.init()
    }

    public required init?(coder: NSCoder) {
        self.grdbId = coder.decodeObject(of: NSNumber.self, forKey: "grdbId")
        let decodedUniqueId = coder.decodeObject(of: NSString.self, forKey: "uniqueId") as String?
        if let decodedUniqueId, !decodedUniqueId.isEmpty {
            self.uniqueId = decodedUniqueId
        } else {
            owsFailDebug("Invalid uniqueId.")
            self.uniqueId = UUID().uuidString
        }
        super.init()
    }

    // MARK: Coding / copying helpers

    /// Encode the grdbId and uniqueId. Subclasses call this from `encode(with:)`.
    public func encodeIds(with coder: NSCoder) {
        if let grdbId {
            coder.encode(grdbId, forKey: "grdbId")
        }
        coder.encode(uniqueId, forKey: "uniqueId")
    }

    /// Creates a copy of the receiver's dynamic class and assigns the grdbId and uniqueId.
    public func copyAndAssignIds(with zone: NSZone?) -> Any {
        let result = type(of: self).init()
        result.grdbId = self.grdbId
        result.uniqueId = self.uniqueId
        return result
    }

    // MARK: Equality

    open override var hash: Int {
        var result = 0
        result ^= grdbId?.hash ?? 0
        result ^= uniqueId.hashValue
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TSYapDatabaseObject,
              type(of: other) == type(of: self) else {
            return false
        }
        return grdbId == other.grdbId && uniqueId == other.uniqueId
    }

    // MARK: Persistence flags

    open var shouldBeSaved: Bool { true }

    // MARK: Data Store Write Hooks

    open func anyWillInsert(with transaction: DBWriteTransaction) {}
    open func anyDidInsert(with transaction: DBWriteTransaction) {}
    open func anyWillUpdate(with transaction: DBWriteTransaction) {}
    open func anyDidUpdate(with transaction: DBWriteTransaction) {}
    open func anyWillRemove(with transaction: DBWriteTransaction) {}
    open func anyDidRemove(with transaction: DBWriteTransaction) {}

    // MARK: SDSRecordDelegate / row id management
    //
    // These must only ever be called within a GRDB write transaction.

    public func updateRowId(_ rowId: Int64) {
        if let grdbId {
            owsAssertDebug(grdbId.int64Value == rowId)
            owsFailDebug("grdbId set more than once.")
        }
        self.grdbId = NSNumber(value: rowId)
    }

    public func clearRowId() {
        self.grdbId = nil
    }

    /// Facilitates a database object replacement. See OWSRecoverableDecryptionPlaceholder.
    public func replaceRowId(_ rowId: Int64, uniqueId: String) {
        self.grdbId = NSNumber(value: rowId)
        self.uniqueId = uniqueId
    }
}

// MARK: - BaseModel  (Storage/BaseModel.h)

// TODO: Upstream comment: rename and/or merge with TSYapDatabaseObject.
open class BaseModel: TSYapDatabaseObject {}
