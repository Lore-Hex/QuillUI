#if os(Linux)
import Foundation

// macOS Foundation APIs that are missing from swift-corelibs-foundation on
// Linux, cloned here so verbatim Apple-source compiles unchanged. QuillFoundation
// `@_exported import`s Foundation, so a target that links it (and whose source
// `import`s QuillFoundation) sees these alongside the real Foundation surface.
// Grows one gap at a time as vendored upstream code surfaces them.

public extension NSString {
    /// Clone of Apple's `NSString.localizedStringWithFormat(_:_:)`, absent from
    /// swift-corelibs-foundation. Formats the arguments into `format` (the
    /// Apple version is current-locale-aware; locale only affects numeric
    /// formatting, which the cases we hit so far don't use).
    static func localizedStringWithFormat(_ format: NSString, _ args: CVarArg...) -> NSString {
        NSString(string: String(format: format as String, arguments: args))
    }
}

public extension FileManager {
    /// Clone of Apple's app-group container API, absent from
    /// swift-corelibs-foundation. There are no app groups on Linux, so this
    /// returns nil — callers degrade gracefully (e.g. WireGuard's
    /// FileManager+Extension shared-folder / last-error URLs become nil).
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        nil
    }
}
#endif
