//
// NSTextCheckingResult data-detector accessors -- Linux shim (Track B).
//
// swift-corelibs Foundation's NSTextCheckingResult only implements the
// regular-expression surface (resultType / range / regularExpression /
// numberOfRanges). It does NOT provide the data-detector accessors that Apple's
// Foundation exposes (url / date / components), because corelibs has no data
// detection. SSK reads these while building tappable link/data items
// (HydratedMessageBody, TextCheckingDataItem). Those closures iterate the
// detector's matches; on Linux NSDataDetector returns [] (see
// QuillNSDataDetector.swift), so the accessors are never reached at runtime --
// they exist purely so the (dead-on-Linux) code type-checks. Returning nil is
// safe and honest: link previews / tappable data items are a display feature
// deferred on QuillOS. HONEST STATUS: inert.
//
#if os(Linux)
import Foundation

public extension NSTextCheckingResult {
    /// Detected URL of a link match. Always nil on Linux (no data detection).
    var url: URL? { nil }
    /// Detected date of a date match. Always nil on Linux (no data detection).
    var date: Date? { nil }
    /// Detected key/value components of a match. Always nil on Linux.
    var components: [NSTextCheckingKey: String]? { nil }
}
#endif
