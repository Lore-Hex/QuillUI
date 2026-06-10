import QuillFoundation
import SwiftUI

public protocol CustomEmoji: Sendable {
    var shortcode: String { get }
    var url: URL { get }
}

public struct RemoteEmoji: CustomEmoji {
    public let shortcode: String
    public let url: URL
    
    public init(shortcode: String, url: URL) {
        self.shortcode = shortcode
        self.url = url
    }
}

/// A functional EmojiText shim that renders custom emojis on Linux using a baseline alignment trick.
public struct EmojiText: View {
    private let markdown: String
    private let emojis: [any CustomEmoji]
    private let append: (() -> Text)?
    
    public init(markdown: String, emojis: [any CustomEmoji]) {
        self.markdown = HTMLText.plainText(fromMarkdown: markdown)
        self.emojis = emojis
        self.append = nil
    }
    
    public init(verbatim: String, emojis: [any CustomEmoji]) {
        self.markdown = verbatim
        self.emojis = emojis
        self.append = nil
    }
    
    private init(markdown: String, emojis: [any CustomEmoji], append: (() -> Text)?) {
        self.markdown = markdown
        self.emojis = emojis
        self.append = append
    }
    
    public var body: some View {
        let parts = parseEmoji(text: markdown, emojis: emojis)
        
        // On Linux we use an Flow-like HStack to simulate text with inline images
        // Since Pango/GTK in SwiftOpenUI doesn't support AttributedString images yet.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(0..<parts.count, id: \.self) { index in
                switch parts[index] {
                case .text(let s):
                    Text(s)
                case .emoji(let url):
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 20, height: 20)
                    .baselineOffset(-4)
                }
            }
            if let append = append {
                append()
            }
        }
    }
    
    public func animated(_ animated: Bool) -> Self { self }
    public func lineLimit(_ limit: Int?) -> Self { self }
    public func append(text: @escaping () -> Text) -> EmojiText {
        EmojiText(markdown: markdown, emojis: emojis, append: text)
    }
    
    private enum Part {
        case text(String)
        case emoji(URL)
    }
    
    private func parseEmoji(text: String, emojis: [any CustomEmoji]) -> [Part] {
        var result: [Part] = []
        var currentText = text
        
        // Simple regex-less parser for :shortcode:
        while let startRange = currentText.range(of: ":") {
            let pre = String(currentText[..<startRange.lowerBound])
            if !pre.isEmpty { result.append(.text(pre)) }
            
            let remainder = currentText[startRange.upperBound...]
            if let endRange = remainder.range(of: ":") {
                let code = String(remainder[..<endRange.lowerBound])
                if let emoji = emojis.first(where: { $0.shortcode == code }) {
                    result.append(.emoji(emoji.url))
                } else {
                    result.append(.text(":\(code):"))
                }
                currentText = String(remainder[endRange.upperBound...])
            } else {
                result.append(.text(":"))
                currentText = String(remainder)
            }
        }
        
        if !currentText.isEmpty { result.append(.text(currentText)) }
        return result
    }
}

public extension View {
    var emojiText: EmojiTextViewProxy<Self> {
        EmojiTextViewProxy(base: self)
    }

    func emojiText(emojis: [any CustomEmoji]) -> some View { self }
}

public struct EmojiTextViewProxy<Base: View>: View {
    public let base: Base

    public var body: some View { base }

    public func size(_ size: Double) -> Base {
        _ = size
        return base
    }

    public func baselineOffset(_ offset: Double) -> Base {
        _ = offset
        return base
    }
}
