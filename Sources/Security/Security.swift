import Foundation
@_exported import QuillKit

public final class SecCertificate: @unchecked Sendable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

public final class SecTrust: @unchecked Sendable {
    public init() {}
}

public final class SecRandom: @unchecked Sendable {
    public init() {}
}

public typealias OSStatus = Int32
public typealias SecRandomRef = SecRandom
public let errSecSuccess: OSStatus = 0
public let errSecUnimplemented: OSStatus = -4
public let errSecParam: OSStatus = -50
public let errSecAllocate: OSStatus = -108
public let errSecNotAvailable: OSStatus = -25291
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300

public let kSecClass: CFString = "class" as CFString
public let kSecClassGenericPassword: CFString = "genp" as CFString
public let kSecClassInternetPassword: CFString = "inet" as CFString
public let kSecClassKey: CFString = "keys" as CFString
public let kSecClassCertificate: CFString = "cert" as CFString
public let kSecClassIdentity: CFString = "idnt" as CFString

public let kSecAttrService: CFString = "svce" as CFString
public let kSecAttrAccount: CFString = "acct" as CFString
public let kSecAttrAccessGroup: CFString = "agrp" as CFString
public let kSecAttrSynchronizable: CFString = "sync" as CFString
public let kSecAttrLabel: CFString = "labl" as CFString
public let kSecAttrGeneric: CFString = "gena" as CFString
public let kSecAttrAccessible: CFString = "pdmn" as CFString
public let kSecAttrAccessibleWhenUnlocked: CFString = "ak" as CFString
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck" as CFString
public let kSecAttrAccessibleAlways: CFString = "dk" as CFString
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: CFString = "akpu" as CFString
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFString = "aku" as CFString
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFString = "cku" as CFString
public let kSecAttrAccessibleAlwaysThisDeviceOnly: CFString = "dku" as CFString

public let kSecValueData: CFString = "v_Data" as CFString
public let kSecValueRef: CFString = "v_Ref" as CFString
public let kSecValuePersistentRef: CFString = "v_PersistentRef" as CFString
public let kSecReturnData: CFString = "r_Data" as CFString
public let kSecReturnAttributes: CFString = "r_Attributes" as CFString
public let kSecReturnRef: CFString = "r_Ref" as CFString
public let kSecReturnPersistentRef: CFString = "r_PersistentRef" as CFString
public let kSecMatchLimit: CFString = "m_Limit" as CFString
public let kSecMatchLimitOne: CFString = "m_LimitOne" as CFString
public let kSecMatchLimitAll: CFString = "m_LimitAll" as CFString

public let kSecRandomDefault: SecRandomRef? = nil

public func SecCertificateCreateWithData(_ allocator: CFAllocator?, _ data: CFData) -> SecCertificate? {
    SecCertificate(data: data)
}

@discardableResult
public func SecRandomCopyBytes(_ _: SecRandomRef?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> OSStatus {
    guard count >= 0 else {
        return errSecParam
    }
    guard count > 0 else {
        return errSecSuccess
    }

    var generator = SystemRandomNumberGenerator()
    let buffer = bytes.bindMemory(to: UInt8.self, capacity: count)
    for index in 0..<count {
        buffer[index] = UInt8.random(in: UInt8.min ... UInt8.max, using: &generator)
    }
    return errSecSuccess
}

public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    SecItemProcessStore.shared.add(secDictionary(attributes), result: result)
}

public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    SecItemProcessStore.shared.copyMatching(secDictionary(query), result: result)
}

public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    SecItemProcessStore.shared.update(secDictionary(query), updates: secDictionary(attributesToUpdate))
}

public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    SecItemProcessStore.shared.delete(secDictionary(query))
}

public func SecTrustSetAnchorCertificates(_ trust: SecTrust, _ anchorCertificates: CFArray) -> OSStatus {
    errSecSuccess
}

public func SecTrustSetAnchorCertificatesOnly(_ trust: SecTrust, _ anchorCertificatesOnly: Bool) {}

public func SecTrustEvaluateWithError(_ trust: SecTrust, _ error: UnsafeMutablePointer<CFError?>?) -> Bool {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "Security",
        operation: "trustEvaluation",
        severity: .info,
        message: "Trust evaluation is accepted by the compatibility shim; attach a native TLS trust backend before production use."
    )
    return true
}

private struct SecItemIdentity: Hashable, Comparable {
    var itemClass: String
    var service: String?
    var account: String?
    var accessGroup: String?
    var synchronizable: String?

    static func < (lhs: SecItemIdentity, rhs: SecItemIdentity) -> Bool {
        let lhsValues = lhs.sortValues
        let rhsValues = rhs.sortValues
        for index in lhsValues.indices {
            if lhsValues[index] == rhsValues[index] {
                continue
            }
            return lhsValues[index] < rhsValues[index]
        }
        return false
    }

