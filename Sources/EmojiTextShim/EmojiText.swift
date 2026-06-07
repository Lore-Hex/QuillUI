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
