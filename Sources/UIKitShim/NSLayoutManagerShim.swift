// NSLayoutManager — TextKit 1 layout object (UIKit flavor; the AppKit flavor
// lives in QuillAppKit, per the per-flavor convention documented in
// QuillFoundation/NSTextLayoutShared.swift: these classes traffic in
// flavor-specific NSTextStorage/NSTextContainer, so they cannot share one
// declaration).
//
// SignalUI drives the full TextKit 1 triumvirate (NSTextStorage →
// NSLayoutManager → NSTextContainer) for chat-bubble measurement
// (CVText/CVTextLabel), tap-to-character hit testing (UIKit+Text), spoiler
// rects (SpoilerableTextViewAnimator) and search-capsule drawing
// (CVCapsuleLabel).
//
// MODEL HONESTY: there is no glyph layout engine on Linux. This class stores
// the object graph faithfully (storage/container wiring, identity, ranges) and
// answers geometry questions from a uniform-advance line model built on the
// shim's existing font conventions (UIFont.lineHeight = 1.2 × pointSize; char
// advance = 0.6 × pointSize, matching quillEstimatedTextRect in UIKit.swift):
//   * "glyphs" are UTF-16 units of the text storage, 1:1 with characters;
//   * lines wrap at floor(containerWidth / charWidth) characters;
//   * usedRect / boundingRect / line fragments / glyph hit tests all derive
//     from that grid, so they are mutually consistent (a rect returned by
//     boundingRect(forGlyphRange:) contains the points that glyphIndex(for:)
//     maps into that range) but are NOT typographically accurate.
// drawGlyphs/drawBackground are inert (rasterization is deferred to a real
// paint backend, like String.draw in UIKit.swift).

#if !os(iOS)

import Foundation
import QuillFoundation
import QuillUIKit

public protocol NSLayoutManagerDelegate: AnyObject {}

open class NSLayoutManager: NSObject, @unchecked Sendable {

    public override init() { super.init() }

    public weak var delegate: NSLayoutManagerDelegate?

    /// Weak (Apple: unowned(unsafe)) back-reference; the storage owns its
    /// layout managers via addLayoutManager(_:). Settable directly, matching
    /// Apple — BodyRangesTextView assigns it without addLayoutManager.
    public weak var textStorage: NSTextStorage?

    public internal(set) var textContainers: [NSTextContainer] = []

    public func addTextContainer(_ container: NSTextContainer) {
        textContainers.append(container)
        container.layoutManager = self
    }

    public func removeTextContainer(at index: Int) {
        guard textContainers.indices.contains(index) else { return }
        let removed = textContainers.remove(at: index)
        if removed.layoutManager === self { removed.layoutManager = nil }
    }

    public var numberOfGlyphs: Int { textStorage?.length ?? 0 }

    // MARK: Glyph <-> character mapping (identity under the 1:1 model)

    public func glyphRange(for container: NSTextContainer) -> NSRange {
        _ = container
        return NSRange(location: 0, length: textStorage?.length ?? 0)
    }

    public func glyphRange(forCharacterRange charRange: NSRange, actualCharacterRange: NSRangePointer?) -> NSRange {
        let clamped = clampedRange(charRange)
        actualCharacterRange?.pointee = clamped
        return clamped
    }

    public func characterRange(forGlyphRange glyphRange: NSRange, actualGlyphRange: NSRangePointer?) -> NSRange {
        let clamped = clampedRange(glyphRange)
        actualGlyphRange?.pointee = clamped
        return clamped
    }

    public func characterIndexForGlyph(at glyphIndex: Int) -> Int {
        Swift.max(0, Swift.min(glyphIndex, textStorage?.length ?? glyphIndex))
    }

    public func isValidGlyphIndex(_ glyphIndex: Int) -> Bool {
        glyphIndex >= 0 && glyphIndex < (textStorage?.length ?? 0)
    }

    // MARK: Geometry (uniform-advance line model)

    public func usedRect(for container: NSTextContainer) -> CGRect {
        let grid = lineGrid(for: container)
        let width = grid.length == 0
            ? 0
            : CGFloat(Swift.min(grid.length, grid.charsPerLine)) * grid.charWidth
        return CGRect(x: 0, y: 0, width: width, height: CGFloat(grid.lineCount) * grid.lineHeight)
    }

