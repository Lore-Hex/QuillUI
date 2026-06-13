import Foundation
// Plain import: re-exporting all of corelibs CoreFoundation leaks its stub
// CFString/CFArray classes into every `import Cocoa` scope (see the QuartzCore
// shim note). Only the CF names CoreText's API surface needs are re-exported.
import CoreFoundation
@_exported import QuillFoundation

public typealias CFIndex = CoreFoundation.CFIndex
public typealias CFRange = CoreFoundation.CFRange
public typealias CFError = NSError

public final class CTFramesetter {}
public final class CTFrame {}
public typealias CTFont = RSFont

public let kCTFontAttributeName = "NSFont"
public let kCTForegroundColorAttributeName = "CTForegroundColor"
public let kCTForegroundColorFromContextAttributeName = "CTForegroundColorFromContext"

public enum CTFontManagerScope: UInt32, Sendable {
    case none = 0
    case process = 1
    case user = 2
    case session = 3
}

@discardableResult
public func CTFontManagerRegisterFontsForURL(
    _ fontURL: URL,
    _ scope: CTFontManagerScope,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> Bool {
    _ = (fontURL, scope)
    error?.pointee = nil
    return true
}
public final class CTLine {
    fileprivate let length: Int

    fileprivate init(length: Int = 0) {
        self.length = length
    }
}

public final class CTRun {
    fileprivate let range: CFRange

    fileprivate init(range: CFRange = CFRange(location: 0, length: 0)) {
        self.range = range
    }
}

public final class CTTypesetter {
    fileprivate let attributedString: NSAttributedString

    fileprivate init(_ attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }
}

public enum CTLineTruncationType: UInt32, Sendable {
    case start = 0
    case end = 1
    case middle = 2
}

public func CTFramesetterCreateWithAttributedString(_ attributedString: NSAttributedString) -> CTFramesetter {
    _ = attributedString
    return CTFramesetter()
}

public func CTFramesetterSuggestFrameSizeWithConstraints(
    _ framesetter: CTFramesetter,
    _ stringRange: CFRange,
    _ frameAttributes: Any?,
    _ constraints: CGSize,
    _ fitRange: UnsafeMutablePointer<CFRange>?
) -> CGSize {
    _ = (framesetter, stringRange, frameAttributes)
    fitRange?.pointee = CFRange(location: 0, length: 0)
    return constraints
}

public func CTLineCreateWithAttributedString(_ attributedString: NSAttributedString) -> CTLine {
    CTLine(length: attributedString.length)
}

public func CTLineCreateTruncatedLine(_ line: CTLine, _ width: Double, _ truncationType: CTLineTruncationType, _ truncationToken: CTLine?) -> CTLine? {
    _ = (width, truncationType, truncationToken)
    return line
}

public func CTLineGetGlyphCount(_ line: CTLine) -> Int {
    _ = line
    return 0
}

public func CTFontGetAscent(_ font: CTFont) -> CGFloat {
    font.ascender
}

public func CTFontGetDescent(_ font: CTFont) -> CGFloat {
    -font.descender
}

public func CTFontGetLeading(_ font: CTFont) -> CGFloat {
    max(0, font.lineHeight - font.ascender + font.descender)
}

public func CTTypesetterCreateWithAttributedString(_ attributedString: NSAttributedString) -> CTTypesetter? {
    CTTypesetter(attributedString)
}

public func CTTypesetterSuggestLineBreak(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double) -> CFIndex {
    let remaining = max(0, typesetter.attributedString.length - startIndex)
    guard width.isFinite, width > 0 else { return remaining }
    return min(remaining, max(1, Int(width / 7)))
}

public func CTTypesetterCreateLineWithOffset(_ typesetter: CTTypesetter, _ stringRange: CFRange, _ offset: Double) -> CTLine {
    _ = (typesetter, offset)
    return CTLine(length: max(0, stringRange.length))
}

public func CTLineGetStringRange(_ line: CTLine) -> CFRange {
    CFRange(location: 0, length: line.length)
}

public func CTLineGetTypographicBounds(
    _ line: CTLine,
    _ ascent: UnsafeMutablePointer<CGFloat>?,
    _ descent: UnsafeMutablePointer<CGFloat>?,
    _ leading: UnsafeMutablePointer<CGFloat>?
) -> Double {
    ascent?.pointee = 10
    descent?.pointee = 3
    leading?.pointee = 0
    return Double(line.length) * 7
}

public func CTLineGetTrailingWhitespaceWidth(_ line: CTLine) -> Double {
    _ = line
    return 0
}

public func CTLineGetStringIndexForPosition(_ line: CTLine, _ position: CGPoint) -> CFIndex {
    guard line.length > 0 else { return 0 }
    return min(max(0, Int(position.x / 7)), line.length)
}

public func CTLineGetOffsetForStringIndex(
    _ line: CTLine,
    _ charIndex: CFIndex,
    _ secondaryOffset: UnsafeMutablePointer<CGFloat>?
) -> CGFloat {
    secondaryOffset?.pointee = 0
    return CGFloat(min(max(0, charIndex), line.length)) * 7
}

public func CTLineGetPenOffsetForFlush(_ line: CTLine, _ flushFactor: CGFloat, _ flushWidth: Double) -> Double {
    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    return max(0, flushWidth - lineWidth) * Double(flushFactor)
}

public func CTLineGetGlyphRuns(_ line: CTLine) -> NSArray {
    guard line.length > 0 else { return NSArray() }
    return NSArray(object: CTRun(range: CFRange(location: 0, length: line.length)))
}

public func CTLineDraw(_ line: CTLine, _ context: CGContext) {
    _ = (line, context)
}

public func CTRunDraw(_ run: CTRun, _ context: CGContext, _ range: CFRange) {
    _ = (run, context, range)
}

public struct CTRunStatus: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let rightToLeft = CTRunStatus(rawValue: 1 << 0)
    public static let nonMonotonic = CTRunStatus(rawValue: 1 << 1)
    public static let hasNonIdentityMatrix = CTRunStatus(rawValue: 1 << 2)
}

public func CTRunGetGlyphCount(_ run: CTRun) -> Int {
    run.range.length
}

public func CTRunGetStringRange(_ run: CTRun) -> CFRange {
    run.range
}

public func CTRunGetStatus(_ run: CTRun) -> CTRunStatus {
    _ = run
    return []
}

public func CTRunGetAttributes(_ run: CTRun) -> NSDictionary {
    _ = run
    return NSDictionary()
}
