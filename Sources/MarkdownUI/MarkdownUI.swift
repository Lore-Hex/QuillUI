import Foundation
import SwiftUI

public struct Markdown: View {
    public var content: String
    private var highlighter: AnyCodeSyntaxHighlighter?

    public init(_ content: String) {
        self.content = content
        self.highlighter = nil
    }

    public var body: some View {
        MarkdownDocumentView(
            blocks: MarkdownBlockParser.parse(content),
            highlighter: highlighter
        )
    }

    public static func plainText(from markdown: String) -> String {
        MarkdownBlockParser.parse(markdown)
            .map(\.plainText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AnyCodeSyntaxHighlighter {
    private let _highlight: (String, String?) -> Text

    init(_ highlighter: some CodeSyntaxHighlighter) {
        self._highlight = { content, language in
            highlighter.highlightCode(content, language: language)
        }
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        _highlight(content, language)
    }
}

private enum MarkdownBlockKind: Equatable {
    case paragraph
    case heading(level: Int)
    case unorderedListItem
    case orderedListItem(number: Int)
    case quote
    case divider
    case codeBlock(language: String?)
    case table(headers: [String], rows: [[String]])
}

private struct MarkdownRenderedBlock: Identifiable, Equatable {
    var id: Int
    var kind: MarkdownBlockKind
    var text: String

    var plainText: String {
        switch kind {
        case .unorderedListItem:
            return "• \(MarkdownBlockParser.cleanInline(text))"
        case .orderedListItem(let number):
            return "\(number). \(MarkdownBlockParser.cleanInline(text))"
        case .codeBlock:
            return text
        case .divider:
            return ""
        case .table(let headers, let rows):
            return ([headers] + rows)
                .map { row in
                    row.map { MarkdownBlockParser.cleanInline($0) }.joined(separator: " | ")
                }
                .joined(separator: "\n")
        default:
            return MarkdownBlockParser.cleanInline(text)
        }
    }
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownRenderedBlock] {
        var blocks: [MarkdownRenderedBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var activeFence: MarkdownFence?
        let lines = splitLines(markdown)

        func append(_ kind: MarkdownBlockKind, _ text: String) {
            blocks.append(MarkdownRenderedBlock(id: blocks.count, kind: kind, text: text))
        }

        func flushParagraph() {
            let text = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphLines.removeAll(keepingCapacity: true)
            guard !cleanInline(text).isEmpty else { return }
            append(.paragraph, text)
        }

        func flushCodeBlock() {
            append(.codeBlock(language: activeFence?.language), codeLines.joined(separator: "\n"))
            codeLines.removeAll(keepingCapacity: true)
            activeFence = nil
        }

        var index = 0
        while index < lines.count {
            let rawLine = lines[index]

            if let fence = activeFence {
                if fence.matchesClosingLine(rawLine) {
                    flushCodeBlock()
                } else {
                    codeLines.append(rawLine)
                }
                index += 1
                continue
            }

            if let fence = MarkdownFence(openingLine: rawLine) {
                flushParagraph()
                activeFence = fence
                codeLines.removeAll(keepingCapacity: true)
                index += 1
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let table = table(startingAt: index, in: lines) {
                flushParagraph()
                blocks.append(
                    MarkdownRenderedBlock(
                        id: blocks.count,
                        kind: .table(headers: table.headers, rows: table.rows),
                        text: ""
                    )
                )
                index = table.endIndex
                continue
            }

            if let heading = heading(in: line) {
                flushParagraph()
                append(.heading(level: heading.level), heading.text)
            } else if thematicBreak(in: line) {
                flushParagraph()
                append(.divider, "")
            } else if let item = unorderedListItem(in: line) {
                flushParagraph()
                append(.unorderedListItem, item)
            } else if let item = orderedListItem(in: line) {
                flushParagraph()
                append(.orderedListItem(number: item.number), item.text)
            } else if let quote = quote(in: line) {
                flushParagraph()
                append(.quote, quote)
            } else if let setextLevel = setextHeadingLevel(after: index, in: lines) {
                paragraphLines.append(line)
                let title = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                paragraphLines.removeAll(keepingCapacity: true)
                if !cleanInline(title).isEmpty {
                    append(.heading(level: setextLevel), title)
                }
                index += 2
                continue
            } else {
                paragraphLines.append(line)
            }
            index += 1
        }

        if activeFence != nil {
            flushCodeBlock()
        } else {
            flushParagraph()
        }

        if blocks.isEmpty {
            return [MarkdownRenderedBlock(id: 0, kind: .paragraph, text: "")]
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
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: count)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
        let text = normalizedHeadingText(String(line[markerEnd...]))
        return text.isEmpty ? nil : (count, text)
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
        let text = String(line[line.index(after: afterMarker)...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (Int(digits) ?? 1, text)
    }

    private static func quote(in line: String) -> String? {
        normalizedQuoteText(line)
    }

    private static func normalizedQuoteText(_ line: String) -> String? {
        guard line.first == ">" else { return nil }
        let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func table(
        startingAt startIndex: Int,
        in lines: [String]
    ) -> (headers: [String], rows: [[String]], endIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }
        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|"), separatorLine.contains("|") else { return nil }

        let headers = tableCells(in: headerLine)
        let separatorCells = tableCells(in: separatorLine)
        guard headers.count >= 2, separatorCells.count == headers.count else { return nil }
        guard separatorCells.allSatisfy(isTableSeparatorCell) else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else { break }
            let cells = tableCells(in: line)
            guard !cells.isEmpty else { break }
            rows.append(normalizedTableRow(cells, columnCount: headers.count))
            index += 1
        }

        return (headers, rows, index)
    }

    private static func tableCells(in line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.first == "|" {
            text.removeFirst()
        }
        if text.last == "|" {
            text.removeLast()
        }
        return text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparatorCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let body = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return !body.isEmpty && body.allSatisfy { $0 == "-" }
    }

    private static func normalizedTableRow(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count == columnCount {
            return cells
        } else if cells.count > columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
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
        guard count >= 3 else { return nil }

        marker = first
        markerCount = count
        let labelStart = trimmed.index(trimmed.startIndex, offsetBy: count)
        let label = String(trimmed[labelStart...]).trimmingCharacters(in: .whitespaces)
        language = label.isEmpty ? nil : label
    }

    func matchesClosingLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == marker else { return false }

        let closingCount = trimmed.prefix(while: { $0 == marker }).count
        guard closingCount >= markerCount else { return false }

        let suffixStart = trimmed.index(trimmed.startIndex, offsetBy: closingCount)
        return String(trimmed[suffixStart...]).trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private enum MarkdownInlineRunKind: Equatable {
    case text(String)
    case strong(String)
    case emphasis(String)
    case code(String)
    case strikethrough(String)
    case link(title: String, destination: String)
    case image(alt: String, source: String)
}

private struct MarkdownInlineRun: Identifiable, Equatable {
    var id: Int
    var kind: MarkdownInlineRunKind
}

private enum MarkdownInlineParser {
    static func parse(_ text: String) -> [MarkdownInlineRun] {
        var runs: [MarkdownInlineRunKind] = []
        var index = text.startIndex

        func appendText(_ value: String) {
            guard !value.isEmpty else { return }
            if case .text(let previous)? = runs.last {
                runs[runs.count - 1] = .text(previous + value)
            } else {
                runs.append(.text(value))
            }
        }

        while index < text.endIndex {
            if text[index...].hasPrefix("!["),
               let parsed = bracketedInline(
                   in: text,
                   start: index,
                   markerLength: 2
               ) {
                runs.append(.image(alt: plainText(from: parsed.label), source: parsed.destination))
                index = parsed.endIndex
            } else if text[index] == "[",
                      let parsed = bracketedInline(in: text, start: index, markerLength: 1) {
                runs.append(.link(title: plainText(from: parsed.label), destination: parsed.destination))
                index = parsed.endIndex
            } else if text[index...].hasPrefix("**"),
                      let parsed = delimitedInline(in: text, start: index, delimiter: "**") {
                runs.append(.strong(plainText(from: parsed.content)))
                index = parsed.endIndex
            } else if text[index...].hasPrefix("__"),
                      let parsed = delimitedInline(in: text, start: index, delimiter: "__") {
                runs.append(.strong(plainText(from: parsed.content)))
                index = parsed.endIndex
            } else if text[index...].hasPrefix("~~"),
                      let parsed = delimitedInline(in: text, start: index, delimiter: "~~") {
                runs.append(.strikethrough(plainText(from: parsed.content)))
                index = parsed.endIndex
            } else if text[index] == "`",
                      let parsed = delimitedInline(in: text, start: index, delimiter: "`") {
                runs.append(.code(parsed.content))
                index = parsed.endIndex
            } else if text[index] == "*",
                      let parsed = delimitedInline(in: text, start: index, delimiter: "*") {
                runs.append(.emphasis(plainText(from: parsed.content)))
                index = parsed.endIndex
            } else if text[index] == "_",
                      let parsed = delimitedInline(in: text, start: index, delimiter: "_") {
                runs.append(.emphasis(plainText(from: parsed.content)))
                index = parsed.endIndex
            } else {
                appendText(String(text[index]))
                index = text.index(after: index)
            }
        }

        if runs.isEmpty {
            runs = [.text("")]
        }
        return runs.enumerated().map { MarkdownInlineRun(id: $0.offset, kind: $0.element) }
    }

    static func plainText(from text: String) -> String {
        parse(text)
            .map { run in
                switch run.kind {
                case .text(let value),
                     .strong(let value),
                     .emphasis(let value),
                     .code(let value),
                     .strikethrough(let value):
                    return value
                case .link(let title, let destination):
                    return destination.isEmpty ? title : "\(title) (\(destination))"
                case .image(let alt, _):
                    return alt
                }
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func delimitedInline(
        in text: String,
        start: String.Index,
        delimiter: String
    ) -> (content: String, endIndex: String.Index)? {
        let contentStart = text.index(start, offsetBy: delimiter.count)
        guard contentStart < text.endIndex else { return nil }
        guard let close = text[contentStart...].range(of: delimiter) else { return nil }
        guard close.lowerBound > contentStart else { return nil }
        return (String(text[contentStart..<close.lowerBound]), close.upperBound)
    }

    private static func bracketedInline(
        in text: String,
        start: String.Index,
        markerLength: Int
    ) -> (label: String, destination: String, endIndex: String.Index)? {
        let labelStart = text.index(start, offsetBy: markerLength)
        guard labelStart < text.endIndex else { return nil }
        guard let labelClose = text[labelStart...].firstIndex(of: "]") else { return nil }
        let destinationOpen = text.index(after: labelClose)
        guard destinationOpen < text.endIndex, text[destinationOpen] == "(" else { return nil }
        let destinationStart = text.index(after: destinationOpen)
        guard let destinationClose = text[destinationStart...].firstIndex(of: ")") else { return nil }
        let label = String(text[labelStart..<labelClose])
        let destination = String(text[destinationStart..<destinationClose])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (label, destination, text.index(after: destinationClose))
    }
}

private struct MarkdownDocumentView: View {
    var blocks: [MarkdownRenderedBlock]
    var highlighter: AnyCodeSyntaxHighlighter?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownRenderedBlock) -> some View {
        switch block.kind {
        case .paragraph:
            MarkdownInlineText(raw: block.text, font: .system(size: 14))
                .lineSpacing(4)
        case .heading(let level):
            MarkdownInlineText(raw: block.text, font: headingFont(level: level), weight: .semibold)
                .font(headingFont(level: level))
                .lineSpacing(3)
                .padding(.top, level <= 2 ? 8 : 4)
        case .unorderedListItem:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 15, weight: .semibold))
                MarkdownInlineText(raw: block.text, font: .system(size: 14))
                    .lineSpacing(4)
            }
        case .orderedListItem(let number):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, alignment: .trailing)
                MarkdownInlineText(raw: block.text, font: .system(size: 14))
                    .lineSpacing(4)
            }
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color(red: 0.82, green: 0.82, blue: 0.84))
                    .frame(width: 3)
                MarkdownInlineText(
                    raw: block.text,
                    font: .system(size: 14),
                    foregroundColor: Color(red: 0.38, green: 0.39, blue: 0.43)
                )
                    .lineSpacing(4)
            }
            .padding(.vertical, 2)
        case .divider:
            Divider()
                .padding(.vertical, 2)
        case .codeBlock(let language):
            codeBlock(text: block.text, language: language)
        case .table(let headers, let rows):
            tableBlock(headers: headers, rows: rows)
        }
    }

