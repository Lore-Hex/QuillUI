import Foundation
import QuillEnchantedShared
import QuillUI

enum MarkdownBlockKind: Equatable, Sendable {
    case paragraph
    case heading(level: Int)
    case unorderedListItem
    case orderedListItem(number: Int)
    case quote
    case divider
    case codeBlock(language: String?)
}

struct MarkdownBlock: Identifiable, Equatable, Sendable {
    var id: Int
    var kind: MarkdownBlockKind
    var text: String
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var activeFence: MarkdownFence?

        func appendBlock(kind: MarkdownBlockKind, text: String) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text))
        }

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: " ")
            paragraphLines.removeAll(keepingCapacity: true)
            guard let text = cleanInline(joined).quillTrimmedNonEmpty else { return }
            appendBlock(kind: .paragraph, text: text)
        }

        func flushCodeBlock() {
            appendBlock(kind: .codeBlock(language: activeFence?.language), text: codeLines.joined(separator: "\n"))
            codeLines.removeAll(keepingCapacity: true)
            activeFence = nil
        }

        let lines = splitLines(markdown)
        var lineIndex = 0
        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            if let fence = activeFence {
                if fence.matchesClosingLine(rawLine) {
                    flushCodeBlock()
                } else {
                    codeLines.append(rawLine)
                }
                lineIndex += 1
                continue
            }

            if let fence = MarkdownFence(openingLine: rawLine) {
                flushParagraph()
                activeFence = fence
                codeLines.removeAll(keepingCapacity: true)
                lineIndex += 1
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if let heading = heading(in: line) {
                flushParagraph()
                appendBlock(kind: .heading(level: heading.level), text: cleanInline(heading.text))
            } else if thematicBreak(in: line) {
                flushParagraph()
                appendBlock(kind: .divider, text: "")
            } else if let item = unorderedListItem(in: line) {
                flushParagraph()
                appendBlock(kind: .unorderedListItem, text: cleanInline(item))
            } else if let item = orderedListItem(in: line) {
                flushParagraph()
                appendBlock(kind: .orderedListItem(number: item.number), text: cleanInline(item.text))
            } else if let quote = quote(in: line) {
                flushParagraph()
                appendBlock(kind: .quote, text: cleanInline(quote))
            } else if let setextLevel = setextHeadingLevel(after: lineIndex, in: lines) {
                paragraphLines.append(line)
                let title = cleanInline(paragraphLines.joined(separator: " "))
                paragraphLines.removeAll(keepingCapacity: true)
                if let text = title.quillTrimmedNonEmpty {
                    appendBlock(kind: .heading(level: setextLevel), text: text)
                }
                lineIndex += 2
                continue
            } else {
                paragraphLines.append(line)
            }
            lineIndex += 1
        }

        if activeFence != nil {
            flushCodeBlock()
        } else {
            flushParagraph()
        }

        return blocks
    }

    static func cleanInline(_ text: String) -> String {
        var cleaned = protectBackslashEscapes(in: text)
        cleaned = replaceImages(in: cleaned)
        cleaned = replaceLinks(in: cleaned)
        cleaned = replaceAutolinks(in: cleaned)
        cleaned = removeInlineHTML(in: cleaned)
        cleaned = decodeCharacterReferences(in: cleaned)
        cleaned = removePairedMarkers(in: cleaned, marker: "**")
        cleaned = removePairedMarkers(in: cleaned, marker: "__")
        cleaned = removePairedMarkers(in: cleaned, marker: "`")
        cleaned = removePairedMarkers(in: cleaned, marker: "~~")
        cleaned = removePairedSingleMarkers(in: cleaned, marker: "*")
        cleaned = removePairedSingleMarkers(in: cleaned, marker: "_")
        cleaned = restoreBackslashEscapes(in: cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func replaceLinks(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            if let replacement = markdownLinkReplacement(in: text, at: index) {
                result += replacement.text
                index = replacement.endIndex
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }

        return result
    }

    private static func replaceImages(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            if let replacement = markdownImageReplacement(in: text, at: index) {
                result += replacement.text
                index = replacement.endIndex
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }

        return result
    }

    private static func markdownImageReplacement(
        in text: String,
        at index: String.Index
    ) -> (text: String, endIndex: String.Index)? {
        guard text[index] == "!" else { return nil }

        let labelStart = text.index(after: index)
        guard labelStart < text.endIndex, text[labelStart] == "[" else { return nil }

        let labelContentStart = text.index(after: labelStart)
        guard let labelEnd = closingBracket(in: text, from: labelContentStart) else { return nil }

        let destinationStartMarker = text.index(after: labelEnd)
        guard destinationStartMarker < text.endIndex, text[destinationStartMarker] == "(" else {
            return nil
        }

        let destinationStart = text.index(after: destinationStartMarker)
        guard let destinationEnd = closingParenthesis(in: text, from: destinationStart) else {
            return nil
        }

        let label = String(text[labelContentStart..<labelEnd])
        return (label, text.index(after: destinationEnd))
    }

    private static func markdownLinkReplacement(
        in text: String,
        at index: String.Index
    ) -> (text: String, endIndex: String.Index)? {
        guard text[index] == "[",
              !isImageLabelStart(in: text, at: index) else { return nil }
        let labelStart = index
        let labelContentStart = text.index(after: labelStart)
        guard let labelEnd = closingBracket(in: text, from: labelContentStart) else { return nil }

        let destinationStartMarker = text.index(after: labelEnd)
        guard destinationStartMarker < text.endIndex, text[destinationStartMarker] == "(" else {
            return nil
        }

        let destinationStart = text.index(after: destinationStartMarker)
        guard let destinationEnd = closingParenthesis(in: text, from: destinationStart) else {
            return nil
        }

        let label = String(text[labelContentStart..<labelEnd])
        let destination = String(text[destinationStart..<destinationEnd])
        let replacement = label.isEmpty ? "(\(destination))" : "\(label) (\(destination))"
        return (replacement, text.index(after: destinationEnd))
    }

    private static func isImageLabelStart(in text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return false }
        let previous = text[text.index(before: index)]
        if previous == "!" {
            return true
        }

        return previous.unicodeScalars.first?.value == escapedMarkdownScalarBase + 33
    }

    private static func closingBracket(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "]" {
                return index
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func closingParenthesis(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 {
                    return index
                }
                depth -= 1
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func replaceAutolinks(in text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "<",
               let closingIndex = text[text.index(after: index)...].firstIndex(of: ">") {
                let content = String(text[text.index(after: index)..<closingIndex])
                if isAutolinkContent(content) {
                    result += content
                    index = text.index(after: closingIndex)
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }

    private static func isAutolinkContent(_ text: String) -> Bool {
        guard !text.isEmpty,
              !text.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) else {
            return false
        }

        if let colonIndex = text.firstIndex(of: ":") {
            let scheme = text[..<colonIndex]
            return (2...32).contains(scheme.count)
                && scheme.first?.isLetter == true
                && scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }
                && text.index(after: colonIndex) < text.endIndex
        }

        if let atIndex = text.firstIndex(of: "@") {
            let localPart = text[..<atIndex]
            let domainPart = text[text.index(after: atIndex)...]
            return !localPart.isEmpty
                && domainPart.contains(".")
                && !domainPart.isEmpty
        }

        return false
    }

    private static func removeInlineHTML(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "<" {
                if text[index...].hasPrefix("<!--"),
                   let closingRange = text[index...].range(of: "-->") {
                    index = closingRange.upperBound
                    continue
                }

                if let replacement = inlineHTMLTagReplacement(in: text, at: index) {
                    if replacement.insertsSpace {
                        result.append(" ")
                    }
                    index = replacement.endIndex
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }

    private static func inlineHTMLTagReplacement(
        in text: String,
        at index: String.Index
    ) -> (endIndex: String.Index, insertsSpace: Bool)? {
        guard text[index] == "<" else { return nil }

        var cursor = text.index(after: index)
        if cursor < text.endIndex, text[cursor] == "/" {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor].isASCIIAlphabetic else { return nil }

        let tagStart = cursor
        while cursor < text.endIndex, text[cursor].isASCIIHTMLTagNameCharacter {
            cursor = text.index(after: cursor)
        }

        let tagName = String(text[tagStart..<cursor]).lowercased()
        guard inlineHTMLTagNames.contains(tagName) else { return nil }

        while cursor < text.endIndex, text[cursor] != ">" {
            if text[cursor] == "<" {
                return nil
            }
            cursor = text.index(after: cursor)
        }

        guard cursor < text.endIndex else { return nil }
        return (text.index(after: cursor), inlineHTMLSpaceTags.contains(tagName))
    }

    private static let inlineHTMLTagNames: Set<String> = [
        "a", "abbr", "b", "br", "button", "code", "del", "div", "em", "i",
        "kbd", "li", "mark", "ol", "p", "pre", "s", "span", "strong", "sub",
        "sup", "u", "ul"
    ]

    private static let inlineHTMLSpaceTags: Set<String> = [
        "br", "div", "li", "p"
    ]

    private static func decodeCharacterReferences(in text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "&",
               let semicolonIndex = text[text.index(after: index)...].firstIndex(of: ";") {
                let reference = String(text[text.index(after: index)..<semicolonIndex])
                if let decoded = decodedCharacterReference(reference) {
                    result += decoded
                    index = text.index(after: semicolonIndex)
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }

    private static func decodedCharacterReference(_ reference: String) -> String? {
        switch reference {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        case "nbsp":
            return "\u{00A0}"
        case "copy":
            return "\u{00A9}"
        case "reg":
            return "\u{00AE}"
        case "trade":
            return "\u{2122}"
        case "ndash":
            return "\u{2013}"
        case "mdash":
            return "\u{2014}"
        case "lsquo":
            return "\u{2018}"
        case "rsquo":
            return "\u{2019}"
        case "ldquo":
            return "\u{201C}"
        case "rdquo":
            return "\u{201D}"
        case "hellip":
            return "\u{2026}"
        default:
            break
        }

        let scalarValue: UInt32?
        if reference.hasPrefix("#x") || reference.hasPrefix("#X") {
            scalarValue = UInt32(reference.dropFirst(2), radix: 16)
        } else if reference.hasPrefix("#") {
            scalarValue = UInt32(reference.dropFirst(), radix: 10)
        } else {
            scalarValue = nil
        }

        guard let scalarValue,
              scalarValue != 0,
              let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }
        return String(Character(scalar))
    }

    private static let escapedMarkdownScalarBase: UInt32 = 0xE000

    private static func protectBackslashEscapes(in text: String) -> String {
        var result = String.UnicodeScalarView()
        var index = text.unicodeScalars.startIndex

        while index < text.unicodeScalars.endIndex {
            let scalar = text.unicodeScalars[index]
            if scalar.value == 92 {
                let nextIndex = text.unicodeScalars.index(after: index)
                if nextIndex < text.unicodeScalars.endIndex,
                   let protected = protectedEscapedPunctuation(text.unicodeScalars[nextIndex]) {
                    result.append(protected)
                    index = text.unicodeScalars.index(after: nextIndex)
                    continue
                }
            }

            result.append(scalar)
            index = text.unicodeScalars.index(after: index)
        }

        return String(result)
    }

    private static func restoreBackslashEscapes(in text: String) -> String {
        var result = String.UnicodeScalarView()
        let escapedMarkdownScalarRange = escapedMarkdownScalarBase..<(escapedMarkdownScalarBase + 128)

        for scalar in text.unicodeScalars {
            if escapedMarkdownScalarRange.contains(scalar.value),
               let restored = UnicodeScalar(scalar.value - escapedMarkdownScalarBase) {
                result.append(restored)
            } else {
                result.append(scalar)
            }
        }

        return String(result)
    }

    private static func protectedEscapedPunctuation(_ scalar: UnicodeScalar) -> UnicodeScalar? {
        guard scalar.value < 128,
              isEscapableMarkdownPunctuation(scalar),
              let protected = UnicodeScalar(escapedMarkdownScalarBase + scalar.value) else {
            return nil
        }

        return protected
    }

    private static func isEscapableMarkdownPunctuation(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 33, 35, 40, 41, 42, 43, 45, 46, 60, 62, 91, 92, 93, 95, 96, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    private static func removePairedSingleMarkers(in text: String, marker: Character) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == marker {
                let contentStart = text.index(after: index)
                if let closingIndex = text[contentStart...].firstIndex(of: marker),
                   closingIndex > contentStart {
                    result += String(text[contentStart..<closingIndex])
                    index = text.index(after: closingIndex)
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }

    private static func removePairedMarkers(in text: String, marker: String) -> String {
        guard !marker.isEmpty else { return text }

        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix(marker) {
                let contentStart = text.index(index, offsetBy: marker.count)
                if let closingRange = text[contentStart...].range(of: marker),
                   closingRange.lowerBound > contentStart {
                    result += String(text[contentStart..<closingRange.lowerBound])
                    index = closingRange.upperBound
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let markers = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markers) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: markers)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let text = normalizedHeadingText(String(line[markerEnd...]))
        guard !text.isEmpty else { return nil }
        return (markers, text)
    }

    private static func normalizedHeadingText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.last == "#" else { return trimmed }

        var hashStart = trimmed.endIndex
        while hashStart > trimmed.startIndex {
            let previous = trimmed.index(before: hashStart)
            guard trimmed[previous] == "#" else { break }
            hashStart = previous
        }

        guard hashStart > trimmed.startIndex else { return trimmed }
        let beforeHashes = trimmed.index(before: hashStart)
        guard trimmed[beforeHashes].isWhitespace else { return trimmed }

        let candidate = trimmed[..<hashStart].trimmingCharacters(in: .whitespaces)
        return candidate.isEmpty ? trimmed : candidate
    }

    private static func setextHeadingLevel(after lineIndex: Int, in lines: [String]) -> Int? {
        let underlineIndex = lineIndex + 1
        guard underlineIndex < lines.count else { return nil }

        let underline = lines[underlineIndex].trimmingCharacters(in: .whitespaces)
        guard let marker = underline.first, marker == "=" || marker == "-" else { return nil }
        guard underline.allSatisfy({ $0 == marker }) else { return nil }

        return marker == "=" ? 1 : 2
    }

    private static func thematicBreak(in line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "_" else { return false }

        var markerCount = 0
        for character in trimmed {
            if character == marker {
                markerCount += 1
            } else if !character.isWhitespace {
                return false
            }
        }

        return markerCount >= 3
    }

    private static func unorderedListItem(in line: String) -> String? {
        guard line.count > 2 else { return nil }
        let marker = line[line.startIndex]
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let space = line.index(after: line.startIndex)
        guard line[space].isWhitespace else { return nil }
        let text = String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func orderedListItem(in line: String) -> (number: Int, text: String)? {
        var index = line.startIndex
        var digits = ""
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex else { return nil }
        let marker = line[index]
        guard marker == "." || marker == ")" else { return nil }
        let afterMarker = line.index(after: index)
        guard afterMarker < line.endIndex, line[afterMarker].isWhitespace else { return nil }
        let textStart = line.index(after: afterMarker)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (Int(digits) ?? 1, text)
    }

    private static func quote(in line: String) -> String? {
        normalizedQuoteText(line)
    }

    private static func normalizedQuoteText(_ line: String) -> String? {
        guard line.first == ">" else { return nil }
        let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }
}

private extension Character {
    var isASCIIAlphabetic: Bool {
        guard unicodeScalars.count == 1,
              let scalar = unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    var isASCIIHTMLTagNameCharacter: Bool {
        guard unicodeScalars.count == 1,
              let scalar = unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
            || (48...57).contains(scalar.value)
            || scalar.value == 45
    }
}

private struct MarkdownFence {
    var marker: Character
    var markerCount: Int
    var language: String?

    init?(openingLine: String) {
        let trimmed = openingLine.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else {
            return nil
        }

        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else {
            return nil
        }

        marker = first
        markerCount = count
        let labelStart = trimmed.index(trimmed.startIndex, offsetBy: count)
        language = String(trimmed[labelStart...]).quillTrimmedNonEmpty
    }

    func matchesClosingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == marker else {
            return false
        }

        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= markerCount else {
            return false
        }

        let suffixStart = trimmed.index(trimmed.startIndex, offsetBy: count)
        return String(trimmed[suffixStart...]).trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public struct MarkdownMessageView: View {
    var markdown: String
    var foregroundColor: Color

    public init(markdown: String, foregroundColor: Color) {
        self.markdown = markdown
        self.foregroundColor = foregroundColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.markdownBlockSpacing)) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    private var blocks: [MarkdownBlock] {
        let parsed = MarkdownParser.parse(markdown)
        if parsed.isEmpty {
            return [MarkdownBlock(id: 0, kind: .paragraph, text: "")]
        }
        return parsed
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            Text(block.text)
                .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize)))
                .foregroundColor(foregroundColor)
                .lineSpacing(3)
        case .heading(let level):
            Text(block.text)
                .font(headingFont(level: level))
                .foregroundColor(QuillColors.ink)
                .lineSpacing(2)
        case .unorderedListItem:
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownListItemSpacing)) {
                Text("•")
                    .font(.system(size: CGFloat(EnchantedTypography.markdownHeadingFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)))
                    .foregroundColor(QuillColors.primary)
                Text(block.text)
                    .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize)))
                    .foregroundColor(foregroundColor)
                    .lineSpacing(3)
            }
        case .orderedListItem(let number):
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownListItemSpacing)) {
                Text("\(number).")
                    .font(.system(size: CGFloat(EnchantedTypography.markdownHeadingFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)))
                    .foregroundColor(QuillColors.primary)
                    .frame(width: CGFloat(EnchantedVisualMetrics.markdownNumberWidth), alignment: .trailing)
                Text(block.text)
                    .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize)))
                    .foregroundColor(foregroundColor)
                    .lineSpacing(3)
            }
        case .quote:
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownQuoteSpacing)) {
                Rectangle()
                    .fill(QuillColors.quoteRule)
                    .frame(width: CGFloat(EnchantedVisualMetrics.markdownQuoteRuleWidth))
                Text(block.text)
                    .font(.system(size: CGFloat(EnchantedTypography.markdownHeadingFontSize)))
                    .foregroundColor(QuillColors.muted)
                    .lineSpacing(3)
            }
            .padding(.vertical, CGFloat(EnchantedVisualMetrics.markdownQuoteVerticalPadding))
        case .divider:
            Rectangle()
                .fill(QuillColors.quoteRule)
                .frame(height: CGFloat(EnchantedVisualMetrics.markdownQuoteRuleWidth))
                .padding(.vertical, CGFloat(EnchantedVisualMetrics.markdownQuoteVerticalPadding))
        case .codeBlock(let language):
            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.markdownCodeBlockSpacing)) {
                if let language {
                    Text(language.uppercased())
                        .font(.system(size: CGFloat(EnchantedTypography.markdownCodeLanguageFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)))
                        .foregroundColor(QuillColors.muted)
                }
                Text(block.text.isEmpty ? " " : block.text)
                    .font(.system(size: CGFloat(EnchantedTypography.markdownCodeFontSize), weight: .regular, design: .monospaced))
                    .foregroundColor(QuillColors.ink)
                    .lineSpacing(2)
            }
            .padding(CGFloat(EnchantedVisualMetrics.markdownCodeBlockPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QuillColors.codeBlock)
            .cornerRadius(CGFloat(EnchantedVisualMetrics.markdownCodeBlockRadius))
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: CGFloat(EnchantedTypography.markdownHeading1FontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight))
        case 2:
            return .system(size: CGFloat(EnchantedTypography.markdownHeading2FontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight))
        default:
            return .system(size: CGFloat(EnchantedTypography.markdownHeadingFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight))
        }
    }
}
