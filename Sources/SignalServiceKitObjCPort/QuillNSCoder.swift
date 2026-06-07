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

    // swift-corelibs NSCoder has the `UnsafePointer<UInt8>?` overload of
    // encodeBytes but not the raw-pointer one. NSSecureCoding encoders write
    // `data.withUnsafeBytes { coder.encodeBytes($0.baseAddress, ...) }`, and
    // `$0.baseAddress` is an `UnsafeRawPointer?` -- so the bare-corelibs call
    // fails with "cannot convert UnsafeRawPointer? to UnsafePointer<UInt8>?".
    // Forward the raw form to the UInt8 overload it does have. (ECKeyPair.encode.)
    func encodeBytes(_ bytes: UnsafeRawPointer?, length: Int, forKey key: String) {
        encodeBytes(bytes?.assumingMemoryBound(to: UInt8.self), length: length, forKey: key)
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
}
