import AppKit

public struct TextFieldSizeInfo: Sendable {
    public let size: NSSize
    public let numberOfLinesUsed: Int

    public init(size: NSSize, numberOfLinesUsed: Int) {
        self.size = size
        self.numberOfLinesUsed = numberOfLinesUsed
    }
}

@MainActor
public final class SingleLineTextFieldSizer {
    private static var cache: [String: NSSize] = [:]

    public static func size(for text: String, font: NSFont) -> NSSize {
        let key = "\(font.pointSize)|\(font.fontDescriptor.name)|\(font.fontDescriptor.symbolicTraits.rawValue)|\(text)"
        if let cached = cache[key] {
            return cached
        }

        let textField = NSTextField(labelWithString: text)
        textField.font = font
        var size = textField.fittingSize
        size.width = ceil(size.width)
        size.height = ceil(size.height)
        cache[key] = size
        return size
    }
}

@MainActor
public final class MultilineTextFieldSizer {
    private static var stringCache: [String: TextFieldSizeInfo] = [:]
    private static var attributedCache: [String: TextFieldSizeInfo] = [:]

    public static func size(for string: String, font: NSFont, numberOfLines: Int, width: Int) -> TextFieldSizeInfo {
        let cacheKey = "\(font.pointSize)|\(font.fontDescriptor.name)|\(font.fontDescriptor.symbolicTraits.rawValue)|\(numberOfLines)|\(width)|\(string)"
        if let cached = stringCache[cacheKey] {
            return cached
        }

        let info = measure(string: string, font: font, numberOfLines: numberOfLines, width: width)
        stringCache[cacheKey] = info
        return info
    }

    public static func size(for attributedString: NSAttributedString, numberOfLines: Int, width: Int) -> TextFieldSizeInfo {
        guard attributedString.length > 0 else {
            return TextFieldSizeInfo(size: .zero, numberOfLinesUsed: 0)
        }

        let font = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let cacheKey = "\(font.pointSize)|\(font.fontDescriptor.name)|\(font.fontDescriptor.symbolicTraits.rawValue)|\(numberOfLines)|\(width)|\(attributedString.string)"
        if let cached = attributedCache[cacheKey] {
            return cached
        }

        let info = measure(string: attributedString.string, font: font, numberOfLines: numberOfLines, width: width)
        attributedCache[cacheKey] = info
        return info
    }

    public static func emptyCache() {
        stringCache.removeAll()
        attributedCache.removeAll()
    }

    private static func measure(string: String, font: NSFont, numberOfLines: Int, width: Int) -> TextFieldSizeInfo {
        guard !string.isEmpty, width > 0 else {
            return TextFieldSizeInfo(size: .zero, numberOfLinesUsed: 0)
        }

        let textField = NSTextField(wrappingLabelWithString: string)
        textField.font = font
        textField.maximumNumberOfLines = numberOfLines
        textField.preferredMaxLayoutWidth = CGFloat(width)
        let measured = textField.fittingSize
        let lineHeight = max(1, ceil(NSFont.systemFont(ofSize: font.pointSize).pointSize * 1.35))
        let rawLines = max(1, Int(ceil(measured.height / lineHeight)))
        let linesUsed = numberOfLines > 0 ? min(numberOfLines, rawLines) : rawLines
        let height = CGFloat(linesUsed) * lineHeight
        return TextFieldSizeInfo(
            size: NSSize(width: CGFloat(width), height: ceil(height)),
            numberOfLinesUsed: linesUsed
        )
    }
}
