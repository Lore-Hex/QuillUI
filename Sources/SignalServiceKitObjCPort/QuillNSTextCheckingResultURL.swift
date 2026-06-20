//
// NSTextCheckingResult data-detector accessors -- Linux shim (Track B).
//
// swift-corelibs Foundation's NSTextCheckingResult only implements the
// regular-expression surface (resultType / range / regularExpression /
// numberOfRanges). It does NOT provide the data-detector accessors that Apple's
// Foundation exposes (url / date / components), because corelibs has no data
// detection. Quill's NSDataDetector shim provides URL-backed link matches; the
// remaining data types still return nil.
//
#if os(Linux)
import Foundation

public extension NSTextCheckingResult {
    /// Detected URL of a link match.
    var url: URL? { (self as? QuillTextCheckingURLProviding)?.quillDetectedURL }
    /// Detected date of a date match. Always nil on Linux (no data detection).
    var date: Date? { nil }
    /// Detected key/value components of a match. Always nil on Linux.
    var components: [NSTextCheckingKey: String]? { nil }
}
#endif