    private func codeBlock(text: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.38, green: 0.39, blue: 0.43))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.925, green: 0.925, blue: 0.945))

            Divider()

            (highlighter?.highlightCode(text.isEmpty ? " " : text, language: language) ?? Text(text.isEmpty ? " " : text))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .lineSpacing(3)
                .padding(12)
        }
        .background(Color(red: 0.965, green: 0.965, blue: 0.975))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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

    private func tableBlock(headers: [String], rows: [[String]]) -> some View {
        let columnWidths = tableColumnWidths(headers: headers, rows: rows)
        let displayRows = [MarkdownTableDisplayRow(id: 0, cells: headers, isHeader: true)]
            + rows.enumerated().map { MarkdownTableDisplayRow(id: $0.offset + 1, cells: $0.element, isHeader: false) }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(displayRows) { row in
                tableRow(row, columnWidths: columnWidths)
                if row.id < displayRows.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color(red: 0.965, green: 0.965, blue: 0.975))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func tableRow(_ row: MarkdownTableDisplayRow, columnWidths: [Double]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(row.cells.indices.map { MarkdownTableCell(id: $0, text: row.cells[$0]) }) { cell in
                MarkdownInlineText(
                    raw: cell.text,
                    font: row.isHeader ? .system(size: 12, weight: .semibold) : .system(size: 13)
                )
                .frame(width: columnWidths[safe: cell.id] ?? 120, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
        .background(row.isHeader ? Color(red: 0.925, green: 0.925, blue: 0.945) : Color(red: 0.985, green: 0.985, blue: 0.992))
    }

    private func tableColumnWidths(headers: [String], rows: [[String]]) -> [Double] {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }

        return (0..<columnCount).map { column in
            let values = [headers[safe: column] ?? ""] + rows.map { $0[safe: column] ?? "" }
            let maxLength = values.map { MarkdownInlineParser.plainText(from: $0).count }.max() ?? 0
            return min(240, max(86, Double(maxLength * 8 + 32)))
        }
    }
}

private struct MarkdownTableDisplayRow: Identifiable {
    var id: Int
    var cells: [String]
    var isHeader: Bool
}

private struct MarkdownTableCell: Identifiable {
    var id: Int
    var text: String
}

private struct MarkdownInlineText: View {
    var raw: String
    var font: Font
    var weight: SwiftUI.Font.Weight?
    var foregroundColor: Color?

    init(
        raw: String,
        font: Font,
        weight: SwiftUI.Font.Weight? = nil,
        foregroundColor: Color? = nil
    ) {
        self.raw = raw
        self.font = font
        self.weight = weight
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        let runs = MarkdownInlineParser.parse(raw)
        if runs.count == 1, case .text(let value) = runs[0].kind {
            styledText(value)
        } else if MarkdownInlineParser.plainText(from: raw).count > 180 {
            styledText(MarkdownInlineParser.plainText(from: raw))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach(runs) { run in
                    runView(run)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func styledText(_ value: String) -> some View {
        if let foregroundColor {
            Text(value)
                .font(font)
                .fontWeight(weight ?? .regular)
                .foregroundColor(foregroundColor)
        } else {
            Text(value)
                .font(font)
                .fontWeight(weight ?? .regular)
        }
    }

    @ViewBuilder
    private func runView(_ run: MarkdownInlineRun) -> some View {
        switch run.kind {
        case .text(let value):
            styledText(value)
        case .strong(let value):
            MarkdownInlineText(raw: value, font: font, weight: .semibold, foregroundColor: foregroundColor)
        case .emphasis(let value):
            styledText(value)
                .italic()
        case .code(let value):
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color(red: 0.925, green: 0.925, blue: 0.945))
                .cornerRadius(4)
        case .strikethrough(let value):
            styledText(value)
                .strikethrough()
        case .link(let title, _):
            Text(title)
                .font(font)
                .foregroundColor(Color(red: 0.0, green: 0.35, blue: 0.85))
                .underline()
        case .image(let alt, _):
            HStack(spacing: 3) {
                Image(systemName: "photo")
                Text(alt.isEmpty ? "Image" : alt)
                    .font(font)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public protocol CodeSyntaxHighlighter {
    func highlightCode(_ content: String, language: String?) -> Text
}

public struct PlainTextCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    public init() {}

    public func highlightCode(_ content: String, language: String?) -> Text {
        Text(content)
    }
}

public extension Markdown {
    func markdownCodeSyntaxHighlighter(_ highlighter: some CodeSyntaxHighlighter) -> Markdown {
        var copy = self
        copy.highlighter = AnyCodeSyntaxHighlighter(highlighter)
        return copy
    }

    func markdownTheme(_ theme: Theme) -> Markdown {
        self
    }
}

public struct Theme: Sendable {
    public init() {}

    public func text(_ style: () -> Void) -> Self {
        style()
        return self
    }

    public func code(_ style: () -> Void) -> Self {
        style()
        return self
    }

    public func strong(_ style: () -> Void) -> Self {
        style()
        return self
    }

    public func link(_ style: () -> Void) -> Self {
        style()
        return self
    }

    public func heading1<Content: View>(@ViewBuilder _ content: (HeadingConfiguration) -> Content) -> Self {
        _ = content(.heading(level: 1))
        return self
    }

    public func heading2<Content: View>(@ViewBuilder _ content: (HeadingConfiguration) -> Content) -> Self {
        _ = content(.heading(level: 2))
        return self
    }

    public func heading3<Content: View>(@ViewBuilder _ content: (HeadingConfiguration) -> Content) -> Self {
        _ = content(.heading(level: 3))
        return self
    }

    public func heading4<Content: View>(@ViewBuilder _ content: (HeadingConfiguration) -> Content) -> Self {
        _ = content(.heading(level: 4))
        return self
    }

    public func heading5<Content: View>(@ViewBuilder _ content: (HeadingConfiguration) -> Content) -> Self {
        _ = content(.heading(level: 5))
        return self
    }

    public func heading6<Content: View>(@ViewBuilder _ content: (HeadingConfiguration) -> Content) -> Self {
        _ = content(.heading(level: 6))
        return self
    }

    public func paragraph<Content: View>(@ViewBuilder _ content: (ParagraphConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func blockquote<Content: View>(@ViewBuilder _ content: (BlockquoteConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func codeBlock<Content: View>(@ViewBuilder _ content: (CodeBlockConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func listItem<Content: View>(@ViewBuilder _ content: (ListItemConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func taskListMarker<Content: View>(@ViewBuilder _ content: (TaskListMarkerConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func table<Content: View>(@ViewBuilder _ content: (TableConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func tableCell<Content: View>(@ViewBuilder _ content: (TableCellConfiguration) -> Content) -> Self {
        _ = content(.sample)
        return self
    }

    public func thematicBreak<Content: View>(@ViewBuilder _ content: () -> Content) -> Self {
        _ = content()
        return self
    }
}

public struct HeadingConfiguration {
    public var level: Int
    public var label: Text

    public static func heading(level: Int) -> HeadingConfiguration {
        HeadingConfiguration(level: level, label: Text("Heading"))
    }
}

public struct ParagraphConfiguration {
    public var label: Text
    public static var sample: ParagraphConfiguration { ParagraphConfiguration(label: Text("Paragraph")) }
}

public struct BlockquoteConfiguration {
    public var label: Text
    public static var sample: BlockquoteConfiguration { BlockquoteConfiguration(label: Text("Quote")) }
}

public struct CodeBlockConfiguration {
    public var language: String?
    public var content: String
    public var label: Text

    public init(language: String? = nil, content: String, label: Text? = nil) {
        self.language = language
        self.content = content
        self.label = label ?? Text(content)
    }

    public static var sample: CodeBlockConfiguration {
        CodeBlockConfiguration(language: "swift", content: "print(\"Quill\")")
    }
}

public struct ListItemConfiguration {
    public var label: Text
    public static var sample: ListItemConfiguration { ListItemConfiguration(label: Text("Item")) }
}

public struct TaskListMarkerConfiguration {
    public var isCompleted: Bool
    public static var sample: TaskListMarkerConfiguration { TaskListMarkerConfiguration(isCompleted: false) }
}

public struct TableConfiguration {
    public var label: Text
    public static var sample: TableConfiguration { TableConfiguration(label: Text("Table")) }
}

public struct TableCellConfiguration {
    public var row: Int
    public var column: Int
    public var label: Text
    public static var sample: TableCellConfiguration { TableCellConfiguration(row: 0, column: 0, label: Text("Cell")) }
}

public struct MarkdownLength: Equatable, Sendable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public var points: Double

    public init(points: Double) {
        self.points = points
    }

    public init(integerLiteral value: Int) {
        self.points = Double(value)
    }

    public init(floatLiteral value: Double) {
        self.points = value
    }

    public static let zero = MarkdownLength(points: 0)

    public static func em(_ value: Double) -> MarkdownLength {
        MarkdownLength(points: value * 16)
    }
}

public struct MarkdownFontFamilyVariant: Sendable {
    public static let monospaced = MarkdownFontFamilyVariant()
}

public func FontSize(_ size: MarkdownLength) {}
public func FontFamilyVariant(_ variant: MarkdownFontFamilyVariant) {}
public func FontWeight(_ weight: SwiftUI.Font.Weight) {}
public func ForegroundColor(_ color: Color) {}
public func BackgroundColor(_ color: Color?) {}

public struct MarkdownTableBorderStyle {
    public var color: Color

    public init(color: Color) {
        self.color = color
    }
}

public struct MarkdownTableBackgroundStyle {
    public var oddRows: Color
    public var evenRows: Color

    public init(oddRows: Color, evenRows: Color) {
        self.oddRows = oddRows
        self.evenRows = evenRows
    }

    public static func alternatingRows(_ oddRows: Color, _ evenRows: Color) -> MarkdownTableBackgroundStyle {
        MarkdownTableBackgroundStyle(oddRows: oddRows, evenRows: evenRows)
    }
}

public extension Text {
    static func + (lhs: Text, rhs: Text) -> Text {
        Text(lhs.content + rhs.content)
    }

    func foregroundColor(_ color: Color) -> Text {
        self
    }
}

public extension View {
    func markdownTheme(_ theme: Theme) -> some View {
        self
    }

    func markdownCodeSyntaxHighlighter(_ highlighter: some CodeSyntaxHighlighter) -> some View {
        self
    }

    func markdownTextStyle(_ style: () -> Void) -> some View {
        style()
        return self
    }

    func markdownMargin(top: MarkdownLength = .zero, bottom: MarkdownLength = .zero) -> some View {
        padding(top: Int(top.points), bottom: Int(bottom.points))
    }

    func relativeLineSpacing(_ length: MarkdownLength) -> some View {
        lineSpacing(length.points)
    }

    func relativePadding(_ edges: Edge.Set = .all, length: MarkdownLength) -> some View {
        padding(edges, Int(length.points))
    }

    func relativeFrame(
        width: MarkdownLength? = nil,
        height: MarkdownLength? = nil,
        minWidth: MarkdownLength? = nil,
        minHeight: MarkdownLength? = nil,
        alignment: Alignment = .center
    ) -> some View {
        if minWidth != nil || minHeight != nil {
            return frame(
                minWidth: minWidth?.points,
                minHeight: minHeight?.points,
                alignment: alignment
            )
        }
        return frame(width: width?.points, height: height?.points, alignment: alignment)
    }

    func markdownTableBorderStyle(_ style: MarkdownTableBorderStyle) -> some View {
        self
    }

    func markdownTableBackgroundStyle(_ style: MarkdownTableBackgroundStyle) -> some View {
        self
    }
}
