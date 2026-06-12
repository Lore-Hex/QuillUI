//
// QuillUserDefaultsKVC -- Linux shadow for SignalServiceKit (Track B).
//
// On Apple, `UserDefaults.standard.setValue(_:forKey:)` is inherited NSObject
// Key-Value Coding. swift-corelibs-foundation's UserDefaults exposes only the
// canonical `set(_ value: Any?, forKey: String)` and provides no KVC layer
// (there is no Objective-C runtime under QuillOS). SSK calls it once, in
// AppSetup.configureUnsatisfiableConstraintLogging().
//
// QuillFoundation's NSObject extension owns the Apple-named KVC entry points
// (value(forKey:)/setValue(_:forKey:)/…) and forwards them through the
// QuillKeyValueCoding protocol — so UserDefaults adopts the protocol here
// rather than re-declaring setValue (a same-signature extension method can
// be neither overridden nor shadowed across modules). For defaults this is
// exactly equivalent to the canonical accessors.
//
import Foundation
#if os(Linux)
import UIKit // re-exports QuillFoundation (QuillKeyValueCoding)

extension UserDefaults: QuillKeyValueCoding {
    public func quillSetValue(_ value: Any?, forKey key: String) {
        set(value, forKey: key)
    }

    public func quillValue(forKey key: String) -> Any? {
        object(forKey: key)
    }
}
#endif
