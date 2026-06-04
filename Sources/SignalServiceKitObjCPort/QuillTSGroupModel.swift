//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful Swift port of Groups/TSGroupModel.{h,m} (ObjC, excluded on Linux) — a
// standalone NSObject<NSSecureCoding, NSCopying> archived into the thread/info
// records. TSGroupModelV2 (the V2-groups subclass) is a separate later port.
//
// PASS 1 scope: the extern group-id/avatar constants (referenced from Swift), the
// GroupsVersion enum, and the base class's stored props + builder/NSCoding inits,
// encode/decode (with the schema migrations), exact-class hash/isEqual, copy, and
// the groupsVersion/groupMembership/groupNameOrDefault accessors.
//
// Pass-1 deferrals (noted; no contract requirement): avatar persistence
// (`persistAvatarData`) is skipped so the `avatarData:` init argument is accepted
// but not hashed/stored; the GroupManager.isValidGroupId debug assert is dropped;
// the `!isKindOfClass:TSGroupModelV2` discriminator in encode is dropped until V2
// is ported (V2 will override encode); `groupName` is the raw stored value (the
// upstream getter applies `filterStringForDisplay`).
//
import Foundation

public let kGroupIdLengthV1: UInt = 16
public let kGroupIdLengthV2: UInt = 32
public let kMaxEncryptedAvatarSize: UInt64 = 3 * 1024 * 1024
// kMaxEncryptedAvatarSize minus padding-length(4) - protobuf overhead(1+4) -
// padding(0) - tag&nonce(16+12) - reserved(1). See TSGroupModel.m.
public let kMaxAvatarSize: UInt64 = kMaxEncryptedAvatarSize - 4 - 1 - 4 - 0 - 16 - 12 - 1

private let tsGroupModelSchemaVersion: UInt = 2

// MARK: - GroupsVersion (declared in TSGroupModel.h)

public enum GroupsVersion: UInt32 {
    case v1 = 0
    case v2 = 1
}

// MARK: - TSGroupModel

open class TSGroupModel: NSObject, NSSecureCoding, NSCopying {

    /// Includes administrators and normal members.
    public internal(set) var groupMembers: [SignalServiceAddress]
    public internal(set) var groupName: String?
    public internal(set) var groupId: Data
    public internal(set) var addedByAddress: SignalServiceAddress?

    /// Always PNG when present.
    public internal(set) var legacyAvatarData: Data?
    public internal(set) var avatarHash: String?

    internal var groupModelSchemaVersion: UInt

    // MARK: Computed

    open var groupsVersion: GroupsVersion { .v1 }

    open var groupMembership: GroupMembership { GroupMembership(v1Members: groupMembers) }

    public var groupNameOrDefault: String {
        if let groupName, !groupName.isEmpty {
            return groupName
        }
        return TSGroupThread.defaultGroupName
    }

    // MARK: Initializers

    public init(groupId: Data,
                name: String?,
                avatarData: Data?,
                members: [SignalServiceAddress],
                addedByAddress: SignalServiceAddress?) {
        self.groupId = groupId
        self.groupName = name
        self.groupMembers = members
        self.addedByAddress = addedByAddress
        self.legacyAvatarData = nil
        self.avatarHash = nil
        self.groupModelSchemaVersion = tsGroupModelSchemaVersion
        super.init()
        // PASS 1: avatarData persistence + GroupManager.isValidGroupId assert deferred.
        _ = avatarData
    }

    // MARK: NSSecureCoding

    public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        self.addedByAddress = coder.decodeObject(of: SignalServiceAddress.self, forKey: "addedByAddress")
        self.avatarHash = coder.decodeObject(of: NSString.self, forKey: "avatarHash") as String?
        self.groupId = (coder.decodeObject(of: NSData.self, forKey: "groupId") as Data?) ?? Data()
        var members = (coder.decodeObject(forKey: "groupMembers") as? [SignalServiceAddress]) ?? []
        let schema = (coder.decodeObject(of: NSNumber.self, forKey: "groupModelSchemaVersion"))?.uintValue ?? 0
        self.groupName = coder.decodeObject(of: NSString.self, forKey: "groupName") as String?
        self.legacyAvatarData = coder.decodeObject(of: NSData.self, forKey: "legacyAvatarData") as Data?

        // schemaVersion < 1: groupMemberIds (phone numbers) -> addresses.
        if schema < 1, members.isEmpty,
           let memberE164s = coder.decodeObject(forKey: "groupMemberIds") as? [String] {
            members = memberE164s.map { SignalServiceAddress.legacyAddress(serviceIdString: nil, phoneNumber: $0) }
        }
        self.groupMembers = members

        // schemaVersion < 2: legacy groupAvatarData key.
        if schema < 2 {
            self.legacyAvatarData = coder.decodeObject(of: NSData.self, forKey: "groupAvatarData") as Data?
        }
        self.groupModelSchemaVersion = tsGroupModelSchemaVersion
        super.init()
    }

    open func encode(with coder: NSCoder) {
        if let addedByAddress { coder.encode(addedByAddress, forKey: "addedByAddress") }
        if let avatarHash { coder.encode(avatarHash, forKey: "avatarHash") }
        coder.encode(groupId, forKey: "groupId")
        // PASS 1: the !isKindOf(TSGroupModelV2) discriminator is dropped until V2 lands.
        coder.encode(groupMembers, forKey: "groupMembers")
        coder.encode(NSNumber(value: groupModelSchemaVersion), forKey: "groupModelSchemaVersion")
        if let groupName { coder.encode(groupName, forKey: "groupName") }
        if let legacyAvatarData { coder.encode(legacyAvatarData, forKey: "legacyAvatarData") }
    }

    // MARK: Equality

    open override var hash: Int {
        var result = 0
        result ^= addedByAddress?.hash ?? 0
        result ^= (avatarHash as NSString?)?.hash ?? 0
        result ^= (groupId as NSData).hash
        result ^= (groupMembers as NSArray).hash
        result ^= Int(truncatingIfNeeded: groupModelSchemaVersion)
        result ^= (groupName as NSString?)?.hash ?? 0
        result ^= (legacyAvatarData as NSData?)?.hash ?? 0
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TSGroupModel, type(of: other) == type(of: self) else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return objectsEqual(addedByAddress, other.addedByAddress)
            && objectsEqual(avatarHash as NSString?, other.avatarHash as NSString?)
            && objectsEqual(groupId as NSData, other.groupId as NSData)
            && objectsEqual(groupMembers as NSArray, other.groupMembers as NSArray)
            && groupModelSchemaVersion == other.groupModelSchemaVersion
            && objectsEqual(groupName as NSString?, other.groupName as NSString?)
            && objectsEqual(legacyAvatarData as NSData?, other.legacyAvatarData as NSData?)
    }

    // MARK: NSCopying

    open func copy(with zone: NSZone? = nil) -> Any {
        let result = TSGroupModel(groupId: groupId,
                                  name: groupName,
                                  avatarData: nil,
                                  members: groupMembers,
                                  addedByAddress: addedByAddress)
        result.avatarHash = avatarHash
        result.legacyAvatarData = legacyAvatarData
        result.groupModelSchemaVersion = groupModelSchemaVersion
        return result
    }
}
