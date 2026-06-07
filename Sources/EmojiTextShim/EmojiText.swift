// Minimal Linux shim for divadretlaw/EmojiText — DesignSystem's EmojiTextApp wrapper.
#if os(Linux)
import Foundation
import SwiftUI

public struct RemoteEmoji {
    public let shortcode: String
    public let url: URL
    public init(shortcode: String, url: URL) { self.shortcode = shortcode; self.url = url }
}

// On Linux, render the markdown as plain styled Text (no remote-emoji image
// substitution / animation). The modifiers return Self so the chain compiles.
public struct EmojiText: View {
    private let content: String
    public init(markdown: String, emojis: [any CustomEmoji]) { self.content = markdown }
    public func animated(_ animated: Bool) -> EmojiText { self }
    public func append(text: @escaping @Sendable () -> Text) -> EmojiText { self }
    public var body: some View { Text(content) }
}

// EmojiText library protocol for custom (server) emojis. RemoteEmoji conforms.
public protocol CustomEmoji {
    var shortcode: String { get }
    var url: URL { get }
}
extension RemoteEmoji: CustomEmoji {}

#endif

import SwiftOpenUI

// EmojiText library Text.emojiText.size(_:).baselineOffset(_:) chain (sizes inline
// custom emoji to the surrounding font). No-op on Linux; returns Text to chain.
public struct EmojiTextConfiguration<Content: View> {
    let content: Content
    public func size(_ size: CGFloat) -> Content { content }
    public func baselineOffset(_ offset: CGFloat) -> Content { content }
}
public extension View {
    var emojiText: EmojiTextConfiguration<Self> { EmojiTextConfiguration(content: self) }
}
