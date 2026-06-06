//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// swift-corelibs-foundation declares `DateComponentsFormatter` but marks it
// `@available(*, unavailable, message: "Not supported in swift-corelibs-
// foundation")`, so SSK's duration formatting (OWSFormat / String+SSK) fails to
// compile. This same-module type SHADOWS the Foundation one (a declaration in
// the SSK module wins over the imported, unavailable type) and provides a
// working positional/colon duration formatter -- enough for call-duration and
// timer strings. UnitsStyle text rendering ("3 minutes") is deferred to the
// positional form.
//
import Foundation

public final class DateComponentsFormatter {

    public enum UnitsStyle: Int, Sendable {
        case positional, abbreviated, short, full, spellOut, brief
    }

    public struct ZeroFormattingBehavior: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let dropLeading = ZeroFormattingBehavior(rawValue: 1 << 1)
        public static let dropMiddle = ZeroFormattingBehavior(rawValue: 1 << 2)
        public static let dropTrailing = ZeroFormattingBehavior(rawValue: 1 << 3)
        public static let dropAll: ZeroFormattingBehavior = [.dropLeading, .dropMiddle, .dropTrailing]
        public static let pad = ZeroFormattingBehavior(rawValue: 1 << 16)
    }

    /// Mirrors `Formatter.Context` (inherited from NSFormatter on Apple). SSK sets
    /// `formatter.formattingContext = .standalone`; it doesn't affect the inert
    /// Linux formatting, but the property + cases must exist.
    public enum Context: Int, Sendable {
        case unknown = 0
        case dynamic = 1
        case standalone = 2
        case listItem = 3
        case beginningOfSentence = 4
        case middleOfSentence = 5
    }

    public var formattingContext: Context = .unknown
    public var unitsStyle: UnitsStyle = .positional
    public var allowedUnits: NSCalendar.Unit = []
    public var zeroFormattingBehavior: ZeroFormattingBehavior = []
    public var maximumUnitCount: Int = 0

    public init() {}

    /// Colon-separated duration (e.g. "1:23:45" / "4:05"). Honors whether the
    /// hour unit is allowed; otherwise minutes:seconds.
    public func string(from ti: TimeInterval) -> String? {
        guard ti.isFinite, ti >= 0 else { return nil }
        let total = Int(ti.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if allowedUnits.contains(.hour) || hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    public func string(from components: DateComponents) -> String? {
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        let seconds = components.second ?? 0
        let interval = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        return string(from: interval)
    }

    public static func localizedString(from components: DateComponents, unitsStyle: UnitsStyle) -> String? {
        DateComponentsFormatter().string(from: components)
    }
}
