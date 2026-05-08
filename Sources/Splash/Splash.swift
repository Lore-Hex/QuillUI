import Foundation
import SwiftUI

public struct SplashColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public extension Color {
    init(_ color: SplashColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

public struct Font: Equatable, Sendable {
    public var size: Double

    public init(size: Double) {
        self.size = size
    }
}

public enum TokenType: String, CaseIterable, Hashable, Sendable {
    case keyword
    case string
    case type
    case call
    case number
    case comment
    case property
    case dotAccess
    case preprocessing
    case plain
}

public struct Theme: Sendable {
    public var font: Font
    public var plainTextColor: SplashColor
    public var tokenColors: [TokenType: SplashColor]

    public init(
        font: Font = Font(size: 14),
        plainTextColor: SplashColor = SplashColor(red: 0.13, green: 0.13, blue: 0.14),
        tokenColors: [TokenType: SplashColor] = [:]
    ) {
        self.font = font
        self.plainTextColor = plainTextColor
        self.tokenColors = tokenColors
    }

    public static func sunset(withFont font: Font) -> Theme {
        Theme(
            font: font,
            plainTextColor: SplashColor(red: 0.13, green: 0.13, blue: 0.14),
            tokenColors: [
                .keyword: SplashColor(red: 0.48, green: 0.35, blue: 0.82),
                .string: SplashColor(red: 0.69, green: 0.22, blue: 0.31),
                .type: SplashColor(red: 0.19, green: 0.47, blue: 0.70),
                .number: SplashColor(red: 0.74, green: 0.39, blue: 0.12),
                .comment: SplashColor(red: 0.42, green: 0.43, blue: 0.47)
            ]
        )
    }

    public static func wwdc17(withFont font: Font) -> Theme {
        Theme(
            font: font,
            plainTextColor: SplashColor(red: 0.90, green: 0.91, blue: 0.94),
            tokenColors: [
                .keyword: SplashColor(red: 0.88, green: 0.53, blue: 0.98),
                .string: SplashColor(red: 0.98, green: 0.75, blue: 0.46),
                .type: SplashColor(red: 0.53, green: 0.80, blue: 1.0),
                .number: SplashColor(red: 0.99, green: 0.60, blue: 0.40),
                .comment: SplashColor(red: 0.54, green: 0.57, blue: 0.62)
            ]
        )
    }
}

public protocol OutputBuilder {
    associatedtype Output

    mutating func addToken(_ token: String, ofType type: TokenType)
    mutating func addPlainText(_ text: String)
    mutating func addWhitespace(_ whitespace: String)
    func build() -> Output
}

public protocol OutputFormat {
    associatedtype Builder: OutputBuilder

    func makeBuilder() -> Builder
}

public struct SyntaxHighlighter<Format: OutputFormat> {
    private let format: Format

    public init(format: Format) {
        self.format = format
    }

    public func highlight(_ content: String) -> Format.Builder.Output {
        var builder = format.makeBuilder()
        var current = ""

        func flushToken() {
            guard !current.isEmpty else { return }
            builder.addToken(current, ofType: Self.classify(current))
            current.removeAll(keepingCapacity: true)
        }

        for scalar in content.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flushToken()
                builder.addWhitespace(String(scalar))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        flushToken()

        return builder.build()
    }

    private static func classify(_ token: String) -> TokenType {
        if token.hasPrefix("//") || token.hasPrefix("#") { return .comment }
        if token.hasPrefix("\"") || token.hasPrefix("'") { return .string }
        if Double(token.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))) != nil { return .number }
        if ["class", "struct", "enum", "func", "let", "var", "if", "else", "for", "while", "return", "import"].contains(token) {
            return .keyword
        }
        if token.first?.isUppercase == true { return .type }
        return .plain
    }
}
