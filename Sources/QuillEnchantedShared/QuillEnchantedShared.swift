import Foundation

public enum EnchantedPromptCatalog {
    public static let emptyConversationTitles = [
        "Summarize the tradeoffs in moving a SwiftUI app to Linux.",
        "Draft a private local assistant workflow for a small team.",
        "Explain how Ollama model selection should work in a desktop app.",
        "Write a checklist for shipping an open-source Swift package."
    ]
}

public enum EnchantedVisualMetrics {
    public static let minimumWindowWidth = 980
    public static let minimumWindowHeight = 680
    public static let defaultWindowWidth = 1180
    public static let defaultWindowHeight = 760
    public static let sidebarWidth = 300
    public static let sidebarIdealWidth = 330
    public static let sidebarMaxWidth = 360
    public static let detailWidth = defaultWindowWidth - sidebarWidth
    public static let headerTitleWidth = 560
    public static let promptButtonWidth = 620
    public static let emptyStateMaxWidth = 680
    public static let emptyStatePadding = 26
    public static let emptyStateSpacing = 18
    public static let emptyStateHeaderSpacing = 8
    public static let promptListSpacing = 10
    public static let promptButtonIconSpacing = 10
    public static let promptButtonTextWidthInset = 80
    public static let promptButtonPadding = 12
    public static let promptButtonRadius = 8
    public static let messageMaxWidth = 680
    public static let composerMinWidth = 620
    public static let composerMaxWidth = 840
    public static let composerPadding = 18
    public static let composerSpacing = 10
    public static let promptRowSpacing = 12
    public static let composerSendButtonMinWidth = 86
    public static let composerMinHeight = 74
    public static let composerMaxHeight = 120
}

public enum EnchantedTypography {
    public static let rootFontSize = 14
    public static let appTitleFontSize = 26
    public static let appTitleFontWeight = 700
    public static let captionFontSize = 12
    public static let sectionTitleFontSize = 15
    public static let sectionTitleFontWeight = 700
    public static let currentTitleFontSize = 20
    public static let currentTitleFontWeight = 650
    public static let messageBodyFontSize = 14
    public static let markdownHeading1FontSize = 17
    public static let markdownHeading2FontSize = 15
    public static let markdownHeadingFontSize = 14
    public static let markdownHeadingFontWeight = 650
    public static let markdownCodeLanguageFontSize = 11
    public static let markdownCodeFontSize = 13
    public static let attachmentNameFontSize = 12
    public static let attachmentSizeFontSize = 11
    public static let conversationTitleFontSize = 15
    public static let conversationTitleFontWeight = 700
    public static let conversationPreviewFontSize = 12
    public static let warningTextFontSize = 12
    public static let chipRemoveButtonFontWeight = 700
}
