//
// NSDataDetector -- Linux URL detector for SignalServiceKit (Track B).
//
// Foundation's data detection (links, phone numbers, addresses, dates) ships in
// Apple's Foundation but NOT in swift-corelibs Foundation, so `NSDataDetector`
// is "cannot find type" on Linux. SignalServiceKit's link-preview and body-range
// machinery (LinkPreviewHelper, TextCheckingDataItem, HydratedMessageBody,
// LinkValidator) construct a detector and call `matches(in:options:range:)` /
// `enumerateMatches(in:options:range:using:)`, then read each match's
// `resultType` / `range` / `url` (all on swift-corelibs `NSTextCheckingResult`).
//
// This same-module shim implements the highest-value subset: URL-like links and
// email addresses. Phone/address/date/transit data detection remains deferred.
//
import Foundation

protocol QuillTextCheckingURLProviding {
    var quillDetectedURL: URL? { get }
}

private final class QuillDataDetectorCheckingResult: NSTextCheckingResult, QuillTextCheckingURLProviding {
    private static let linkCheckingType = NSTextCheckingResult.CheckingType(rawValue: UInt64(1) << 5)

    let detectedRange: NSRange
    let quillDetectedURL: URL?

    init(range: NSRange, url: URL?) {
        self.detectedRange = range
        self.quillDetectedURL = url
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var resultType: NSTextCheckingResult.CheckingType {
        Self.linkCheckingType
    }

    override var range: NSRange {
        detectedRange
    }

    override var numberOfRanges: Int {
        1
    }

    override func range(at idx: Int) -> NSRange {
        idx == 0 ? detectedRange : NSRange(location: NSNotFound, length: 0)
    }
}

public class NSDataDetector: NSObject {
    private static let linkCheckingType = NSTextCheckingResult.CheckingType(rawValue: UInt64(1) << 5)

    private let checkingTypes: NSTextCheckingResult.CheckingType

    private static let urlExpression = try! NSRegularExpression(
        pattern: #"(?:https?://|mailto:)[^\s<>"'`]+"#,
        options: [.caseInsensitive]
    )
    private static let emailExpression = try! NSRegularExpression(
        pattern: #"\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
        options: [.caseInsensitive]
    )

    /// Mirrors `NSDataDetector(types:)` where `types` is a bitmask of
    /// `NSTextCheckingResult.CheckingType` raw values.
    public init(types checkingTypes: UInt64) throws {
        self.checkingTypes = NSTextCheckingResult.CheckingType(rawValue: checkingTypes)
        super.init()
    }

    public func matches(
        in string: String,
        options: NSRegularExpression.MatchingOptions = [],
        range: NSRange
    ) -> [NSTextCheckingResult] {
        guard checkingTypes.contains(Self.linkCheckingType) else {
            return []
        }

        let searchRange = clampedRange(range, in: string)
        guard searchRange.length > 0 else {
            return []
        }

        var results = [QuillDataDetectorCheckingResult]()
        Self.urlExpression.enumerateMatches(in: string, options: options, range: searchRange) { match, _, _ in
            guard let match else { return }
            if let result = Self.result(forRawURLMatch: match.range, in: string) {
                results.append(result)
            }
        }

        Self.emailExpression.enumerateMatches(in: string, options: options, range: searchRange) { match, _, _ in
            guard let match else { return }
            if results.contains(where: { NSIntersectionRange($0.detectedRange, match.range).length > 0 }) {
                return
            }
            if let result = Self.result(forEmailMatch: match.range, in: string) {
                results.append(result)
            }
        }

        return results.sorted { lhs, rhs in
            lhs.range.location < rhs.range.location
        }
    }

    public func enumerateMatches(
        in string: String,
        options: NSRegularExpression.MatchingOptions = [],
        range: NSRange,
        using block: (NSTextCheckingResult?, NSRegularExpression.MatchingFlags, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        var stop = ObjCBool(false)
        for match in matches(in: string, options: options, range: range) {
            block(match, [], &stop)
            if stop.boolValue {
                break
            }
        }
    }

    private func clampedRange(_ range: NSRange, in string: String) -> NSRange {
        let fullLength = (string as NSString).length
        guard range.location != NSNotFound, range.location < fullLength else {
            return NSRange(location: 0, length: 0)
        }
        let end = min(range.location + range.length, fullLength)
        return NSRange(location: range.location, length: max(0, end - range.location))
    }

    private static func result(forRawURLMatch range: NSRange, in string: String) -> QuillDataDetectorCheckingResult? {
        let trimmedRange = trimmingTerminalPunctuation(from: range, in: string)
        guard trimmedRange.length > 0 else {
            return nil
        }
        let snippet = (string as NSString).substring(with: trimmedRange)
        guard let url = URL(string: snippet) else {
            return nil
        }
        return QuillDataDetectorCheckingResult(range: trimmedRange, url: url)
    }

    private static func result(forEmailMatch range: NSRange, in string: String) -> QuillDataDetectorCheckingResult? {
        let snippet = (string as NSString).substring(with: range)
        guard let url = URL(string: "mailto:\(snippet)") else {
            return nil
        }
        return QuillDataDetectorCheckingResult(range: range, url: url)
    }

    private static func trimmingTerminalPunctuation(from range: NSRange, in string: String) -> NSRange {
        let nsString = string as NSString
        var length = range.length
        while length > 0 {
            let character = nsString.substring(with: NSRange(location: range.location + length - 1, length: 1))
            if ".,;:!?)]}".contains(character) {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
    }
}