    private var sortValues: [String] {
        [itemClass, service ?? "", account ?? "", accessGroup ?? "", synchronizable ?? ""]
    }
}

private struct SecItemRecord {
    var identity: SecItemIdentity
    var attributes: [String: Any]
    var valueData: Data?
    var valueRef: AnyObject?
    var persistentRef: Data
}

private final class SecItemProcessStore: @unchecked Sendable {
    static let shared = SecItemProcessStore()

    private let lock = NSLock()
    private var records: [SecItemIdentity: SecItemRecord] = [:]

    func add(_ attributes: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard let identity = makeIdentity(from: attributes) else {
            return errSecParam
        }

        let record = SecItemRecord(
            identity: identity,
            attributes: storedAttributes(from: attributes),
            valueData: dataValue(attributes[secKey(kSecValueData)]),
            valueRef: attributes[secKey(kSecValueRef)] as AnyObject?,
            persistentRef: makePersistentRef()
        )

        lock.lock()
        defer { lock.unlock() }

        guard records[identity] == nil else {
            return errSecDuplicateItem
        }

        records[identity] = record
        setResult(resultObject(for: record, query: attributes), result)
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let matches = matchingRecords(for: query)
        guard !matches.isEmpty else {
            result?.pointee = nil
            return errSecItemNotFound
        }

        if stringValue(query[secKey(kSecMatchLimit)]) == secString(kSecMatchLimitAll) {
            let objects = matches.compactMap { resultObject(for: $0, query: query) }
            setResult(objects as NSArray as CFTypeRef, result)
        } else {
            setResult(resultObject(for: matches[0], query: query), result)
        }

        return errSecSuccess
    }

    func update(_ query: [String: Any], updates: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let matchingIdentities = matchingRecords(for: query).map(\.identity)
        guard !matchingIdentities.isEmpty else {
            return errSecItemNotFound
        }

        var updatedRecords: [SecItemRecord] = []
        for identity in matchingIdentities {
            guard var record = records[identity] else {
                continue
            }

            apply(updates: updates, to: &record)
            guard let updatedIdentity = makeIdentity(from: record.attributes) else {
                return errSecParam
            }
            record.identity = updatedIdentity
            updatedRecords.append(record)
        }

        var proposedIdentities = Set<SecItemIdentity>()
        for record in updatedRecords {
            if proposedIdentities.contains(record.identity) {
                return errSecDuplicateItem
            }
            proposedIdentities.insert(record.identity)

            if records[record.identity] != nil && !matchingIdentities.contains(record.identity) {
                return errSecDuplicateItem
            }
        }

        for identity in matchingIdentities {
            records.removeValue(forKey: identity)
        }
        for record in updatedRecords {
            records[record.identity] = record
        }
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let matchingIdentities = matchingRecords(for: query).map(\.identity)
        guard !matchingIdentities.isEmpty else {
            return errSecItemNotFound
        }

        for identity in matchingIdentities {
            records.removeValue(forKey: identity)
        }
        return errSecSuccess
    }

    private func matchingRecords(for query: [String: Any]) -> [SecItemRecord] {
        records.values
            .filter { record in matches(record: record, query: query) }
            .sorted { $0.identity < $1.identity }
    }

    private func apply(updates: [String: Any], to record: inout SecItemRecord) {
        for (key, value) in updates where !controlKeys.contains(key) {
            if key == secKey(kSecValueData) {
                record.valueData = dataValue(value)
            } else if key == secKey(kSecValueRef) {
                record.valueRef = value as AnyObject?
            } else if key == secKey(kSecValuePersistentRef) {
                continue
            } else {
                record.attributes[key] = value
            }
        }
    }
}

private let controlKeys: Set<String> = [
    secKey(kSecReturnData),
    secKey(kSecReturnAttributes),
    secKey(kSecReturnRef),
    secKey(kSecReturnPersistentRef),
    secKey(kSecMatchLimit)
]

private let valueKeys: Set<String> = [
    secKey(kSecValueData),
    secKey(kSecValueRef),
    secKey(kSecValuePersistentRef)
]

private func makeIdentity(from attributes: [String: Any]) -> SecItemIdentity? {
    guard let itemClass = stringValue(attributes[secKey(kSecClass)]) else {
        return nil
    }

    return SecItemIdentity(
        itemClass: itemClass,
        service: stringValue(attributes[secKey(kSecAttrService)]),
        account: stringValue(attributes[secKey(kSecAttrAccount)]),
        accessGroup: stringValue(attributes[secKey(kSecAttrAccessGroup)]),
        synchronizable: stringValue(attributes[secKey(kSecAttrSynchronizable)])
    )
}

private func storedAttributes(from attributes: [String: Any]) -> [String: Any] {
    var stored: [String: Any] = [:]
    for (key, value) in attributes where !controlKeys.contains(key) && !valueKeys.contains(key) {
        stored[key] = value
    }
    return stored
}

