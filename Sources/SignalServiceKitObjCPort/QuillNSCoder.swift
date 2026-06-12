//
// SignalServiceKit ObjC-extension port for QuillOS (Track B).
//
// Signal adds a typed NSCoder.decodeDictionary(withKeyClass:objectClass:forKey:)
// convenience (an NSCoder category that is excluded on Linux). GroupMembership's
// initWithCoder uses it for its three legacy maps. swift-corelibs NSCoder has no
// such member, so provide the generic Swift equivalent. The keyClass/objectClass
// are the NSSecureCoding allow-list; enforcing it is deferred (decode + cast).
//
import Foundation

extension NSCoder {
    func decodeDictionary<K: Hashable, V>(
        withKeyClass keyClass: AnyClass,
        objectClass: AnyClass,
        forKey key: String
    ) -> [K: V]? {
        _ = (keyClass, objectClass)
        return decodeObject(forKey: key) as? [K: V]
    }

    // swift-corelibs NSCoder lacks the legacy `encodeCInt(_:forKey:)` convenience
    // (a 32-bit-int writer). It does have `encode(_ value: Int32, forKey:)`, and
    // the matching decode side reads back with `decodeInt32(forKey:)`. Forward to
    // the Int32 overload so the encode/decode roundtrip stays symmetric. Sole
    // caller: OWSProfileManager userProfileWriter encode.
    func encodeCInt(_ value: Int32, forKey key: String) {
        encode(value, forKey: key)
    }

    // swift-corelibs NSCoder has the `UnsafePointer<UInt8>?` overload of
    // encodeBytes but not the raw-pointer one. NSSecureCoding encoders write
    // `data.withUnsafeBytes { coder.encodeBytes($0.baseAddress, ...) }`, and
    // `$0.baseAddress` is an `UnsafeRawPointer?` -- so the bare-corelibs call
    // fails with "cannot convert UnsafeRawPointer? to UnsafePointer<UInt8>?".
    // Forward the raw form to the UInt8 overload it does have. (ECKeyPair.encode.)
    // @_disfavoredOverload so the forwarded call below (a typed UnsafePointer<UInt8>?)
    // resolves to the swift-corelibs base encodeBytes, not back to this overload --
    // otherwise the typed<->raw pointer conversion makes the re-dispatch ambiguous.
    // External callers pass an UnsafeRawPointer?, which only this overload accepts.
    // Store the blob as an NSData under the key so `decodeBytes(forKey:returnedLength:)`
    // below can read it back. swift-corelibs has no `decodeBytes`, and its native
    // `encodeBytes(UInt8?,length:,forKey:)` uses an internal keyed-archive byte format
    // we cannot read; an NSData object round-trips faithfully. This is exercised at
    // runtime by ECKeyPair (the account/identity keypair) NSKeyedArchiver storage.
    @_disfavoredOverload
    func encodeBytes(_ bytes: UnsafeRawPointer?, length: Int, forKey key: String) {
        let data: NSData = bytes.map { NSData(bytes: $0, length: length) } ?? NSData()
        encode(data, forKey: key)
    }

    // swift-corelibs NSCoder has no `decodeBytes(forKey:returnedLength:)` at all.
    // The matching encodeBytes stores the blob as an NSData under the key, so
    // read it back. The sole callers (ECKeyPair.init?(coder:)) copy the bytes
    // into a Data immediately on return, so a freshly-allocated buffer satisfies
    // their usage of Apple's "valid for the decoder's lifetime" contract.
    //
    // The buffer is intentionally not freed here: Apple owns it for the decoder's
    // lifetime, and these keys are tiny (32 bytes) and decoded once at account
    // load. Revisit with a per-decoder store if decode volume ever grows. NOTE
    // this is compile-faithful; the encode/decode roundtrip is not yet exercised
    // at runtime (nothing runs on QuillOS yet).
    func decodeBytes(forKey key: String, returnedLength lengthp: UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>? {
        guard let nsdata = decodeObject(of: NSData.self, forKey: key) else {
            lengthp?.pointee = 0
            return nil
        }
        let data = nsdata as Data
        let count = data.count
        guard count > 0 else {
            lengthp?.pointee = 0
            return nil
        }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        data.copyBytes(to: buffer, count: count)
        lengthp?.pointee = count
        return UnsafePointer(buffer)
    }

    // swift-corelibs NSCoder has no decodeArrayOfObjects(ofClass:forKey:) (used by
    // ~9 NSSecureCoding decoders, e.g. OutgoingBlockedSyncMessage). Apple's is
    // generic -> [DecodedObjectType]?, so `ofClass: NSData.self` yields [NSData]?
    // and callers bridge `as [Data]?`. Decode the stored array and cast; the class
    // is the NSSecureCoding allow-list (enforcement deferred, as elsewhere).
    func decodeArrayOfObjects<DecodedObjectType>(
        ofClass cls: DecodedObjectType.Type,
        forKey key: String
    ) -> [DecodedObjectType]? where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        return decodeObject(forKey: key) as? [DecodedObjectType]
    }
}

// swift-corelibs NSKeyedUnarchiver has unarchivedObject(ofClass:from:) and
// unarchivedObject(ofClasses:from:), but NOT the typed collection conventers
// unarchivedArrayOfObjects(ofClass:from:) / unarchivedDictionary(ofKeyClass:
// objectClass:from:) (verified via 1-file swiftc). SDSDeserialization and
// KeyValueStore (the SDS storage layer) use both. Implement them over the
// allow-list multi-class unarchivedObject(ofClasses:from:) that does exist, then
// bridge-cast to the typed Swift collection. Same-module as SSK (linked via
// quill-signal-link-ports), so callers resolve them without an import.
extension NSKeyedUnarchiver {
    class func unarchivedArrayOfObjects<DecodedObjectType>(
        ofClass cls: DecodedObjectType.Type,
        from data: Data
    ) throws -> [DecodedObjectType]? where DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        let decoded = try unarchivedObject(ofClasses: [NSArray.self, cls], from: data)
        return decoded as? [DecodedObjectType]
    }

    class func unarchivedDictionary<DecodedKeyType, DecodedObjectType>(
        ofKeyClass keyCls: DecodedKeyType.Type,
        objectClass valueCls: DecodedObjectType.Type,
        from data: Data
    ) throws -> [DecodedKeyType: DecodedObjectType]?
    where DecodedKeyType: NSObject, DecodedKeyType: NSCoding,
          DecodedObjectType: NSObject, DecodedObjectType: NSCoding {
        let decoded = try unarchivedObject(ofClasses: [NSDictionary.self, keyCls, valueCls], from: data)
        return decoded as? [DecodedKeyType: DecodedObjectType]
    }
}
