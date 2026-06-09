//
// QuillUserDefaultsKVC -- Linux shadow for SignalServiceKit (Track B).
//
// On Apple, `UserDefaults.standard.setValue(_:forKey:)` is inherited NSObject
// Key-Value Coding. swift-corelibs-foundation's UserDefaults exposes only the
// canonical `set(_ value: Any?, forKey: String)` and provides no KVC layer
// (there is no Objective-C runtime under QuillOS), so the KVC `setValue` member
// is missing. SSK calls it once, in AppSetup.configureUnsatisfiableConstraintLogging().
// For a scalar defaults write this is exactly equivalent to `set(_:forKey:)`.
//
import Foundation

#if os(Linux)
public extension UserDefaults {
    /// Apple KVC `setValue(_:forKey:)` shim -- forwards to corelibs `set(_:forKey:)`.
    func setValue(_ value: Any?, forKey key: String) {
        set(value, forKey: key)
    }
}
#endif
