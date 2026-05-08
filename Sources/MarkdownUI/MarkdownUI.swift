import Foundation
import SwiftUI

public struct Markdown: View {
    public var content: String

    public init(_ content: String) {
        self.content = content
    }

    public var body: some View {
        Text(Self.plainText(from: content))
            .fixedSize(horizontal: false, vertical: true)
    }

    public static func plainText(from markdown: String) -> String {
        var output: [String] = []
        var inFence = false

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if !inFence {
                line = line.replacingOccurrences(
                    of: #"!\[([^\]]*)\]\([^)]+\)"#,
                    with: "$1",
                    options: .regularExpression
                )
                line = line.replacingOccurrences(
                    of: #"\[([^\]]+)\]\(([^)]+)\)"#,
                    with: "$1 ($2)",
                    options: .regularExpression
                )
                line = line.replacingOccurrences(
                    of: #"^#{1,6}\s+"#,
                    with: "",
                    options: .regularExpression
                )
                line = line.replacingOccurrences(
                    of: #"^>\s?"#,
                    with: "",
                    options: .regularExpression
                )
                line = line.replacingOccurrences(
                    of: #"^[-*+]\s+"#,
                    with: "• ",
                    options: .regularExpression
                )
                line = line.replacingOccurrences(
                    of: #"^\d+\.\s+"#,
                    with: "",
                    options: .regularExpression
                )
                for marker in ["**", "__", "`", "~~"] {
                    line = line.replacingOccurrences(of: marker, with: "")
                }
            }
            output.append(line)
        }

        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
public func FontWeight(_ weight: SwiftUI.FontWeight) {}
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
