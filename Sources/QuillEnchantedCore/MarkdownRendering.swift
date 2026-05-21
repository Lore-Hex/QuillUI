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
        var cleaned = replaceLinks(in: text)
        for marker in ["**", "__", "`", "~~"] {
            cleaned = cleaned.replacingOccurrences(of: marker, with: "")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func replaceLinks(in text: String) -> String {
        let pattern = #"!?\[([^\]]+)\]\(([^)]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "$1 ($2)")
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
        return String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
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
