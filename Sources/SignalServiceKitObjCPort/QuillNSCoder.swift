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
}
