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
    case table(headers: [String], rows: [[String]])
    case codeBlock(language: String?)
}

enum MarkdownTaskState: Equatable, Sendable {
    case checked
    case unchecked
}

struct MarkdownBlock: Identifiable, Equatable, Sendable {
    var id: Int
    var kind: MarkdownBlockKind
    var text: String
    var taskState: MarkdownTaskState? = nil
}

private struct MarkdownParagraphLine {
    var text: String
    var hardBreakAfter: Bool
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [MarkdownParagraphLine] = []
        var codeLines: [String] = []
        var indentedCodeLines: [String] = []
        var activeFence: MarkdownFence?
        var parsingIndentedCodeBlock = false
        var skippingHTMLCommentBlock = false

        func appendBlock(kind: MarkdownBlockKind, text: String, taskState: MarkdownTaskState? = nil) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text, taskState: taskState))
        }

        func flushParagraph() {
            let joined = Self.joinedParagraphText(paragraphLines)
            paragraphLines.removeAll(keepingCapacity: true)
            guard let text = cleanInline(joined).quillTrimmedNonEmpty else { return }
            appendBlock(kind: .paragraph, text: text)
        }

        func flushFencedCodeBlock() {
            appendBlock(kind: .codeBlock(language: activeFence?.language), text: codeLines.joined(separator: "\n"))
            codeLines.removeAll(keepingCapacity: true)
            activeFence = nil
        }

        func flushIndentedCodeBlock() {
            appendBlock(kind: .codeBlock(language: nil), text: Self.normalizedCodeBlockText(indentedCodeLines))
            indentedCodeLines.removeAll(keepingCapacity: true)
            parsingIndentedCodeBlock = false
        }

        let lines = splitLines(markdown)
        var lineIndex = 0
        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            if let fence = activeFence {
                if fence.matchesClosingLine(rawLine) {
                    flushFencedCodeBlock()
                } else {
                    codeLines.append(rawLine)
                }
                lineIndex += 1
                continue
            }

            if parsingIndentedCodeBlock {
                if let codeLine = indentedCodeLine(from: rawLine) {
                    indentedCodeLines.append(codeLine)
                    lineIndex += 1
                    continue
                }

                if rawLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    indentedCodeLines.append("")
                    lineIndex += 1
                    continue
                }

                flushIndentedCodeBlock()
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if paragraphLines.isEmpty, let codeLine = indentedCodeLine(from: rawLine) {
                indentedCodeLines.append(codeLine)
                parsingIndentedCodeBlock = true
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

            if skippingHTMLCommentBlock {
                if closesHTMLCommentBlock(rawLine) {
                    skippingHTMLCommentBlock = false
                }
                lineIndex += 1
                continue
            }

            if let commentContinues = htmlCommentBlock(rawLine) {
                flushParagraph()
                skippingHTMLCommentBlock = commentContinues
                lineIndex += 1
                continue
            }

            if linkReferenceDefinition(in: rawLine) {
                flushParagraph()
                lineIndex += 1
                continue
            }

            if let table = table(startingAt: lineIndex, in: lines) {
                flushParagraph()
                appendBlock(
                    kind: .table(headers: table.headers, rows: table.rows),
                    text: tableText(headers: table.headers, rows: table.rows)
                )
                lineIndex = table.endIndex
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
                let taskItem = taskListItem(in: item)
                appendBlock(
                    kind: .unorderedListItem,
                    text: cleanInline(taskItem?.text ?? item),
                    taskState: taskItem?.state
                )
            } else if let item = orderedListItem(in: line) {
                flushParagraph()
                let taskItem = taskListItem(in: item.text)
                appendBlock(
                    kind: .orderedListItem(number: item.number),
                    text: cleanInline(taskItem?.text ?? item.text),
                    taskState: taskItem?.state
                )
            } else if let quote = quoteBlock(startingAt: lineIndex, in: lines) {
                flushParagraph()
                appendBlock(kind: .quote, text: quote.text)
                lineIndex = quote.endIndex
                continue
            } else if let setextLevel = setextHeadingLevel(after: lineIndex, in: lines) {
                paragraphLines.append(Self.paragraphLine(from: rawLine))
                let title = cleanInline(Self.joinedParagraphText(paragraphLines))
                paragraphLines.removeAll(keepingCapacity: true)
                if let text = title.quillTrimmedNonEmpty {
                    appendBlock(kind: .heading(level: setextLevel), text: text)
                }
                lineIndex += 2
                continue
            } else {
                paragraphLines.append(Self.paragraphLine(from: rawLine))
            }
            lineIndex += 1
        }

        if activeFence != nil {
            flushFencedCodeBlock()
        } else if parsingIndentedCodeBlock {
            flushIndentedCodeBlock()
        } else {
            flushParagraph()
        }

        return blocks
    }

    static func cleanInline(_ text: String) -> String {
        var cleaned = protectBackslashEscapes(in: text)
        cleaned = removePairedCodeSpanMarkers(in: cleaned)
        cleaned = replaceImages(in: cleaned)
        cleaned = replaceLinks(in: cleaned)
        cleaned = replaceReferenceImages(in: cleaned)
        cleaned = replaceReferenceLinks(in: cleaned)
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

    private static func paragraphLine(from rawLine: String) -> MarkdownParagraphLine {
        MarkdownParagraphLine(
            text: normalizedParagraphLineText(rawLine),
            hardBreakAfter: markdownHardLineBreak(after: rawLine)
        )
    }

    private static func normalizedParagraphLineText(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasSuffix("\\") {
            line.removeLast()
            line = line.trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    private static func markdownHardLineBreak(after rawLine: String) -> Bool {
        guard !emptyMarkdownContainerMarker(normalizedParagraphLineText(rawLine)) else {
            return false
        }
        return markdownHardLineBreakSpaces(after: rawLine)
            || rawLine.trimmingCharacters(in: .whitespaces).hasSuffix("\\")
    }

    private static func emptyMarkdownContainerMarker(_ line: String) -> Bool {
        switch line {
        case "-", "*", "+", ">":
            return true
        default:
            guard let marker = line.last,
                  marker == "." || marker == ")" else {
                return false
            }

            let digits = line.dropLast()
            return !digits.isEmpty && digits.allSatisfy(\.isNumber)
        }
    }

    private static func markdownHardLineBreakSpaces(after rawLine: String) -> Bool {
        var trailingSpaces = 0
        for scalar in rawLine.unicodeScalars.reversed() {
            if scalar.value == 32 {
                trailingSpaces += 1
            } else {
                break
            }
        }
        return trailingSpaces >= 2
    }

    private static func joinedParagraphText(_ lines: [MarkdownParagraphLine]) -> String {
        var text = ""
        for (index, line) in lines.enumerated() {
            if index > 0 {
                text += lines[index - 1].hardBreakAfter ? "\n" : " "
            }
            text += line.text
        }
        return text
    }

    private static func table(
        startingAt startIndex: Int,
        in lines: [String]
    ) -> (headers: [String], rows: [[String]], endIndex: Int)? {
        guard startIndex + 1 < lines.count,
              let headerCells = tableCells(in: lines[startIndex]),
              let separatorCells = tableCells(in: lines[startIndex + 1]),
              separatorCells.count == headerCells.count,
              isTableSeparator(separatorCells)
        else { return nil }

        let headers = normalizedTableRow(headerCells, columnCount: headerCells.count)
        guard headers.contains(where: { !$0.isEmpty }) else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            guard let cells = tableCells(in: lines[index]),
                  !isTableSeparator(cells)
            else { break }

            rows.append(normalizedTableRow(cells, columnCount: headers.count))
            index += 1
        }

        return (headers, rows, index)
    }

    private static func tableCells(in rawLine: String) -> [String]? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.contains("|") else { return nil }

        if line.first == "|" {
            line.removeFirst()
        }
        if let lastIndex = line.indices.last,
           line[lastIndex] == "|",
           !isEscapedMarkdownCharacter(in: line, at: lastIndex) {
            line.removeLast()
        }

        let cells = splitTableCells(in: line)
        guard cells.count >= 2 else { return nil }
        return cells
    }

    private static func splitTableCells(in line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var index = line.startIndex

        while index < line.endIndex {
            let markerLength = backtickRunLength(in: line, from: index)
            if markerLength > 0,
               !isEscapedMarkdownCharacter(in: line, at: index) {
                let contentStart = line.index(index, offsetBy: markerLength)
                if let closingIndex = matchingBacktickRun(in: line, markerLength: markerLength, from: contentStart),
                   closingIndex > contentStart {
                    let codeSpanEnd = line.index(closingIndex, offsetBy: markerLength)
                    current += String(line[index..<codeSpanEnd])
                    index = codeSpanEnd
                    continue
                }
            }

            if line[index] == "|",
               !isEscapedMarkdownCharacter(in: line, at: index) {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(line[index])
            }
            index = line.index(after: index)
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isEscapedMarkdownCharacter(in line: String, at index: String.Index) -> Bool {
        var backslashCount = 0
        var cursor = index

        while cursor > line.startIndex {
            cursor = line.index(before: cursor)
            if line[cursor] == "\\" {
                backslashCount += 1
            } else {
                break
            }
        }

        return backslashCount % 2 == 1
    }

    private static func isTableSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy(isTableSeparatorCell)
    }

    private static func isTableSeparatorCell(_ cell: String) -> Bool {
        var text = cell.trimmingCharacters(in: .whitespaces)
        if text.first == ":" {
            text.removeFirst()
        }
        if text.last == ":" {
            text.removeLast()
        }

        return text.count >= 3 && text.allSatisfy { $0 == "-" }
    }

    private static func normalizedTableRow(_ cells: [String], columnCount: Int) -> [String] {
        var normalized = Array(cells.prefix(columnCount)).map(cleanInline)
        if normalized.count < columnCount {
            normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
        }
        return normalized
    }

    private static func tableText(headers: [String], rows: [[String]]) -> String {
        ([headers] + rows)
            .map { $0.joined(separator: " | ") }
            .joined(separator: "\n")
    }

    private static func indentedCodeLine(from rawLine: String) -> String? {
        if rawLine.hasPrefix("    ") {
            return String(rawLine.dropFirst(4))
        }
        if rawLine.hasPrefix("\t") {
            return String(rawLine.dropFirst())
        }
        return nil
    }

    private static func normalizedCodeBlockText(_ lines: [String]) -> String {
        var normalized = lines
        while normalized.last == "" {
            normalized.removeLast()
        }
        return normalized.joined(separator: "\n")
    }

    private static func htmlCommentBlock(_ rawLine: String) -> Bool? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("<!--") else { return nil }
        return !closesHTMLCommentBlock(line)
    }

    private static func closesHTMLCommentBlock(_ rawLine: String) -> Bool {
        rawLine.contains("-->")
    }

    private static func linkReferenceDefinition(in rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("[") else { return false }

        let labelStart = line.index(after: line.startIndex)
        guard labelStart < line.endIndex,
              let labelEnd = closingBracket(in: line, from: labelStart),
              labelEnd > labelStart else { return false }

        let colonIndex = line.index(after: labelEnd)
        guard colonIndex < line.endIndex, line[colonIndex] == ":" else { return false }

        let destinationStart = line.index(after: colonIndex)
        let destination = line[destinationStart...].trimmingCharacters(in: .whitespaces)
        return !destination.isEmpty
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

    private static func replaceReferenceImages(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            if let replacement = markdownReferenceImageReplacement(in: text, at: index) {
                result += replacement.text
                index = replacement.endIndex
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }

        return result
    }

    private static func replaceReferenceLinks(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            if let replacement = markdownReferenceLinkReplacement(in: text, at: index) {
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
        let destination = normalizedLinkDestination(String(text[destinationStart..<destinationEnd]))
        let replacement = label.isEmpty ? "(\(destination))" : "\(label) (\(destination))"
        return (replacement, text.index(after: destinationEnd))
    }

    private static func normalizedLinkDestination(_ rawDestination: String) -> String {
        var destination = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)

        if destination.first == "<" {
            let contentStart = destination.index(after: destination.startIndex)
            if let contentEnd = closingAngleLinkDestination(in: destination, from: contentStart) {
                let tailStart = destination.index(after: contentEnd)
                let tail = destination[tailStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                if tail.isEmpty || markdownLinkTitle(tail) {
                    return String(destination[contentStart..<contentEnd])
                }
            }
        }

        if let titleStart = markdownLinkTitleStart(in: destination) {
            let title = destination[titleStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || markdownLinkTitle(title) {
                destination = String(destination[..<titleStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return destination
    }

    private static func closingAngleLinkDestination(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == ">" {
                return index
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func markdownLinkTitleStart(in text: String) -> String.Index? {
        var index = text.startIndex
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
                if depth > 0 {
                    depth -= 1
                }
            } else if character.isWhitespace, depth == 0 {
                return index
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func markdownLinkTitle(_ text: String) -> Bool {
        guard let first = text.first else { return false }

        if first == "\"" || first == "'" {
            guard let closing = closingQuotedLinkTitle(in: text, quote: first) else { return false }
            return text.index(after: closing) == text.endIndex
        }

        if first == "(" {
            let contentStart = text.index(after: text.startIndex)
            guard let closing = closingParenthesis(in: text, from: contentStart) else { return false }
            return text.index(after: closing) == text.endIndex
        }

        return false
    }

    private static func closingQuotedLinkTitle(in text: String, quote: Character) -> String.Index? {
        var index = text.index(after: text.startIndex)
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == quote {
                return index
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func markdownReferenceImageReplacement(
        in text: String,
        at index: String.Index
    ) -> (text: String, endIndex: String.Index)? {
        guard text[index] == "!" else { return nil }

        let labelStart = text.index(after: index)
        guard labelStart < text.endIndex, text[labelStart] == "[" else { return nil }

        return markdownReferenceReplacement(in: text, labelStart: labelStart)
    }

    private static func markdownReferenceLinkReplacement(
        in text: String,
        at index: String.Index
    ) -> (text: String, endIndex: String.Index)? {
        guard text[index] == "[",
              !isImageLabelStart(in: text, at: index) else { return nil }

        return markdownReferenceReplacement(in: text, labelStart: index)
    }

    private static func markdownReferenceReplacement(
        in text: String,
        labelStart: String.Index
    ) -> (text: String, endIndex: String.Index)? {
        let labelContentStart = text.index(after: labelStart)
        guard let labelEnd = closingBracket(in: text, from: labelContentStart) else { return nil }

        let referenceStart = text.index(after: labelEnd)
        guard referenceStart < text.endIndex, text[referenceStart] == "[" else { return nil }

        let referenceContentStart = text.index(after: referenceStart)
        guard let referenceEnd = closingBracket(in: text, from: referenceContentStart) else {
            return nil
        }

        let label = String(text[labelContentStart..<labelEnd])
        guard !label.isEmpty else { return nil }
        return (label, text.index(after: referenceEnd))
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
        var depth = 0
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                if depth == 0 {
                    return index
                }
                depth -= 1
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

        var quotedAttribute: Character?
        while cursor < text.endIndex {
            let character = text[cursor]
            if let quote = quotedAttribute {
                if character == quote {
                    quotedAttribute = nil
                }
            } else if character == "\"" || character == "'" {
                quotedAttribute = character
            } else if character == "<" {
                return nil
            } else if character == ">" {
                return (text.index(after: cursor), inlineHTMLSpaceTags.contains(tagName))
            }
            cursor = text.index(after: cursor)
        }

        return nil
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
        case "ensp":
            return "\u{2002}"
        case "emsp":
            return "\u{2003}"
        case "thinsp":
            return "\u{2009}"
        case "copy":
            return "\u{00A9}"
        case "reg":
            return "\u{00AE}"
        case "deg":
            return "\u{00B0}"
        case "plusmn":
            return "\u{00B1}"
        case "middot":
            return "\u{00B7}"
        case "times":
            return "\u{00D7}"
        case "divide":
            return "\u{00F7}"
        case "trade":
            return "\u{2122}"
        case "ndash":
            return "\u{2013}"
        case "mdash":
            return "\u{2014}"
        case "bull":
            return "\u{2022}"
        case "larr":
            return "\u{2190}"
        case "rarr":
            return "\u{2192}"
        case "minus":
            return "\u{2212}"
        case "ne":
            return "\u{2260}"
        case "le":
            return "\u{2264}"
        case "ge":
            return "\u{2265}"
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

    private static func removePairedCodeSpanMarkers(in text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let markerLength = backtickRunLength(in: text, from: index)
            if markerLength > 0 {
                let contentStart = text.index(index, offsetBy: markerLength)
                if let closingIndex = matchingBacktickRun(in: text, markerLength: markerLength, from: contentStart),
                   closingIndex > contentStart {
                    let content = String(text[contentStart..<closingIndex])
                    result += protectedCodeSpanContent(normalizedCodeSpanContent(content))
                    index = text.index(closingIndex, offsetBy: markerLength)
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }

    private static func backtickRunLength(in text: String, from start: String.Index) -> Int {
        guard start < text.endIndex, text[start] == "`" else { return 0 }

        var length = 0
        var index = start
        while index < text.endIndex, text[index] == "`" {
            length += 1
            index = text.index(after: index)
        }
        return length
    }

    private static func matchingBacktickRun(
        in text: String,
        markerLength: Int,
        from start: String.Index
    ) -> String.Index? {
        var index = start
        while index < text.endIndex {
            if backtickRunLength(in: text, from: index) == markerLength {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func normalizedCodeSpanContent(_ text: String) -> String {
        guard let first = text.first,
              let last = text.last,
              first.isWhitespace,
              last.isWhitespace,
              text.contains(where: { !$0.isWhitespace }) else {
            return text
        }

        return String(text.dropFirst().dropLast())
    }

    private static func protectedCodeSpanContent(_ text: String) -> String {
        var result = String.UnicodeScalarView()

        for scalar in text.unicodeScalars {
            if let protected = protectedCodeSpanScalar(scalar) {
                result.append(protected)
            } else {
                result.append(scalar)
            }
        }

        return String(result)
    }

    private static func protectedCodeSpanScalar(_ scalar: UnicodeScalar) -> UnicodeScalar? {
        guard scalar.value < 128,
              (scalar.value == 38 || isEscapableMarkdownPunctuation(scalar)),
              let protected = UnicodeScalar(escapedMarkdownScalarBase + scalar.value) else {
            return nil
        }

        return protected
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

    private static func taskListItem(in text: String) -> (state: MarkdownTaskState, text: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3,
              trimmed.first == "[" else {
            return nil
        }

        let markerIndex = trimmed.index(after: trimmed.startIndex)
        let closingIndex = trimmed.index(after: markerIndex)
        guard isTaskListMarker(trimmed[markerIndex]),
              trimmed[closingIndex] == "]" else {
            return nil
        }

        let afterClosingIndex = trimmed.index(after: closingIndex)
        guard afterClosingIndex == trimmed.endIndex || trimmed[afterClosingIndex].isWhitespace else {
            return nil
        }

        let remainder = String(trimmed[afterClosingIndex...]).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }
        let state: MarkdownTaskState = trimmed[markerIndex] == " " ? .unchecked : .checked
        return (state, remainder)
    }

    private static func isTaskListMarker(_ character: Character) -> Bool {
        character == " " || character == "x" || character == "X"
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

    private static func quoteBlock(startingAt startIndex: Int, in lines: [String]) -> (text: String, endIndex: Int)? {
        let line = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard let firstQuoteLine = quote(in: line) else { return nil }

        var quoteLines = [cleanInline(firstQuoteLine)]
        var lineIndex = startIndex + 1
        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let nextLine = rawLine.trimmingCharacters(in: .whitespaces)
            if nextLine.first == ">" {
                let content = String(nextLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                quoteLines.append(cleanInline(content))
            } else if lazyQuoteContinuationLine(rawLine) {
                quoteLines.append(cleanInline(normalizedParagraphLineText(rawLine)))
            } else {
                break
            }
            lineIndex += 1
        }

        return (quoteLines.joined(separator: "\n"), lineIndex)
    }

    private static func lazyQuoteContinuationLine(_ rawLine: String) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return false }
        if heading(in: line) != nil { return false }
        if thematicBreak(in: line) { return false }
        if unorderedListItem(in: line) != nil { return false }
        if orderedListItem(in: line) != nil { return false }
        if MarkdownFence(openingLine: rawLine) != nil { return false }
        if htmlCommentBlock(rawLine) != nil { return false }
        if linkReferenceDefinition(in: rawLine) { return false }
        return true
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
                listMarkerView(marker: "•", taskState: block.taskState)
                listText(block.text)
            }
        case .orderedListItem(let number):
            HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownListItemSpacing)) {
                listMarkerView(marker: "\(number).", taskState: block.taskState, reservesNumberWidth: true)
                listText(block.text)
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
        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
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

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableRow(cells: headers, isHeader: true)

            Rectangle()
                .fill(QuillColors.quoteRule)
                .frame(height: CGFloat(EnchantedVisualMetrics.markdownQuoteRuleWidth))

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                tableRow(cells: row, isHeader: false)
            }
        }
        .padding(CGFloat(EnchantedVisualMetrics.markdownCodeBlockPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillColors.codeBlock)
        .cornerRadius(CGFloat(EnchantedVisualMetrics.markdownCodeBlockRadius))
    }

    private func tableRow(cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.markdownListItemSpacing)) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell.isEmpty ? " " : cell)
                    .font(.system(
                        size: CGFloat(EnchantedTypography.messageBodyFontSize),
                        weight: isHeader
                            ? enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)
                            : .regular
                    ))
                    .foregroundColor(isHeader ? QuillColors.ink : foregroundColor)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, CGFloat(EnchantedVisualMetrics.markdownQuoteVerticalPadding))
    }

    @ViewBuilder
    private func listMarkerView(marker: String, taskState: MarkdownTaskState?, reservesNumberWidth: Bool = false) -> some View {
        if let taskState {
            Image(systemName: taskState == .checked ? "checkmark.square.fill" : "square")
                .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)))
                .foregroundColor(taskState == .checked ? QuillColors.primary : QuillColors.muted)
                .frame(width: CGFloat(EnchantedVisualMetrics.markdownNumberWidth), alignment: .trailing)
                .accessibilityLabel(taskState == .checked ? "Completed task" : "Incomplete task")
        } else if reservesNumberWidth {
            Text(marker)
                .font(.system(size: CGFloat(EnchantedTypography.markdownHeadingFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)))
                .foregroundColor(QuillColors.primary)
                .frame(width: CGFloat(EnchantedVisualMetrics.markdownNumberWidth), alignment: .trailing)
        } else {
            Text(marker)
                .font(.system(size: CGFloat(EnchantedTypography.markdownHeadingFontSize), weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)))
                .foregroundColor(QuillColors.primary)
        }
    }

    private func listText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize)))
            .foregroundColor(foregroundColor)
            .lineSpacing(3)
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