private func matches(record: SecItemRecord, query: [String: Any]) -> Bool {
    for (key, queryValue) in query where !controlKeys.contains(key) {
        if key == secKey(kSecValueData) {
            guard dataValue(queryValue) == record.valueData else {
                return false
            }
            continue
        }

        if key == secKey(kSecValueRef) {
            guard referenceEquals(record.valueRef, queryValue) else {
                return false
            }
            continue
        }

        if key == secKey(kSecValuePersistentRef) {
            guard dataValue(queryValue) == record.persistentRef else {
                return false
            }
            continue
        }

        guard let storedValue = record.attributes[key], normalizedEquals(storedValue, queryValue) else {
            return false
        }
    }
    return true
}

private func resultObject(for record: SecItemRecord, query: [String: Any]) -> CFTypeRef? {
    let wantsAttributes = boolValue(query[secKey(kSecReturnAttributes)])
    let wantsData = boolValue(query[secKey(kSecReturnData)])
    let wantsRef = boolValue(query[secKey(kSecReturnRef)])
    let wantsPersistentRef = boolValue(query[secKey(kSecReturnPersistentRef)])

    if wantsAttributes {
        var attributes = record.attributes
        if wantsData, let data = record.valueData {
            attributes[secKey(kSecValueData)] = data as NSData
        }
        if wantsRef, let valueRef = record.valueRef {
            attributes[secKey(kSecValueRef)] = valueRef
        }
        if wantsPersistentRef {
            attributes[secKey(kSecValuePersistentRef)] = record.persistentRef as NSData
        }
        return attributes as NSDictionary as CFTypeRef
    }

    let valueRequestCount = [wantsData, wantsRef, wantsPersistentRef].filter { $0 }.count
    if valueRequestCount > 1 {
        var values: [String: Any] = [:]
        if wantsData, let data = record.valueData {
            values[secKey(kSecValueData)] = data as NSData
        }
        if wantsRef, let valueRef = record.valueRef {
            values[secKey(kSecValueRef)] = valueRef
        }
        if wantsPersistentRef {
            values[secKey(kSecValuePersistentRef)] = record.persistentRef as NSData
        }
        return values as NSDictionary as CFTypeRef
    }

    if wantsData {
        guard let data = record.valueData else {
            return nil
        }
        return data as NSData as CFTypeRef
    }

    if wantsRef {
        if let valueRef = record.valueRef {
            return valueRef as CFTypeRef
        }
        if let data = record.valueData {
            return data as NSData as CFTypeRef
        }
        return record.attributes as NSDictionary as CFTypeRef
    }

    if wantsPersistentRef {
        return record.persistentRef as NSData as CFTypeRef
    }

    return nil
}

private func makePersistentRef() -> Data {
    Data("quillui-security-persistent-ref:\(UUID().uuidString)".utf8)
}

private func setResult(_ object: CFTypeRef?, _ result: UnsafeMutablePointer<CFTypeRef?>?) {
    guard let result else {
        return
    }
    result.pointee = object
}

private func secDictionary(_ dictionary: CFDictionary) -> [String: Any] {
    var result: [String: Any] = [:]
    let source = dictionary as NSDictionary
    for (key, value) in source {
        result[secKeyName(key)] = value
    }
    return result
}

private func secKey(_ key: CFString) -> String {
    key as String
}

private func secKeyName(_ key: Any) -> String {
    if let key = key as? String {
        return key
    }
    if let key = key as? NSString {
        return key as String
    }
    return String(describing: key)
}

private func secString(_ key: CFString) -> String {
    key as String
}

private func stringValue(_ value: Any?) -> String? {
    if let value = value as? String {
        return value
    }
    if let value = value as? NSString {
        return value as String
    }
    if let value {
        return String(describing: value)
    }
    return nil
}

private func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? NSNumber {
        return value.boolValue
    }
    return false
}

private func dataValue(_ value: Any?) -> Data? {
    if let value = value as? Data {
        return value
    }
    if let value = value as? NSData {
        return value as Data
    }
    return nil
}

private func referenceEquals(_ stored: AnyObject?, _ query: Any) -> Bool {
    guard let stored else {
        return false
    }
    if let queryObject = query as AnyObject?, stored === queryObject {
        return true
    }
    return normalizedEquals(stored, query)
}

private func normalizedEquals(_ lhs: Any, _ rhs: Any) -> Bool {
    if let lhsData = dataValue(lhs), let rhsData = dataValue(rhs) {
        return lhsData == rhsData
    }
    if let lhsBool = lhs as? Bool, let rhsBool = rhs as? Bool {
        return lhsBool == rhsBool
    }
    if let lhsNumber = lhs as? NSNumber, let rhsNumber = rhs as? NSNumber {
        return lhsNumber == rhsNumber
    }
    return stringValue(lhs) == stringValue(rhs)
}
