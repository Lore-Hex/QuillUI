import Foundation
import QuillEnchantedShared
import QuillUI

enum MarkdownBlockKind: Equatable, Sendable {
    case paragraph
    case heading(level: Int)
    case unorderedListItem
    case orderedListItem(number: Int)
    case quote
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

        for rawLine in splitLines(markdown) {
            if let fence = activeFence {
                if fence.matchesClosingLine(rawLine) {
                    flushCodeBlock()
                } else {
                    codeLines.append(rawLine)
                }
                continue
            }

            if let fence = MarkdownFence(openingLine: rawLine) {
                flushParagraph()
                activeFence = fence
                codeLines.removeAll(keepingCapacity: true)
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = heading(in: line) {
                flushParagraph()
                appendBlock(kind: .heading(level: heading.level), text: cleanInline(heading.text))
            } else if let item = unorderedListItem(in: line) {
                flushParagraph()
                appendBlock(kind: .unorderedListItem, text: cleanInline(item))
            } else if let item = orderedListItem(in: line) {
                flushParagraph()
                appendBlock(kind: .orderedListItem(number: item.number), text: cleanInline(item.text))
            } else if let quote = quote(in: line) {
                flushParagraph()
                appendBlock(kind: .quote, text: cleanInline(quote))
            } else {
                paragraphLines.append(line)
            }
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
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "$1 ($2)")
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let markers = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markers) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: markers)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let text = line[markerEnd...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (markers, text)
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
        guard !digits.isEmpty, index < line.endIndex, line[index] == "." else { return nil }
        let afterPeriod = line.index(after: index)
        guard afterPeriod < line.endIndex, line[afterPeriod].isWhitespace else { return nil }
        let textStart = line.index(after: afterPeriod)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (Int(digits) ?? 1, text)
    }

    private static func quote(in line: String) -> String? {
        guard line.first == ">" else { return nil }
        let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }
}

private struct MarkdownFence {
    var delimiter: String
    var language: String?

    init?(openingLine: String) {
        let trimmed = openingLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            delimiter = "```"
        } else if trimmed.hasPrefix("~~~") {
            delimiter = "~~~"
        } else {
            return nil
        }

        let labelStart = trimmed.index(trimmed.startIndex, offsetBy: delimiter.count)
        language = String(trimmed[labelStart...]).quillTrimmedNonEmpty
    }

    func matchesClosingLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(delimiter)
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
                .foregroundColor(foregroundColor)
                .lineSpacing(3)
        case .heading(let level):
            Text(block.text)
                .font(headingFont(level: level))
                .fontWeight(.semibold)
                .foregroundColor(QuillColors.ink)
                .lineSpacing(2)
        case .unorderedListItem:
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownListItemSpacing)) {
                Text("•")
                    .font(.headline)
                    .foregroundColor(QuillColors.primary)
                Text(block.text)
                    .foregroundColor(foregroundColor)
                    .lineSpacing(3)
            }
        case .orderedListItem(let number):
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownListItemSpacing)) {
                Text("\(number).")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(QuillColors.primary)
                    .frame(width: CGFloat(EnchantedVisualMetrics.markdownNumberWidth), alignment: .trailing)
                Text(block.text)
                    .foregroundColor(foregroundColor)
                    .lineSpacing(3)
            }
        case .quote:
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownQuoteSpacing)) {
                Rectangle()
                    .fill(QuillColors.quoteRule)
                    .frame(width: CGFloat(EnchantedVisualMetrics.markdownQuoteRuleWidth))
                Text(block.text)
                    .foregroundColor(QuillColors.muted)
                    .lineSpacing(3)
            }
            .padding(.vertical, CGFloat(EnchantedVisualMetrics.markdownQuoteVerticalPadding))
        case .codeBlock(let language):
            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.markdownCodeBlockSpacing)) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
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
            return .title3
        case 2:
            return .headline
        default:
            return .subheadline
        }
    }
}
