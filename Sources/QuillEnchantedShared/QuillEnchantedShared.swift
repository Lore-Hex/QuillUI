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
    public static let sidebarPadding = 18
    public static let sidebarSpacing = 14
    public static let sidebarTitleSpacing = 4
    public static let sidebarControlGroupSpacing = 7
    public static let statusRowSpacing = 8
    public static let statusTextWidth = 240
    public static let statusDotSize = 9
    public static let statusDotRadius = 9
    public static let headerTitleWidth = 560
    public static let headerSpacing = 12
    public static let headerTitleSpacing = 4
    public static let headerPadding = 18
    public static let contentPadding = 22
    public static let loadingRowSpacing = 8
    public static let loadingTopPadding = 8
    public static let promptButtonWidth = 620
    public static let promptButtonMinHeight = 48
    public static let emptyStateMaxWidth = 680
    public static let emptyStatePadding = 26
    public static let emptyStateSpacing = 18
    public static let emptyStateHeaderSpacing = 8
    public static let promptListSpacing = 10
    public static let promptButtonIconSpacing = 10
    public static let promptButtonTextWidthInset = 80
    public static let promptButtonPadding = 12
    public static let promptButtonRadius = 8
    public static let primaryButtonPadding = 12
    public static let primaryButtonIconSpacing = 8
    public static let primaryButtonVerticalPadding = primaryButtonPadding
    public static let primaryButtonHorizontalPadding = primaryButtonPadding
    public static let primaryButtonRadius = 8
    public static let actionButtonIconSpacing = 6
    public static let secondaryButtonVerticalPadding = 7
    public static let secondaryButtonHorizontalPadding = 10
    public static let secondaryButtonRadius = 7
    public static let controlPadding = 7
    public static let controlRadius = 7
    public static let dropTargetPadding = 8
    public static let dropTargetRadius = 8
    public static let conversationListSpacing = 8
    public static let conversationActionsSpacing = 8
    public static let conversationRowPadding = 11
    public static let conversationRowSpacing = 5
    public static let conversationRowRadius = 8
    public static let conversationListItemRadius = 8
    public static let conversationListItemVerticalMargin = 2
    public static let conversationListItemPadding = 8
    public static let emptyHistoryPadding = 12
    public static let emptyHistorySpacing = 8
    public static let emptyHistoryRadius = 8
    public static let attachmentChipPadding = 8
    public static let attachmentChipSpacing = 8
    public static let attachmentChipTextSpacing = 2
    public static let attachmentChipRadius = 8
    public static let attachmentRemoveButtonWidth = 28
    public static let chipRemoveButtonVerticalPadding = 2
    public static let chipRemoveButtonHorizontalPadding = 6
    public static let attachmentTraySpacing = 7
    public static let attachmentTrayChipSpacing = 8
    public static let attachmentInputHorizontalPadding = 10
    public static let attachmentInputVerticalPadding = 7
    public static let attachmentInputSpacing = 8
    public static let messageMaxWidth = 680
    public static let messageSpacing = 14
    public static let messageBubbleRowSpacing = 10
    public static let messageBubblePadding = 13
    public static let messageBubbleSpacing = 7
    public static let messageBubbleRadius = 10
    public static let markdownBlockSpacing = 9
    public static let markdownListItemSpacing = 8
    public static let markdownNumberWidth = 26
    public static let markdownQuoteSpacing = 9
    public static let markdownQuoteRuleWidth = 3
    public static let markdownQuoteRuleRadius = 1
    public static let markdownQuoteVerticalPadding = 2
    public static let markdownCodeBlockSpacing = 7
    public static let markdownCodeBlockPadding = 10
    public static let markdownCodeBlockRadius = 7
    public static let composerMinWidth = 620
    public static let composerMaxWidth = 840
    public static let composerPadding = 18
    public static let composerSpacing = 10
    public static let composerEditorRadius = 8
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