    public func boundingRect(forGlyphRange glyphRange: NSRange, in container: NSTextContainer) -> CGRect {
        let grid = lineGrid(for: container)
        let range = clampedRange(glyphRange)
        guard range.length > 0 else {
            // Zero-length range: a caret-style rect at the range's position.
            let (line, column) = grid.position(of: range.location)
            return CGRect(
                x: CGFloat(column) * grid.charWidth,
                y: CGFloat(line) * grid.lineHeight,
                width: 0,
                height: grid.lineHeight
            )
        }
        var union: CGRect?
        enumerateLineRects(of: range, in: grid) { rect in
            union = union?.union(rect) ?? rect
            return true
        }
        return union ?? .zero
    }

    public func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> CGRect {
        // Fragment rect == fragment used rect in the uniform model (no
        // trailing-whitespace/indent distinction).
        lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange)
    }

    public func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> CGRect {
        let grid = lineGrid(for: textContainers.first)
        let (line, _) = grid.position(of: Swift.max(0, Swift.min(glyphIndex, Swift.max(grid.length - 1, 0))))
        let lineRange = grid.glyphRange(ofLine: line)
        effectiveGlyphRange?.pointee = lineRange
        return CGRect(
            x: 0,
            y: CGFloat(line) * grid.lineHeight,
            width: CGFloat(lineRange.length) * grid.charWidth,
            height: grid.lineHeight
        )
    }

    public func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> CGRect {
        _ = flag // No layout pass exists to skip.
        return lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange)
    }

    public func glyphIndex(for point: CGPoint, in container: NSTextContainer) -> Int {
        let grid = lineGrid(for: container)
        guard grid.length > 0 else { return 0 }
        let line = Swift.max(0, Swift.min(Int(point.y / grid.lineHeight), grid.lineCount - 1))
        let column = Swift.max(0, Swift.min(Int(point.x / grid.charWidth), grid.charsPerLine - 1))
        return Swift.min(line * grid.charsPerLine + column, grid.length - 1)
    }

    public func enumerateLineFragments(
        forGlyphRange glyphRange: NSRange,
        using block: (CGRect, CGRect, NSTextContainer, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        let container = textContainers.first ?? NSTextContainer()
        let grid = lineGrid(for: container)
        let range = clampedRange(glyphRange)
        guard range.length > 0 else { return }
        let firstLine = grid.position(of: range.location).line
        let lastLine = grid.position(of: range.location + range.length - 1).line
        var stop = ObjCBool(false)
        for line in firstLine...lastLine {
            let lineRange = grid.glyphRange(ofLine: line)
            let usedRect = CGRect(
                x: 0,
                y: CGFloat(line) * grid.lineHeight,
                width: CGFloat(lineRange.length) * grid.charWidth,
                height: grid.lineHeight
            )
            // Fragment rect spans the container's full wrap width when known.
            var fragmentRect = usedRect
            if container.size.width > 0, container.size.width.isFinite {
                fragmentRect.size.width = container.size.width
            }
            withUnsafeMutablePointer(to: &stop) { block(fragmentRect, usedRect, container, lineRange, $0) }
            if stop.boolValue { return }
        }
    }

    public func enumerateEnclosingRects(
        forGlyphRange glyphRange: NSRange,
        withinSelectedGlyphRange selGlyphRange: NSRange,
        in textContainer: NSTextContainer,
        using block: (CGRect, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        _ = selGlyphRange // Selection-merging is a rendering nicety; not modeled.
        let grid = lineGrid(for: textContainer)
        var stop = ObjCBool(false)
        enumerateLineRects(of: clampedRange(glyphRange), in: grid) { rect in
            withUnsafeMutablePointer(to: &stop) { block(rect, $0) }
            return !stop.boolValue
        }
    }

    // MARK: Editing + drawing (inert)

    /// Re-layout notification from a storage edit. There is no layout to
    /// invalidate on Linux; geometry is recomputed from the storage on every
    /// query, so edits are always "seen". Kept for API shape (Apple's
    /// NSTextStorageObserving hook; AttachmentTextToolbar calls it directly).
    public func processEditing(
        for textStorage: NSTextStorage,
        edited editMask: NSTextStorage.EditActions,
        range newCharRange: NSRange,
        changeInLength delta: Int,
        invalidatedRange invalidatedCharRange: NSRange
    ) {
        _ = (textStorage, editMask, newCharRange, delta, invalidatedCharRange)
    }

    open func ensureLayout(for textContainer: NSTextContainer) {
        _ = textContainer
    }

    /// Inert: glyph rasterization is deferred to a real paint backend (same
    /// status as String.draw in UIKit.swift).
    public func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        _ = (glyphsToShow, origin)
    }

    public func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        _ = (glyphsToShow, origin)
    }

    // MARK: - Uniform-advance grid

    private struct LineGrid {
        let length: Int
        let charWidth: CGFloat
        let lineHeight: CGFloat
        let charsPerLine: Int
        let lineCount: Int

        func position(of glyphIndex: Int) -> (line: Int, column: Int) {
            guard charsPerLine > 0 else { return (0, 0) }
            let clamped = Swift.max(0, glyphIndex)
            let line = Swift.min(clamped / charsPerLine, lineCount - 1)
            // When the line was clamped (caret past the end, or glyphs beyond
            // a maximumNumberOfLines truncation), let the column run to the
            // wrap width instead of wrapping around to 0.
            let column = Swift.min(clamped - line * charsPerLine, charsPerLine)
            return (line, column)
        }

        func glyphRange(ofLine line: Int) -> NSRange {
            let start = Swift.min(line * charsPerLine, length)
            let isLastModeledLine = line == lineCount - 1
            // The last modeled line absorbs any glyphs truncated away by
            // maximumNumberOfLines, so ranges still tile the whole storage.
            let end = isLastModeledLine ? length : Swift.min(start + charsPerLine, length)
            return NSRange(location: start, length: Swift.max(0, end - start))
        }
    }

    private func lineGrid(for container: NSTextContainer?) -> LineGrid {
        // Default 17pt mirrors UITextView.sizeThatFits's fallback in UIKit.swift.
        let pointSize: CGFloat
        if let storage = textStorage, storage.length > 0,
           let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
            pointSize = font.pointSize
        } else {
            pointSize = 17
        }
        let charWidth = pointSize * 0.6
        let lineHeight = pointSize * 1.2
        let length = textStorage?.length ?? 0
        let charsPerLine: Int
        if let width = container?.size.width, width > 0, width.isFinite {
            charsPerLine = Swift.max(1, Int(width / charWidth))
        } else {
            charsPerLine = Swift.max(1, length)
        }
        var lineCount = Swift.max(1, Int(ceil(Double(length) / Double(charsPerLine))))
        if let maxLines = container?.maximumNumberOfLines, maxLines > 0 {
            lineCount = Swift.min(lineCount, maxLines)
        }
        return LineGrid(
            length: length,
            charWidth: charWidth,
            lineHeight: lineHeight,
            charsPerLine: charsPerLine,
            lineCount: lineCount
        )
    }

    /// Walks the per-line sub-rects of `range` (one rect per modeled line,
    /// matching Apple's enclosing-rect semantics). `body` returns false to stop.
    private func enumerateLineRects(of range: NSRange, in grid: LineGrid, body: (CGRect) -> Bool) {
        guard range.length > 0, grid.length > 0 else { return }
        let (firstLine, _) = grid.position(of: range.location)
        let (lastLine, _) = grid.position(of: range.location + range.length - 1)
        for line in firstLine...lastLine {
            let lineRange = grid.glyphRange(ofLine: line)
            let intersection = NSIntersectionRange(lineRange, range)
            guard intersection.length > 0 else { continue }
            let startColumn = intersection.location - lineRange.location
            let rect = CGRect(
                x: CGFloat(startColumn) * grid.charWidth,
                y: CGFloat(line) * grid.lineHeight,
                width: CGFloat(intersection.length) * grid.charWidth,
                height: grid.lineHeight
            )
            if !body(rect) { return }
        }
    }

    private func clampedRange(_ range: NSRange) -> NSRange {
        let length = textStorage?.length ?? 0
        guard range.location != NSNotFound else { return NSRange(location: 0, length: 0) }
        // Clamp without computing location+length, which can overflow Int for
        // sentinel-sized inputs (same hardening as the QuillAppKit flavor).
        let location = Swift.max(0, Swift.min(range.location, length))
        let count = Swift.max(0, Swift.min(range.length, length - location))
        return NSRange(location: location, length: count)
    }
}

#endif // !os(iOS)
