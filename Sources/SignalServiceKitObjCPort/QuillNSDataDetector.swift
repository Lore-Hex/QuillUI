//
// NSDataDetector — Linux placeholder for SignalServiceKit (Track B).
//
// Foundation's data detection (links, phone numbers, addresses, dates) ships in
// Apple's Foundation but NOT in swift-corelibs Foundation, so `NSDataDetector`
// is "cannot find type" on Linux. SignalServiceKit's link-preview and body-range
// machinery (LinkPreviewHelper, TextCheckingDataItem, HydratedMessageBody,
// LinkValidator) construct a detector and call `matches(in:options:range:)` /
// `enumerateMatches(in:options:range:using:)`, then read each match's
// `resultType` / `range` / `url` (all on swift-corelibs `NSTextCheckingResult`).
//
// This is a same-module placeholder: detection yields NO matches on Linux, so
// link previews are simply never auto-detected and callers degrade gracefully
// (they already guard the optional detector and empty result arrays). A real
// detector — or a regex-based URL fallback — is a later, separately-scoped
// milestone; this only unblocks compilation. HONEST STATUS: inert (no detection).
//
import Foundation

public class NSDataDetector: NSObject {
    /// Mirrors `NSDataDetector(types:)` where `types` is a bitmask of
    /// `NSTextCheckingResult.CheckingType` raw values (a `UInt64`). The bitmask
    /// is accepted and ignored — no detection is performed on Linux.
    public init(types checkingTypes: UInt64) throws {
        super.init()
    }

    /// Always returns no matches on Linux (data detection unavailable).
    public func matches(
        in string: String,
        options: NSRegularExpression.MatchingOptions = [],
        range: NSRange
    ) -> [NSTextCheckingResult] {
        []
    }

    /// No-op on Linux: the enumeration block is never invoked because no
    /// matches are produced.
    public func enumerateMatches(
        in string: String,
        options: NSRegularExpression.MatchingOptions = [],
        range: NSRange,
        using block: (NSTextCheckingResult?, NSRegularExpression.MatchingFlags, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
    }
}
