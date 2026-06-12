#if os(Linux)
import CQuillQt6WidgetsShim
import QuillEnchantedShared
import QuillQtNativeRuntimeSupport

public struct QuillGenericQtAppSnapshot: Codable, Sendable {
    public static let genericSelectedIndexEnvironmentKey = "QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"
    public static let defaultSelectedIndexEnvironmentKeys = [genericSelectedIndexEnvironmentKey]

    public var windowTitle: String
    public var minimumWidth: Int
    public var minimumHeight: Int
    public var defaultWidth: Int
    public var defaultHeight: Int
    public var sidebarWidth: Int
    public var detailWidth: Int
    public var sidebarTitle: String
    public var sidebarSubtitle: String
    public var primaryActionTitle: String
    public var secondaryActionTitle: String
    public var listTitle: String
    public var status: String
    public var selectedIndex: Int
    public var selectedIndexEnvironmentKeys: [String]
    public var detailTitle: String
    public var detailSubtitle: String
    public var messagesTitle: String
    public var items: [Item]
    public var sections: [Section]
    public var messages: [Message]
    public var presentation: Presentation
    public var emptyStateTitle: String
    public var emptyStateSubtitle: String
    public var prompts: [Prompt]
    public var bottomNavigation: [NavigationAction]
    public var composerPlaceholder: String
    public var noticeTitle: String
    public var noticeBody: String
    public var noticeActionTitle: String
    public var style: Style

    public enum Presentation: String, Codable, Sendable {
        case standard
        case chat
    }

    public struct Item: Codable, Sendable {
        public var title: String
        public var subtitle: String
        public var badge: String
        public var height: Int
        public var detailTitle: String?
        public var detailSubtitle: String?
        public var sections: [Section]?
        public var messages: [Message]?

        public init(
            title: String,
            subtitle: String,
            badge: String = "",
            height: Int = 76,
            detailTitle: String? = nil,
            detailSubtitle: String? = nil,
            sections: [Section]? = nil,
            messages: [Message]? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.height = height
            self.detailTitle = detailTitle
            self.detailSubtitle = detailSubtitle
            self.sections = sections
            self.messages = messages
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case subtitle
            case badge
            case height
            case detailTitle
            case detailSubtitle
            case sections
            case messages
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.init(
                title: try container.decode(String.self, forKey: .title),
                subtitle: try container.decode(String.self, forKey: .subtitle),
                badge: try container.decodeIfPresent(String.self, forKey: .badge) ?? "",
                height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 76,
                detailTitle: try container.decodeIfPresent(String.self, forKey: .detailTitle),
                detailSubtitle: try container.decodeIfPresent(String.self, forKey: .detailSubtitle),
                sections: try container.decodeIfPresent([Section].self, forKey: .sections),
                messages: try container.decodeIfPresent([Message].self, forKey: .messages)
            )
        }
    }

    public struct Section: Codable, Sendable {
        public var title: String
        public var body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public struct Message: Codable, Sendable {
        public var sender: String
        public var body: String

        public init(sender: String, body: String) {
            self.sender = sender
            self.body = body
        }
    }

    public struct Prompt: Codable, Sendable {
        public var title: String
        public var systemImage: String

        public init(title: String, systemImage: String = "") {
            self.title = title
            self.systemImage = systemImage
        }

        public init(_ prompt: EnchantedPrompt) {
            self.init(title: prompt.title, systemImage: prompt.systemImage)
        }
    }

    public struct NavigationAction: Codable, Sendable {
        public var title: String
        public var systemImage: String

        public init(title: String, systemImage: String = "") {
            self.title = title
            self.systemImage = systemImage
        }
    }

    public struct Style: Codable, Sendable {
        public var canvasColor: String
        public var sidebarColor: String
        public var cardColor: String
        public var activeCardColor: String
        public var headerColor: String
        public var promptCardColor: String
        public var noticeColor: String
        public var primaryColor: String
        public var inkColor: String
        public var mutedColor: String
        public var badgeColor: String
        public var selectedMutedColor: String
        public var borderColor: String
        public var selectedBorderColor: String
        public var dividerColor: String
        public var controlBorderColor: String
        public var rootFontSize: Int
        public var appTitleFontSize: Int
        public var appTitleFontWeight: Int
        public var captionFontSize: Int
        public var sectionTitleFontSize: Int
        public var sectionTitleFontWeight: Int
        public var currentTitleFontSize: Int
        public var currentTitleFontWeight: Int
        public var emptyStateWordmarkFontSize: Int
        public var emptyStateWordmarkFontWeight: Int
        public var messageBodyFontSize: Int
        public var conversationTitleFontSize: Int
        public var conversationTitleFontWeight: Int
        public var headerHeight: Int
        public var headerPadding: Int
        public var headerSpacing: Int
        public var headerTitleSpacing: Int
        public var contentPadding: Int
        public var emptyStateMaxWidth: Int
        public var emptyStatePadding: Int
        public var emptyStateSpacing: Int
        public var emptyStateHeaderSpacing: Int
        public var promptGridColumns: Int
        public var promptGridSpacing: Int
        public var promptCardWidth: Int
        public var promptCardHeight: Int
        public var promptGridWidth: Int
        public var promptButtonPadding: Int
        public var promptButtonRadius: Int
        public var sidebarPadding: Int
        public var sidebarSpacing: Int
        public var sidebarActionSpacing: Int
        public var primaryButtonMinHeight: Int
        public var primaryButtonVerticalPadding: Int
        public var primaryButtonHorizontalPadding: Int
        public var primaryButtonRadius: Int
        public var secondaryButtonVerticalPadding: Int
        public var secondaryButtonHorizontalPadding: Int
        public var secondaryButtonRadius: Int
        public var listSpacing: Int
        public var listItemRadius: Int
        public var listItemVerticalMargin: Int
        public var listItemPadding: Int
        public var itemRowHorizontalPadding: Int
        public var itemRowVerticalPadding: Int
        public var itemRowSpacing: Int
        public var cardRadius: Int
        public var cardPaddingHorizontal: Int
        public var cardPaddingVertical: Int
        public var cardSpacing: Int
        public var activeCardRadius: Int
        public var messageCardRadius: Int
        public var messageCardPaddingHorizontal: Int
        public var messageCardPaddingVertical: Int
        public var messageCardSpacing: Int
        public var composerMinWidth: Int
        public var composerMaxWidth: Int
        public var composerPadding: Int
        public var composerSpacing: Int
        public var promptRowSpacing: Int
        public var composerMinHeight: Int
        public var composerMaxHeight: Int
        public var composerEditorRadius: Int
        public var composerSendButtonMinWidth: Int
        public var detailPaddingHorizontal: Int
        public var detailPaddingVertical: Int
        public var detailSpacing: Int
        public var detailContentSpacing: Int

        public static let desktop = Style(
            canvasColor: "#F7F8F4",
            sidebarColor: "#EEF2EA",
            cardColor: "#FFFFFF",
            activeCardColor: "#E7F0FA",
            headerColor: "#F7F8F4",
            promptCardColor: "#FFFFFF",
            noticeColor: "#F8D7DA",
            primaryColor: "#2E5B78",
            inkColor: "#182027",
            mutedColor: "#65707A",
            badgeColor: "#295A7A",
            selectedMutedColor: "#DDEBFA",
            borderColor: "#E0E4DC",
            selectedBorderColor: "#CBDDEB",
            dividerColor: "#D8DDD4",
            controlBorderColor: "#CDD5CA",
            rootFontSize: EnchantedTypography.rootFontSize,
            appTitleFontSize: EnchantedTypography.appTitleFontSize,
            appTitleFontWeight: EnchantedTypography.appTitleFontWeight,
            captionFontSize: EnchantedTypography.captionFontSize,
            sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize,
            sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight,
            currentTitleFontSize: EnchantedTypography.currentTitleFontSize,
            currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight,
            emptyStateWordmarkFontSize: EnchantedTypography.emptyStateWordmarkFontSize,
            emptyStateWordmarkFontWeight: EnchantedTypography.emptyStateWordmarkFontWeight,
            messageBodyFontSize: EnchantedTypography.messageBodyFontSize,
            conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize,
            conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight,
            headerHeight: 76,
            headerPadding: 18,
            headerSpacing: 12,
            headerTitleSpacing: 4,
            contentPadding: 22,
            emptyStateMaxWidth: 760,
            emptyStatePadding: 26,
            emptyStateSpacing: 18,
            emptyStateHeaderSpacing: 8,
            promptGridColumns: 4,
            promptGridSpacing: 15,
            promptCardWidth: 160,
            promptCardHeight: 128,
            promptGridWidth: 685,
            promptButtonPadding: 12,
            promptButtonRadius: 8,
            sidebarPadding: 18,
            sidebarSpacing: 12,
            sidebarActionSpacing: 8,
            primaryButtonMinHeight: 36,
            primaryButtonVerticalPadding: 8,
            primaryButtonHorizontalPadding: 12,
            primaryButtonRadius: 8,
            secondaryButtonVerticalPadding: 7,
            secondaryButtonHorizontalPadding: 10,
            secondaryButtonRadius: 7,
            listSpacing: 4,
            listItemRadius: 8,
            listItemVerticalMargin: 2,
            listItemPadding: 8,
            itemRowHorizontalPadding: 2,
            itemRowVerticalPadding: 4,
            itemRowSpacing: 4,
            cardRadius: 8,
            cardPaddingHorizontal: 16,
            cardPaddingVertical: 14,
            cardSpacing: 7,
            activeCardRadius: 8,
            messageCardRadius: 8,
            messageCardPaddingHorizontal: 14,
            messageCardPaddingVertical: 10,
            messageCardSpacing: 6,
            composerMinWidth: 620,
            composerMaxWidth: 800,
            composerPadding: 18,
            composerSpacing: 10,
            promptRowSpacing: 12,
            composerMinHeight: 46,
            composerMaxHeight: 120,
            composerEditorRadius: 23,
            composerSendButtonMinWidth: 86,
            detailPaddingHorizontal: 24,
            detailPaddingVertical: 22,
            detailSpacing: 14,
            detailContentSpacing: 14
        )

        public static let enchanted = Style(
            canvasColor: EnchantedPalette.canvasColor,
            sidebarColor: EnchantedPalette.sidebarColor,
            cardColor: EnchantedPalette.cardColor,
            activeCardColor: EnchantedPalette.sidebarSelectedColor,
            headerColor: EnchantedPalette.headerColor,
            promptCardColor: EnchantedPalette.cardQuietColor,
            noticeColor: EnchantedPalette.noticeColor,
            primaryColor: EnchantedPalette.accentColor,
            inkColor: EnchantedPalette.textColor,
            mutedColor: EnchantedPalette.secondaryTextColor,
            badgeColor: EnchantedPalette.accentColor,
            selectedMutedColor: EnchantedPalette.sidebarSelectedColor,
            borderColor: EnchantedPalette.hairlineColor,
            selectedBorderColor: EnchantedPalette.controlBorderColor,
            dividerColor: EnchantedPalette.hairlineColor,
            controlBorderColor: EnchantedPalette.controlBorderColor,
            emptyStateWordmarkFontSize: EnchantedTypography.emptyStateWordmarkFontSize,
            emptyStateWordmarkFontWeight: EnchantedTypography.emptyStateWordmarkFontWeight,
            headerHeight: EnchantedVisualMetrics.headerHeight,
            headerPadding: EnchantedVisualMetrics.headerPadding,
            headerSpacing: EnchantedVisualMetrics.headerSpacing,
            headerTitleSpacing: EnchantedVisualMetrics.headerTitleSpacing,
            contentPadding: EnchantedVisualMetrics.contentPadding,
            emptyStateMaxWidth: EnchantedVisualMetrics.emptyStateMaxWidth,
            emptyStatePadding: EnchantedVisualMetrics.emptyStatePadding,
            emptyStateSpacing: EnchantedVisualMetrics.emptyStateSpacing,
            emptyStateHeaderSpacing: EnchantedVisualMetrics.emptyStateHeaderSpacing,
            promptGridColumns: EnchantedVisualMetrics.promptGridColumns,
            promptGridSpacing: EnchantedVisualMetrics.promptGridSpacing,
            promptCardWidth: EnchantedVisualMetrics.promptCardWidth,
            promptCardHeight: EnchantedVisualMetrics.promptCardHeight,
            promptGridWidth: EnchantedVisualMetrics.promptGridWidth,
            promptButtonPadding: EnchantedVisualMetrics.promptButtonPadding,
            promptButtonRadius: EnchantedVisualMetrics.promptButtonRadius,
            sidebarPadding: EnchantedVisualMetrics.sidebarPadding,
            sidebarSpacing: EnchantedVisualMetrics.sidebarSpacing,
            sidebarActionSpacing: EnchantedVisualMetrics.conversationActionsSpacing,
            primaryButtonMinHeight: EnchantedVisualMetrics.primaryButtonVerticalPadding * 2
                + EnchantedTypography.rootFontSize,
            primaryButtonVerticalPadding: EnchantedVisualMetrics.primaryButtonVerticalPadding,
            primaryButtonHorizontalPadding: EnchantedVisualMetrics.primaryButtonHorizontalPadding,
            primaryButtonRadius: EnchantedVisualMetrics.primaryButtonRadius,
            secondaryButtonVerticalPadding: EnchantedVisualMetrics.secondaryButtonVerticalPadding,
            secondaryButtonHorizontalPadding: EnchantedVisualMetrics.secondaryButtonHorizontalPadding,
            secondaryButtonRadius: EnchantedVisualMetrics.secondaryButtonRadius,
            listSpacing: EnchantedVisualMetrics.conversationListSpacing,
            listItemRadius: EnchantedVisualMetrics.conversationListItemRadius,
            listItemVerticalMargin: EnchantedVisualMetrics.conversationListItemVerticalMargin,
            listItemPadding: EnchantedVisualMetrics.conversationListItemPadding,
            itemRowHorizontalPadding: EnchantedVisualMetrics.conversationRowPadding,
            itemRowVerticalPadding: EnchantedVisualMetrics.conversationRowPadding,
            itemRowSpacing: EnchantedVisualMetrics.conversationRowSpacing,
            cardRadius: EnchantedVisualMetrics.emptyHistoryRadius,
            cardPaddingHorizontal: EnchantedVisualMetrics.emptyHistoryPadding,
            cardPaddingVertical: EnchantedVisualMetrics.emptyHistoryPadding,
            cardSpacing: EnchantedVisualMetrics.emptyHistorySpacing,
            activeCardRadius: EnchantedVisualMetrics.conversationRowRadius,
            messageCardRadius: EnchantedVisualMetrics.messageBubbleRadius,
            messageCardPaddingHorizontal: EnchantedVisualMetrics.messageBubbleHorizontalPadding,
            messageCardPaddingVertical: EnchantedVisualMetrics.messageBubbleVerticalPadding,
            messageCardSpacing: EnchantedVisualMetrics.messageBubbleSpacing,
            composerMinWidth: EnchantedVisualMetrics.composerMinWidth,
            composerMaxWidth: EnchantedVisualMetrics.composerMaxWidth,
            composerPadding: EnchantedVisualMetrics.composerPadding,
            composerSpacing: EnchantedVisualMetrics.composerSpacing,
            promptRowSpacing: EnchantedVisualMetrics.promptRowSpacing,
            composerMinHeight: EnchantedVisualMetrics.composerMinHeight,
            composerMaxHeight: EnchantedVisualMetrics.composerMaxHeight,
            composerEditorRadius: EnchantedVisualMetrics.composerEditorRadius,
            composerSendButtonMinWidth: EnchantedVisualMetrics.composerSendButtonMinWidth,
            detailPaddingHorizontal: EnchantedVisualMetrics.contentPadding,
            detailPaddingVertical: EnchantedVisualMetrics.contentPadding,
            detailSpacing: EnchantedVisualMetrics.messageSpacing,
            detailContentSpacing: EnchantedVisualMetrics.messageSpacing
        )

        public init(
            canvasColor: String,
            sidebarColor: String,
            cardColor: String,
            activeCardColor: String,
            headerColor: String = "#F7F8F4",
            promptCardColor: String = "#FFFFFF",
            noticeColor: String = "#F8D7DA",
            primaryColor: String,
            inkColor: String,
            mutedColor: String,
            badgeColor: String,
            selectedMutedColor: String,
            borderColor: String,
            selectedBorderColor: String,
            dividerColor: String,
            controlBorderColor: String,
            rootFontSize: Int = EnchantedTypography.rootFontSize,
            appTitleFontSize: Int = EnchantedTypography.appTitleFontSize,
            appTitleFontWeight: Int = EnchantedTypography.appTitleFontWeight,
            captionFontSize: Int = EnchantedTypography.captionFontSize,
            sectionTitleFontSize: Int = EnchantedTypography.sectionTitleFontSize,
            sectionTitleFontWeight: Int = EnchantedTypography.sectionTitleFontWeight,
            currentTitleFontSize: Int = EnchantedTypography.currentTitleFontSize,
            currentTitleFontWeight: Int = EnchantedTypography.currentTitleFontWeight,
            emptyStateWordmarkFontSize: Int = EnchantedTypography.emptyStateWordmarkFontSize,
            emptyStateWordmarkFontWeight: Int = EnchantedTypography.emptyStateWordmarkFontWeight,
            messageBodyFontSize: Int = EnchantedTypography.messageBodyFontSize,
            conversationTitleFontSize: Int = EnchantedTypography.conversationTitleFontSize,
            conversationTitleFontWeight: Int = EnchantedTypography.conversationTitleFontWeight,
            headerHeight: Int = 76,
            headerPadding: Int = 18,
            headerSpacing: Int = 12,
            headerTitleSpacing: Int = 4,
            contentPadding: Int = 22,
            emptyStateMaxWidth: Int = 760,
            emptyStatePadding: Int = 26,
            emptyStateSpacing: Int = 18,
            emptyStateHeaderSpacing: Int = 8,
            promptGridColumns: Int = 4,
            promptGridSpacing: Int = 15,
            promptCardWidth: Int = 160,
            promptCardHeight: Int = 128,
            promptGridWidth: Int = 685,
            promptButtonPadding: Int = 12,
            promptButtonRadius: Int = 8,
            sidebarPadding: Int = 18,
            sidebarSpacing: Int = 12,
            sidebarActionSpacing: Int = 8,
            primaryButtonMinHeight: Int = 36,
            primaryButtonVerticalPadding: Int = 8,
            primaryButtonHorizontalPadding: Int = 12,
            primaryButtonRadius: Int = 8,
            secondaryButtonVerticalPadding: Int = 7,
            secondaryButtonHorizontalPadding: Int = 10,
            secondaryButtonRadius: Int = 7,
            listSpacing: Int = 4,
            listItemRadius: Int = 8,
            listItemVerticalMargin: Int = 2,
            listItemPadding: Int = 8,
            itemRowHorizontalPadding: Int = 2,
            itemRowVerticalPadding: Int = 4,
            itemRowSpacing: Int = 4,
            cardRadius: Int = 8,
            cardPaddingHorizontal: Int = 16,
            cardPaddingVertical: Int = 14,
            cardSpacing: Int = 7,
            activeCardRadius: Int = 8,
            messageCardRadius: Int = 8,
            messageCardPaddingHorizontal: Int = 14,
            messageCardPaddingVertical: Int = 10,
            messageCardSpacing: Int = 6,
            composerMinWidth: Int = 620,
            composerMaxWidth: Int = 800,
            composerPadding: Int = 18,
            composerSpacing: Int = 10,
            promptRowSpacing: Int = 12,
            composerMinHeight: Int = 46,
            composerMaxHeight: Int = 120,
            composerEditorRadius: Int = 23,
            composerSendButtonMinWidth: Int = 86,
            detailPaddingHorizontal: Int = 24,
            detailPaddingVertical: Int = 22,
            detailSpacing: Int = 14,
            detailContentSpacing: Int = 14
        ) {
            self.canvasColor = canvasColor
            self.sidebarColor = sidebarColor
            self.cardColor = cardColor
            self.activeCardColor = activeCardColor
            self.headerColor = headerColor
            self.promptCardColor = promptCardColor
            self.noticeColor = noticeColor
            self.primaryColor = primaryColor
            self.inkColor = inkColor
            self.mutedColor = mutedColor
            self.badgeColor = badgeColor
            self.selectedMutedColor = selectedMutedColor
            self.borderColor = borderColor
            self.selectedBorderColor = selectedBorderColor
            self.dividerColor = dividerColor
            self.controlBorderColor = controlBorderColor
            self.rootFontSize = rootFontSize
            self.appTitleFontSize = appTitleFontSize
            self.appTitleFontWeight = appTitleFontWeight
            self.captionFontSize = captionFontSize
            self.sectionTitleFontSize = sectionTitleFontSize
            self.sectionTitleFontWeight = sectionTitleFontWeight
            self.currentTitleFontSize = currentTitleFontSize
            self.currentTitleFontWeight = currentTitleFontWeight
            self.emptyStateWordmarkFontSize = emptyStateWordmarkFontSize
            self.emptyStateWordmarkFontWeight = emptyStateWordmarkFontWeight
            self.messageBodyFontSize = messageBodyFontSize
            self.conversationTitleFontSize = conversationTitleFontSize
            self.conversationTitleFontWeight = conversationTitleFontWeight
            self.headerHeight = headerHeight
            self.headerPadding = headerPadding
            self.headerSpacing = headerSpacing
            self.headerTitleSpacing = headerTitleSpacing
            self.contentPadding = contentPadding
            self.emptyStateMaxWidth = emptyStateMaxWidth
            self.emptyStatePadding = emptyStatePadding
            self.emptyStateSpacing = emptyStateSpacing
            self.emptyStateHeaderSpacing = emptyStateHeaderSpacing
            self.promptGridColumns = promptGridColumns
            self.promptGridSpacing = promptGridSpacing
            self.promptCardWidth = promptCardWidth
            self.promptCardHeight = promptCardHeight
            self.promptGridWidth = promptGridWidth
            self.promptButtonPadding = promptButtonPadding
            self.promptButtonRadius = promptButtonRadius
            self.sidebarPadding = sidebarPadding
            self.sidebarSpacing = sidebarSpacing
            self.sidebarActionSpacing = sidebarActionSpacing
            self.primaryButtonMinHeight = primaryButtonMinHeight
            self.primaryButtonVerticalPadding = primaryButtonVerticalPadding
            self.primaryButtonHorizontalPadding = primaryButtonHorizontalPadding
            self.primaryButtonRadius = primaryButtonRadius
            self.secondaryButtonVerticalPadding = secondaryButtonVerticalPadding
            self.secondaryButtonHorizontalPadding = secondaryButtonHorizontalPadding
            self.secondaryButtonRadius = secondaryButtonRadius
            self.listSpacing = listSpacing
            self.listItemRadius = listItemRadius
            self.listItemVerticalMargin = listItemVerticalMargin
            self.listItemPadding = listItemPadding
            self.itemRowHorizontalPadding = itemRowHorizontalPadding
            self.itemRowVerticalPadding = itemRowVerticalPadding
            self.itemRowSpacing = itemRowSpacing
            self.cardRadius = cardRadius
            self.cardPaddingHorizontal = cardPaddingHorizontal
            self.cardPaddingVertical = cardPaddingVertical
            self.cardSpacing = cardSpacing
            self.activeCardRadius = activeCardRadius
            self.messageCardRadius = messageCardRadius
            self.messageCardPaddingHorizontal = messageCardPaddingHorizontal
            self.messageCardPaddingVertical = messageCardPaddingVertical
            self.messageCardSpacing = messageCardSpacing
            self.composerMinWidth = composerMinWidth
            self.composerMaxWidth = composerMaxWidth
            self.composerPadding = composerPadding
            self.composerSpacing = composerSpacing
            self.promptRowSpacing = promptRowSpacing
            self.composerMinHeight = composerMinHeight
            self.composerMaxHeight = composerMaxHeight
            self.composerEditorRadius = composerEditorRadius
            self.composerSendButtonMinWidth = composerSendButtonMinWidth
            self.detailPaddingHorizontal = detailPaddingHorizontal
            self.detailPaddingVertical = detailPaddingVertical
            self.detailSpacing = detailSpacing
            self.detailContentSpacing = detailContentSpacing
        }

        private enum CodingKeys: String, CodingKey {
            case canvasColor
            case sidebarColor
            case cardColor
            case activeCardColor
            case headerColor
            case promptCardColor
            case noticeColor
            case primaryColor
            case inkColor
            case mutedColor
            case badgeColor
            case selectedMutedColor
            case borderColor
            case selectedBorderColor
            case dividerColor
            case controlBorderColor
            case rootFontSize
            case appTitleFontSize
            case appTitleFontWeight
            case captionFontSize
            case sectionTitleFontSize
            case sectionTitleFontWeight
            case currentTitleFontSize
            case currentTitleFontWeight
            case emptyStateWordmarkFontSize
            case emptyStateWordmarkFontWeight
            case messageBodyFontSize
            case conversationTitleFontSize
            case conversationTitleFontWeight
            case headerHeight
            case headerPadding
            case headerSpacing
            case headerTitleSpacing
            case contentPadding
            case emptyStateMaxWidth
            case emptyStatePadding
            case emptyStateSpacing
            case emptyStateHeaderSpacing
            case promptGridColumns
            case promptGridSpacing
            case promptCardWidth
            case promptCardHeight
            case promptGridWidth
            case promptButtonPadding
            case promptButtonRadius
            case sidebarPadding
            case sidebarSpacing
            case sidebarActionSpacing
            case primaryButtonMinHeight
            case primaryButtonVerticalPadding
            case primaryButtonHorizontalPadding
            case primaryButtonRadius
            case secondaryButtonVerticalPadding
            case secondaryButtonHorizontalPadding
            case secondaryButtonRadius
            case listSpacing
            case listItemRadius
            case listItemVerticalMargin
            case listItemPadding
            case itemRowHorizontalPadding
            case itemRowVerticalPadding
            case itemRowSpacing
            case cardRadius
            case cardPaddingHorizontal
            case cardPaddingVertical
            case cardSpacing
            case activeCardRadius
            case messageCardRadius
            case messageCardPaddingHorizontal
            case messageCardPaddingVertical
            case messageCardSpacing
            case composerMinWidth
            case composerMaxWidth
            case composerPadding
            case composerSpacing
            case promptRowSpacing
            case composerMinHeight
            case composerMaxHeight
            case composerEditorRadius
            case composerSendButtonMinWidth
            case detailPaddingHorizontal
            case detailPaddingVertical
            case detailSpacing
            case detailContentSpacing
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Self.desktop

            self.init(
                canvasColor: try container.decodeIfPresent(String.self, forKey: .canvasColor)
                    ?? defaults.canvasColor,
                sidebarColor: try container.decodeIfPresent(String.self, forKey: .sidebarColor)
                    ?? defaults.sidebarColor,
                cardColor: try container.decodeIfPresent(String.self, forKey: .cardColor)
                    ?? defaults.cardColor,
                activeCardColor: try container.decodeIfPresent(String.self, forKey: .activeCardColor)
                    ?? defaults.activeCardColor,
                headerColor: try container.decodeIfPresent(String.self, forKey: .headerColor)
                    ?? defaults.headerColor,
                promptCardColor: try container.decodeIfPresent(String.self, forKey: .promptCardColor)
                    ?? defaults.promptCardColor,
                noticeColor: try container.decodeIfPresent(String.self, forKey: .noticeColor)
                    ?? defaults.noticeColor,
                primaryColor: try container.decodeIfPresent(String.self, forKey: .primaryColor)
                    ?? defaults.primaryColor,
                inkColor: try container.decodeIfPresent(String.self, forKey: .inkColor)
                    ?? defaults.inkColor,
                mutedColor: try container.decodeIfPresent(String.self, forKey: .mutedColor)
                    ?? defaults.mutedColor,
                badgeColor: try container.decodeIfPresent(String.self, forKey: .badgeColor)
                    ?? defaults.badgeColor,
                selectedMutedColor: try container.decodeIfPresent(String.self, forKey: .selectedMutedColor)
                    ?? defaults.selectedMutedColor,
                borderColor: try container.decodeIfPresent(String.self, forKey: .borderColor)
                    ?? defaults.borderColor,
                selectedBorderColor: try container.decodeIfPresent(String.self, forKey: .selectedBorderColor)
                    ?? defaults.selectedBorderColor,
                dividerColor: try container.decodeIfPresent(String.self, forKey: .dividerColor)
                    ?? defaults.dividerColor,
                controlBorderColor: try container.decodeIfPresent(String.self, forKey: .controlBorderColor)
                    ?? defaults.controlBorderColor,
                rootFontSize: try container.decodeIfPresent(Int.self, forKey: .rootFontSize)
                    ?? defaults.rootFontSize,
                appTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .appTitleFontSize)
                    ?? defaults.appTitleFontSize,
                appTitleFontWeight: try container.decodeIfPresent(Int.self, forKey: .appTitleFontWeight)
                    ?? defaults.appTitleFontWeight,
                captionFontSize: try container.decodeIfPresent(Int.self, forKey: .captionFontSize)
                    ?? defaults.captionFontSize,
                sectionTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .sectionTitleFontSize)
                    ?? defaults.sectionTitleFontSize,
                sectionTitleFontWeight: try container.decodeIfPresent(Int.self, forKey: .sectionTitleFontWeight)
                    ?? defaults.sectionTitleFontWeight,
                currentTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .currentTitleFontSize)
                    ?? defaults.currentTitleFontSize,
                currentTitleFontWeight: try container.decodeIfPresent(Int.self, forKey: .currentTitleFontWeight)
                    ?? defaults.currentTitleFontWeight,
                emptyStateWordmarkFontSize: try container.decodeIfPresent(
                    Int.self,
                    forKey: .emptyStateWordmarkFontSize
                ) ?? defaults.emptyStateWordmarkFontSize,
                emptyStateWordmarkFontWeight: try container.decodeIfPresent(
                    Int.self,
                    forKey: .emptyStateWordmarkFontWeight
                ) ?? defaults.emptyStateWordmarkFontWeight,
                messageBodyFontSize: try container.decodeIfPresent(Int.self, forKey: .messageBodyFontSize)
                    ?? defaults.messageBodyFontSize,
                conversationTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .conversationTitleFontSize)
                    ?? defaults.conversationTitleFontSize,
                conversationTitleFontWeight: try container.decodeIfPresent(Int.self, forKey: .conversationTitleFontWeight)
                    ?? defaults.conversationTitleFontWeight,
                headerHeight: try container.decodeIfPresent(Int.self, forKey: .headerHeight)
                    ?? defaults.headerHeight,
                headerPadding: try container.decodeIfPresent(Int.self, forKey: .headerPadding)
                    ?? defaults.headerPadding,
                headerSpacing: try container.decodeIfPresent(Int.self, forKey: .headerSpacing)
                    ?? defaults.headerSpacing,
                headerTitleSpacing: try container.decodeIfPresent(Int.self, forKey: .headerTitleSpacing)
                    ?? defaults.headerTitleSpacing,
                contentPadding: try container.decodeIfPresent(Int.self, forKey: .contentPadding)
                    ?? defaults.contentPadding,
                emptyStateMaxWidth: try container.decodeIfPresent(Int.self, forKey: .emptyStateMaxWidth)
                    ?? defaults.emptyStateMaxWidth,
                emptyStatePadding: try container.decodeIfPresent(Int.self, forKey: .emptyStatePadding)
                    ?? defaults.emptyStatePadding,
                emptyStateSpacing: try container.decodeIfPresent(Int.self, forKey: .emptyStateSpacing)
                    ?? defaults.emptyStateSpacing,
                emptyStateHeaderSpacing: try container.decodeIfPresent(Int.self, forKey: .emptyStateHeaderSpacing)
                    ?? defaults.emptyStateHeaderSpacing,
                promptGridColumns: try container.decodeIfPresent(Int.self, forKey: .promptGridColumns)
                    ?? defaults.promptGridColumns,
                promptGridSpacing: try container.decodeIfPresent(Int.self, forKey: .promptGridSpacing)
                    ?? defaults.promptGridSpacing,
                promptCardWidth: try container.decodeIfPresent(Int.self, forKey: .promptCardWidth)
                    ?? defaults.promptCardWidth,
                promptCardHeight: try container.decodeIfPresent(Int.self, forKey: .promptCardHeight)
                    ?? defaults.promptCardHeight,
                promptGridWidth: try container.decodeIfPresent(Int.self, forKey: .promptGridWidth)
                    ?? defaults.promptGridWidth,
                promptButtonPadding: try container.decodeIfPresent(Int.self, forKey: .promptButtonPadding)
                    ?? defaults.promptButtonPadding,
                promptButtonRadius: try container.decodeIfPresent(Int.self, forKey: .promptButtonRadius)
                    ?? defaults.promptButtonRadius,
                sidebarPadding: try container.decodeIfPresent(Int.self, forKey: .sidebarPadding)
                    ?? defaults.sidebarPadding,
                sidebarSpacing: try container.decodeIfPresent(Int.self, forKey: .sidebarSpacing)
                    ?? defaults.sidebarSpacing,
                sidebarActionSpacing: try container.decodeIfPresent(Int.self, forKey: .sidebarActionSpacing)
                    ?? defaults.sidebarActionSpacing,
                primaryButtonMinHeight: try container.decodeIfPresent(Int.self, forKey: .primaryButtonMinHeight)
                    ?? defaults.primaryButtonMinHeight,
                primaryButtonVerticalPadding: try container.decodeIfPresent(Int.self, forKey: .primaryButtonVerticalPadding)
                    ?? defaults.primaryButtonVerticalPadding,
                primaryButtonHorizontalPadding: try container.decodeIfPresent(Int.self, forKey: .primaryButtonHorizontalPadding)
                    ?? defaults.primaryButtonHorizontalPadding,
                primaryButtonRadius: try container.decodeIfPresent(Int.self, forKey: .primaryButtonRadius)
                    ?? defaults.primaryButtonRadius,
                secondaryButtonVerticalPadding: try container.decodeIfPresent(
                    Int.self,
                    forKey: .secondaryButtonVerticalPadding
                ) ?? defaults.secondaryButtonVerticalPadding,
                secondaryButtonHorizontalPadding: try container.decodeIfPresent(
                    Int.self,
                    forKey: .secondaryButtonHorizontalPadding
                ) ?? defaults.secondaryButtonHorizontalPadding,
                secondaryButtonRadius: try container.decodeIfPresent(Int.self, forKey: .secondaryButtonRadius)
                    ?? defaults.secondaryButtonRadius,
                listSpacing: try container.decodeIfPresent(Int.self, forKey: .listSpacing)
                    ?? defaults.listSpacing,
                listItemRadius: try container.decodeIfPresent(Int.self, forKey: .listItemRadius)
                    ?? defaults.listItemRadius,
                listItemVerticalMargin: try container.decodeIfPresent(Int.self, forKey: .listItemVerticalMargin)
                    ?? defaults.listItemVerticalMargin,
                listItemPadding: try container.decodeIfPresent(Int.self, forKey: .listItemPadding)
                    ?? defaults.listItemPadding,
                itemRowHorizontalPadding: try container.decodeIfPresent(Int.self, forKey: .itemRowHorizontalPadding)
                    ?? defaults.itemRowHorizontalPadding,
                itemRowVerticalPadding: try container.decodeIfPresent(Int.self, forKey: .itemRowVerticalPadding)
                    ?? defaults.itemRowVerticalPadding,
                itemRowSpacing: try container.decodeIfPresent(Int.self, forKey: .itemRowSpacing)
                    ?? defaults.itemRowSpacing,
                cardRadius: try container.decodeIfPresent(Int.self, forKey: .cardRadius)
                    ?? defaults.cardRadius,
                cardPaddingHorizontal: try container.decodeIfPresent(Int.self, forKey: .cardPaddingHorizontal)
                    ?? defaults.cardPaddingHorizontal,
                cardPaddingVertical: try container.decodeIfPresent(Int.self, forKey: .cardPaddingVertical)
                    ?? defaults.cardPaddingVertical,
                cardSpacing: try container.decodeIfPresent(Int.self, forKey: .cardSpacing)
                    ?? defaults.cardSpacing,
                activeCardRadius: try container.decodeIfPresent(Int.self, forKey: .activeCardRadius)
                    ?? defaults.activeCardRadius,
                messageCardRadius: try container.decodeIfPresent(Int.self, forKey: .messageCardRadius)
                    ?? defaults.messageCardRadius,
                messageCardPaddingHorizontal: try container.decodeIfPresent(
                    Int.self,
                    forKey: .messageCardPaddingHorizontal
                ) ?? defaults.messageCardPaddingHorizontal,
                messageCardPaddingVertical: try container.decodeIfPresent(
                    Int.self,
                    forKey: .messageCardPaddingVertical
                ) ?? defaults.messageCardPaddingVertical,
                messageCardSpacing: try container.decodeIfPresent(Int.self, forKey: .messageCardSpacing)
                    ?? defaults.messageCardSpacing,
                composerMinWidth: try container.decodeIfPresent(Int.self, forKey: .composerMinWidth)
                    ?? defaults.composerMinWidth,
                composerMaxWidth: try container.decodeIfPresent(Int.self, forKey: .composerMaxWidth)
                    ?? defaults.composerMaxWidth,
                composerPadding: try container.decodeIfPresent(Int.self, forKey: .composerPadding)
                    ?? defaults.composerPadding,
                composerSpacing: try container.decodeIfPresent(Int.self, forKey: .composerSpacing)
                    ?? defaults.composerSpacing,
                promptRowSpacing: try container.decodeIfPresent(Int.self, forKey: .promptRowSpacing)
                    ?? defaults.promptRowSpacing,
                composerMinHeight: try container.decodeIfPresent(Int.self, forKey: .composerMinHeight)
                    ?? defaults.composerMinHeight,
                composerMaxHeight: try container.decodeIfPresent(Int.self, forKey: .composerMaxHeight)
                    ?? defaults.composerMaxHeight,
                composerEditorRadius: try container.decodeIfPresent(Int.self, forKey: .composerEditorRadius)
                    ?? defaults.composerEditorRadius,
                composerSendButtonMinWidth: try container.decodeIfPresent(Int.self, forKey: .composerSendButtonMinWidth)
                    ?? defaults.composerSendButtonMinWidth,
                detailPaddingHorizontal: try container.decodeIfPresent(Int.self, forKey: .detailPaddingHorizontal)
                    ?? defaults.detailPaddingHorizontal,
                detailPaddingVertical: try container.decodeIfPresent(Int.self, forKey: .detailPaddingVertical)
                    ?? defaults.detailPaddingVertical,
                detailSpacing: try container.decodeIfPresent(Int.self, forKey: .detailSpacing)
                    ?? defaults.detailSpacing,
                detailContentSpacing: try container.decodeIfPresent(Int.self, forKey: .detailContentSpacing)
                    ?? defaults.detailContentSpacing
            )
        }
    }

    public init(
        windowTitle: String,
        minimumWidth: Int = 900,
        minimumHeight: Int = 620,
        defaultWidth: Int = 1040,
        defaultHeight: Int = 700,
        sidebarWidth: Int = 320,
        detailWidth: Int = 720,
        sidebarTitle: String,
        sidebarSubtitle: String,
        primaryActionTitle: String = "New",
        secondaryActionTitle: String = "Refresh",
        listTitle: String,
        status: String,
        selectedIndex: Int = 0,
        selectedIndexEnvironmentKeys: [String] = QuillGenericQtAppSnapshot.defaultSelectedIndexEnvironmentKeys,
        detailTitle: String,
        detailSubtitle: String,
        messagesTitle: String = "Activity",
        items: [Item],
        sections: [Section],
        messages: [Message] = [],
        presentation: Presentation = .standard,
        emptyStateTitle: String = "",
        emptyStateSubtitle: String = "",
        prompts: [Prompt] = [],
        bottomNavigation: [NavigationAction] = [],
        composerPlaceholder: String = "",
        noticeTitle: String = "",
        noticeBody: String = "",
        noticeActionTitle: String = "",
        style: Style = .desktop
    ) {
        self.windowTitle = windowTitle
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.defaultWidth = defaultWidth
        self.defaultHeight = defaultHeight
        self.sidebarWidth = sidebarWidth
        self.detailWidth = detailWidth
        self.sidebarTitle = sidebarTitle
        self.sidebarSubtitle = sidebarSubtitle
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.listTitle = listTitle
        self.status = status
        self.selectedIndex = selectedIndex
        self.selectedIndexEnvironmentKeys = selectedIndexEnvironmentKeys
        self.detailTitle = detailTitle
        self.detailSubtitle = detailSubtitle
        self.messagesTitle = messagesTitle
        self.items = items
        self.sections = sections
        self.messages = messages
        self.presentation = presentation
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateSubtitle = emptyStateSubtitle
        self.prompts = prompts
        self.bottomNavigation = bottomNavigation
        self.composerPlaceholder = composerPlaceholder
        self.noticeTitle = noticeTitle
        self.noticeBody = noticeBody
        self.noticeActionTitle = noticeActionTitle
        self.style = style
    }

    private enum CodingKeys: String, CodingKey {
        case windowTitle
        case minimumWidth
        case minimumHeight
        case defaultWidth
        case defaultHeight
        case sidebarWidth
        case detailWidth
        case sidebarTitle
        case sidebarSubtitle
        case primaryActionTitle
        case secondaryActionTitle
        case listTitle
        case status
        case selectedIndex
        case selectedIndexEnvironmentKeys
        case detailTitle
        case detailSubtitle
        case messagesTitle
        case items
        case sections
        case messages
        case presentation
        case emptyStateTitle
        case emptyStateSubtitle
        case prompts
        case bottomNavigation
        case composerPlaceholder
        case noticeTitle
        case noticeBody
        case noticeActionTitle
        case style
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            windowTitle: try container.decode(String.self, forKey: .windowTitle),
            minimumWidth: try container.decodeIfPresent(Int.self, forKey: .minimumWidth) ?? 900,
            minimumHeight: try container.decodeIfPresent(Int.self, forKey: .minimumHeight) ?? 620,
            defaultWidth: try container.decodeIfPresent(Int.self, forKey: .defaultWidth) ?? 1040,
            defaultHeight: try container.decodeIfPresent(Int.self, forKey: .defaultHeight) ?? 700,
            sidebarWidth: try container.decodeIfPresent(Int.self, forKey: .sidebarWidth) ?? 320,
            detailWidth: try container.decodeIfPresent(Int.self, forKey: .detailWidth) ?? 720,
            sidebarTitle: try container.decode(String.self, forKey: .sidebarTitle),
            sidebarSubtitle: try container.decode(String.self, forKey: .sidebarSubtitle),
            primaryActionTitle: try container.decodeIfPresent(String.self, forKey: .primaryActionTitle) ?? "New",
            secondaryActionTitle: try container.decodeIfPresent(String.self, forKey: .secondaryActionTitle)
                ?? "Refresh",
            listTitle: try container.decode(String.self, forKey: .listTitle),
            status: try container.decode(String.self, forKey: .status),
            selectedIndex: try container.decodeIfPresent(Int.self, forKey: .selectedIndex) ?? 0,
            selectedIndexEnvironmentKeys: try container.decodeIfPresent(
                [String].self,
                forKey: .selectedIndexEnvironmentKeys
            ) ?? Self.defaultSelectedIndexEnvironmentKeys,
            detailTitle: try container.decode(String.self, forKey: .detailTitle),
            detailSubtitle: try container.decode(String.self, forKey: .detailSubtitle),
            messagesTitle: try container.decodeIfPresent(String.self, forKey: .messagesTitle) ?? "Activity",
            items: try container.decode([Item].self, forKey: .items),
            sections: try container.decode([Section].self, forKey: .sections),
            messages: try container.decodeIfPresent([Message].self, forKey: .messages) ?? [],
            presentation: try container.decodeIfPresent(Presentation.self, forKey: .presentation) ?? .standard,
            emptyStateTitle: try container.decodeIfPresent(String.self, forKey: .emptyStateTitle) ?? "",
            emptyStateSubtitle: try container.decodeIfPresent(String.self, forKey: .emptyStateSubtitle) ?? "",
            prompts: try container.decodeIfPresent([Prompt].self, forKey: .prompts) ?? [],
            bottomNavigation: try container.decodeIfPresent([NavigationAction].self, forKey: .bottomNavigation) ?? [],
            composerPlaceholder: try container.decodeIfPresent(String.self, forKey: .composerPlaceholder) ?? "",
            noticeTitle: try container.decodeIfPresent(String.self, forKey: .noticeTitle) ?? "",
            noticeBody: try container.decodeIfPresent(String.self, forKey: .noticeBody) ?? "",
            noticeActionTitle: try container.decodeIfPresent(String.self, forKey: .noticeActionTitle) ?? "",
            style: try container.decodeIfPresent(Style.self, forKey: .style) ?? .desktop
        )
    }
}

private enum QuillGenericQtSelectionEnvironment {
    static let chat = "QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START"
    static let codeEdit = "QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"
    static let iceCubes = "QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"
    static let iina = "QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START"
    static let netNewsWire = "QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"
    static let signal = "QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START"
    static let telegram = "QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"

    static func appSpecific(_ environmentKeys: String...) -> [String] {
        appSpecific(environmentKeys)
    }

    static func appSpecific(_ environmentKeys: [String]) -> [String] {
        environmentKeys + QuillGenericQtAppSnapshot.defaultSelectedIndexEnvironmentKeys
    }
}

public enum QuillGenericQtAppCatalog {
    public static let quillChat = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Chat",
        defaultWidth: 1120,
        defaultHeight: 720,
        sidebarTitle: "Quill Chat",
        sidebarSubtitle: "Local AI workspace",
        primaryActionTitle: "New chat",
        secondaryActionTitle: "Models",
        listTitle: "Conversations",
        status: "Qt native runtime",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.chat
        ),
        detailTitle: "Conversation preview",
        detailSubtitle: "A generated Quill Chat package running through the Qt native host.",
        messagesTitle: "Transcript",
        items: [
            .init(
                title: "Model readiness",
                subtitle: "Check the local endpoint",
                badge: "ready",
                detailSubtitle: "Endpoint and model status remain visible beside the transcript.",
                sections: [
                    .init(title: "Endpoint", body: "The native shell keeps the selected model, endpoint state, and conversation list in the same layout across Linux backends."),
                    .init(title: "Result", body: "A short response confirms that generated packages are linked to the Qt native runtime.")
                ],
                messages: [
                    .init(sender: "user", body: "Confirm the local model is available."),
                    .init(sender: "assistant", body: "The generated Qt launcher is active.")
                ]
            ),
            .init(
                title: "Code review",
                subtitle: "Summarize pending changes",
                badge: "draft",
                detailSubtitle: "Review prompt with a compact response draft.",
                sections: [
                    .init(title: "Prompt", body: "The selected thread can carry app-specific context without duplicating launcher code."),
                    .init(title: "Draft", body: "Generated Quill Chat and canonical generic Qt apps share the same runtime renderer and catalog model.")
                ],
                messages: [
                    .init(sender: "user", body: "Summarize the next Linux parity gap."),
                    .init(sender: "assistant", body: "Generated Qt packages now compile against the native Qt runtime.")
                ]
            ),
            .init(
                title: "Planning note",
                subtitle: "Track desktop consistency",
                badge: "qa",
                detailSubtitle: "Desktop consistency checklist for the next loop.",
                sections: [
                    .init(title: "GTK", body: "The generated GTK launcher continues to use QuillUIGtk and QuillGtkApp."),
                    .init(title: "Qt", body: "The generated Qt launcher bypasses the fallback registry and enters QuillGenericQtNativeRuntime directly.")
                ],
                messages: [
                    .init(sender: "user", body: "Keep GTK and Qt explicit."),
                    .init(sender: "assistant", body: "The package generator now selects one native backend path per request.")
                ]
            )
        ],
        sections: [
            .init(title: "Generated app runtime", body: "The temporary package links QuillGenericQtNativeRuntime when QUILLUI_GENERATED_BACKEND_FACADE=qt is selected."),
            .init(title: "Shared renderer", body: "Quill Chat uses the same generic Qt catalog renderer as the smaller native app shells, keeping the implementation DRY.")
        ],
        messages: [
            .init(sender: "assistant", body: "Quill Chat is running through the generated Qt native entry.")
        ]
    )

    public static let enchantedUpstreamSlice = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Chat",
        minimumWidth: EnchantedVisualMetrics.minimumWindowWidth,
        minimumHeight: EnchantedVisualMetrics.minimumWindowHeight,
        defaultWidth: EnchantedVisualMetrics.defaultWindowWidth,
        defaultHeight: EnchantedVisualMetrics.defaultWindowHeight,
        sidebarWidth: EnchantedVisualMetrics.sidebarWidth,
        detailWidth: EnchantedVisualMetrics.detailWidth,
        sidebarTitle: "Quill Chat",
        sidebarSubtitle: "Local AI conversations",
        primaryActionTitle: "New chat",
        secondaryActionTitle: "Models",
        listTitle: "Conversations",
        status: "Local model ready",
        selectedIndex: -1,
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            EnchantedInitialSelection.selectedConversationIndexEnvironmentKeys
        ),
        detailTitle: "Conversation preview",
        detailSubtitle: "A compact chat workspace with model status, recent prompts, and draft replies.",
        items: [
            .init(
                title: "Auto-config test: reply with one sho...",
                subtitle: "",
                badge: "3 days ago",
                height: 76,
                detailSubtitle: "Local model setup conversation with endpoint status visible.",
                sections: [
                    .init(title: "Endpoint", body: "The selected chat keeps the Ollama endpoint, model choice, and readiness status close to the transcript."),
                    .init(title: "Prompt", body: "A short assistant response confirms the local model is reachable before a longer session starts.")
                ],
                messages: [
                    .init(sender: "user", body: "Reply with one short phrase."),
                    .init(sender: "assistant", body: "Local model is ready.")
                ]
            ),
            .init(
                title: "say one short word",
                subtitle: "",
                height: 44
            ),
            .init(
                title: "say hi in one word",
                subtitle: "",
                height: 54
            ),
            .init(
                title: "Write a text message asking a frien...",
                subtitle: "",
                badge: "4 days ago",
                height: 82,
                detailSubtitle: "Friendly draft-writing conversation.",
                sections: [
                    .init(title: "Conversation", body: "Draft state, title, and preview text stay easy to scan while the reply is refined."),
                    .init(title: "Composer", body: "Attachment context and the message composer remain close to the conversation.")
                ],
                messages: [
                    .init(sender: "user", body: "Draft a friendly plus-one message."),
                    .init(sender: "assistant", body: "Happy to join you at the wedding. Thanks for including me.")
                ]
            ),
            .init(
                title: "Give me phrases to learn in a new la...",
                subtitle: "",
                badge: "7 days ago",
                height: 82
            ),
            .init(
                title: "How to center div in HTML?",
                subtitle: "",
                height: 50
            )
        ],
        sections: [
            .init(title: "Endpoint and model controls", body: "The chat shell keeps model status, conversation selection, and prompt context in one workspace."),
            .init(title: "Conversation state", body: "Each row carries its own title, detail cards, and transcript so selection changes feel immediate.")
        ],
        messages: [
            .init(sender: "assistant", body: "The selected conversation is ready for a local-model response.")
        ],
        presentation: .chat,
        emptyStateTitle: "Quill",
        emptyStateSubtitle: EnchantedCopy.emptyStateSubtitle,
        prompts: EnchantedPromptCatalog.visibleEmptyConversationPrompts.map(QuillGenericQtAppSnapshot.Prompt.init),
        bottomNavigation: [
            .init(title: EnchantedCopy.completionsTitle, systemImage: EnchantedIcon.completions),
            .init(title: EnchantedCopy.shortcutsTitle, systemImage: EnchantedIcon.shortcuts),
            .init(title: EnchantedCopy.settingsTitle, systemImage: EnchantedIcon.settings)
        ],
        composerPlaceholder: EnchantedCopy.composerPlaceholder,
        noticeTitle: "Quill is unreachable.",
        noticeBody: "Plug Quill back in if it's unplugged, or go to Settings and update your Quill API endpoint.",
        noticeActionTitle: EnchantedCopy.settingsTitle,
        style: .enchanted
    )

    public static let iceCubes = QuillGenericQtAppSnapshot(
        windowTitle: "Quill IceCubes",
        sidebarTitle: "IceCubes",
        sidebarSubtitle: "Mastodon timeline",
        primaryActionTitle: "Post",
        secondaryActionTitle: "Boosts",
        listTitle: "Timeline",
        status: "Public timeline loaded",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.iceCubes
        ),
        detailTitle: "Timeline item",
        detailSubtitle: "Mastodon-style timeline with replies, boosts, and post detail.",
        items: [
            .init(
                title: "Mastodon Design",
                subtitle: "Timeline polish update",
                badge: "2m",
                detailSubtitle: "Design notes from the product account.",
                sections: [
                    .init(title: "Post", body: "The selected timeline row opens a focused view with author, timestamp, and excerpt."),
                    .init(title: "Actions", body: "Reply, boost, favorite, and share affordances stay in a predictable hierarchy.")
                ]
            ),
            .init(
                title: "Swift on Linux",
                subtitle: "Desktop packaging notes",
                badge: "8m",
                detailSubtitle: "Toolchain update focused on Linux app packaging.",
                sections: [
                    .init(title: "Thread", body: "The post collects packaging notes, release steps, and a short checklist for desktop builds."),
                    .init(title: "Build note", body: "The update is grouped with related replies so the thread can be reviewed quickly.")
                ]
            ),
            .init(
                title: "Mastodon",
                subtitle: "Timeline cards, replies, and boosts",
                badge: "14m",
                detailSubtitle: "Open conversation with replies and boosts.",
                sections: [
                    .init(title: "Conversation", body: "Replies and boost counts remain visible when the selected row changes."),
                    .init(title: "Thread detail", body: "The lower row carries a distinct conversation preview for selection checks.")
                ]
            )
        ],
        sections: [
            .init(title: "Timeline density", body: "Rows keep avatars, timestamps, and action affordances in a compact, repeatable hierarchy."),
            .init(title: "Responsive updates", body: "Selection changes update detail cards and messages without disturbing the timeline list.")
        ]
    )

    public static let netNewsWire = QuillGenericQtAppSnapshot(
        windowTitle: "Quill NetNewsWire",
        sidebarTitle: "NetNewsWire",
        sidebarSubtitle: "RSS reader",
        primaryActionTitle: "Add feed",
        secondaryActionTitle: "Refresh",
        listTitle: "Feeds",
        status: "3 unread articles",
        selectedIndex: 1,
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.netNewsWire
        ),
        detailTitle: "Article reader",
        detailSubtitle: "RSS reader with feed selection, unread counts, and article excerpts.",
        items: [
            .init(
                title: "Swift.org",
                subtitle: "Language and toolchain updates",
                badge: "1",
                detailSubtitle: "Unread language and toolchain article selected.",
                sections: [
                    .init(title: "Article", body: "The Swift.org entry keeps source, title, and unread count visible in the reader."),
                    .init(title: "Reader chrome", body: "The article body reuses the same detail-card renderer as the other generic apps.")
                ]
            ),
            .init(
                title: "Point-Free",
                subtitle: "Composable app architecture notes",
                badge: "2",
                detailSubtitle: "Composable architecture feed selected by default.",
                sections: [
                    .init(title: "Article", body: "The selected feed row exposes a stable headline, excerpt, and unread badge."),
                    .init(title: "Navigation", body: "Feed selection changes the detail cards without rebuilding the Qt window.")
                ]
            ),
            .init(
                title: "Linux Weekly",
                subtitle: "Desktop compatibility report",
                detailSubtitle: "Desktop compatibility article selected for reading.",
                sections: [
                    .init(title: "Article", body: "The report summarizes desktop polish, packaging notes, and recently fixed regressions."),
                    .init(title: "Reader state", body: "The lower feed row gives the reader a distinct article surface.")
                ]
            )
        ],
        sections: [
            .init(title: "Reader layout", body: "The reader keeps feed selection, unread counts, and article detail in a steady three-pane rhythm."),
            .init(title: "Article state", body: "Each feed row carries the headline, excerpt, and selected-state detail needed for fast scanning.")
        ]
    )

    public static let codeEdit = QuillGenericQtAppSnapshot(
        windowTitle: "Quill CodeEdit",
        minimumWidth: 980,
        defaultWidth: 1180,
        defaultHeight: 740,
        sidebarTitle: "CodeEdit",
        sidebarSubtitle: "Workspace shell",
        primaryActionTitle: "Open",
        secondaryActionTitle: "Search",
        listTitle: "Files",
        status: "Workspace loaded",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.codeEdit
        ),
        detailTitle: "Editor preview",
        detailSubtitle: "Workbench with file tree, tabs, diagnostics, and editor chrome.",
        items: [
            .init(
                title: "Package.swift",
                subtitle: "Package manifest",
                badge: "M",
                detailSubtitle: "Manifest preview with package products and targets.",
                sections: [
                    .init(title: "Editor", body: "The manifest row highlights products, target dependencies, and package metadata."),
                    .init(title: "Diagnostics", body: "The modified badge remains visible while the file preview changes.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "Package metadata is ready for review.")
                ]
            ),
            .init(
                title: "QuillUI.swift",
                subtitle: "Application entry point",
                detailSubtitle: "Source preview for the shared app entry point.",
                sections: [
                    .init(title: "Editor", body: "The facade row keeps the app entry point and scene metadata in the detail pane."),
                    .init(title: "Navigation", body: "Changing file rows updates the same workbench surface.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "No stale detail content after file selection.")
                ]
            ),
            .init(
                title: "ProjectNavigator.swift",
                subtitle: "Workspace navigation",
                detailSubtitle: "Project navigator source file selected.",
                sections: [
                    .init(title: "Editor", body: "The selected navigator row describes file grouping, search state, and outline metadata."),
                    .init(title: "Selection", body: "This row makes the editor preview update beyond the sidebar selection.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "Navigator selection updates the editor preview.")
                ]
            )
        ],
        sections: [
            .init(title: "Workbench", body: "The app keeps the visible file tree, editor panels, and diagnostics in a compact desktop layout."),
            .init(title: "Diagnostics", body: "Diagnostics stay attached to the selected file so review context remains clear.")
        ],
        messages: [
            .init(sender: "diagnostic", body: "No warnings are expected for this target.")
        ]
    )

    public static let signal = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Signal",
        sidebarTitle: "Signal",
        sidebarSubtitle: "Private messaging",
        primaryActionTitle: "Compose",
        secondaryActionTitle: "Archive",
        listTitle: "Chats",
        status: "End-to-end encrypted",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.signal,
            QuillGenericQtSelectionEnvironment.chat
        ),
        detailTitle: "Conversation",
        detailSubtitle: "Private messaging layout with chat list, unread badges, and thread detail.",
        items: [
            .init(
                title: "Mira Patel",
                subtitle: "Lunch moved to 12:30",
                badge: "2",
                detailSubtitle: "Direct message thread with unread replies.",
                sections: [
                    .init(title: "Thread state", body: "Unread badges, preview text, and encrypted conversation chrome stay app-specific."),
                    .init(title: "Conversation detail", body: "The detail pane follows the selected chat instead of showing a static fallback.")
                ],
                messages: [
                    .init(sender: "Mira", body: "Lunch moved to 12:30."),
                    .init(sender: "You", body: "Works for me.")
                ]
            ),
            .init(
                title: "Design review",
                subtitle: "Wireframes are ready",
                detailSubtitle: "Group thread for product review notes.",
                sections: [
                    .init(title: "Thread state", body: "Group chat state keeps participants, attachment context, and delivery status in one model."),
                    .init(title: "Visual contract", body: "Selection-driven detail content gives each chat a meaningful preview.")
                ],
                messages: [
                    .init(sender: "Ari", body: "Wireframes are ready for the review."),
                    .init(sender: "You", body: "I will compare the desktop and Linux captures.")
                ]
            ),
            .init(
                title: "Family",
                subtitle: "Photos from the trip",
                badge: "5",
                detailSubtitle: "Weekend photo thread with media previews.",
                sections: [
                    .init(title: "Thread state", body: "The selected chat keeps media previews and unread state separate from the shared shell."),
                    .init(title: "Conversation detail", body: "Changing rows updates headers, detail cards, and messages together.")
                ],
                messages: [
                    .init(sender: "Sam", body: "Added the photos from the trip."),
                    .init(sender: "You", body: "Saving them after this build passes.")
                ]
            )
        ],
        sections: [
            .init(title: "Chat chrome", body: "Signal keeps a dense chat list, unread badges, and selected-thread messages in one workspace."),
            .init(title: "Message state", body: "Conversation rows update the header, detail cards, and recent messages together.")
        ],
        messages: [
            .init(sender: "Mira", body: "Can you check the latest screenshots?"),
            .init(sender: "You", body: "I will review them before the meeting.")
        ]
    )

    public static let telegram = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Telegram",
        defaultWidth: 1100,
        defaultHeight: 720,
        sidebarTitle: "Telegram",
        sidebarSubtitle: "Channels and folders",
        primaryActionTitle: "New message",
        secondaryActionTitle: "Folders",
        listTitle: "Chats",
        status: "Pinned channels visible",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.telegram,
            QuillGenericQtSelectionEnvironment.chat
        ),
        detailTitle: "Channel preview",
        detailSubtitle: "Foldered chat list with pinned channels and recent activity.",
        items: [
            .init(
                title: "Swift Linux",
                subtitle: "Desktop packaging notes",
                badge: "12",
                detailSubtitle: "Channel thread for Swift-on-Linux updates.",
                sections: [
                    .init(title: "Channel", body: "Unread count and channel preview stay attached to the selected Telegram row."),
                    .init(title: "Milestone", body: "The channel collects release notes, packaging steps, and migration reminders.")
                ],
                messages: [
                    .init(sender: "Swift Linux", body: "Desktop packaging notes are ready for review."),
                    .init(sender: "You", body: "Keep the release checklist explicit.")
                ]
            ),
            .init(
                title: "Release ops",
                subtitle: "Nightly checks passed",
                badge: "pin",
                detailSubtitle: "Pinned release operations channel selected.",
                sections: [
                    .init(title: "Channel", body: "Pinned state and check status stay visible in the selected row detail."),
                    .init(title: "Operations", body: "The detail pane keeps release notes, owners, and current status together.")
                ],
                messages: [
                    .init(sender: "Release ops", body: "Nightly checks passed for the release train."),
                    .init(sender: "You", body: "I will review the report before publishing.")
                ]
            ),
            .init(
                title: "Core Team",
                subtitle: "Project board updates",
                detailSubtitle: "Core engineering channel with the lower row selected.",
                sections: [
                    .init(title: "Channel", body: "Project board changes and owner updates are visible in the selected channel detail."),
                    .init(title: "Shared shell", body: "Telegram keeps folders, pinned channels, and channel previews in the same chat layout.")
                ],
                messages: [
                    .init(sender: "Core Team", body: "Project board changes landed this morning."),
                    .init(sender: "You", body: "Next pass is app coverage.")
                ]
            )
        ],
        sections: [
            .init(title: "Folders", body: "Telegram keeps app-specific folders and unread badges on top of the shared chat layout."),
            .init(title: "Channels", body: "Pinned channels, unread counts, and previews remain clear across the selected chat.")
        ],
        messages: [
            .init(sender: "Release ops", body: "Nightly checks are ready for review.")
        ]
    )

    public static let iina = QuillGenericQtAppSnapshot(
        windowTitle: "Quill IINA",
        minimumWidth: 960,
        minimumHeight: 600,
        defaultWidth: 1080,
        defaultHeight: 660,
        sidebarTitle: "IINA",
        sidebarSubtitle: "Media player",
        primaryActionTitle: "Open media",
        secondaryActionTitle: "Playlist",
        listTitle: "Playlist",
        status: "Paused at 01:24",
        selectedIndex: 1,
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.iina
        ),
        detailTitle: "Player chrome",
        detailSubtitle: "Player layout with playlist, inspector, and playback status.",
        items: [
            .init(
                title: "Launch trailer",
                subtitle: "1080p H.264",
                badge: "3:12",
                detailSubtitle: "Video playlist item with transport controls visible.",
                sections: [
                    .init(title: "Now playing", body: "The trailer row keeps codec, duration, and playback state in the detail surface."),
                    .init(title: "Inspector", body: "Playlist selection updates metadata without replacing the native Qt window.")
                ]
            ),
            .init(
                title: "Conference demo",
                subtitle: "720p VP9",
                badge: "1:24",
                detailSubtitle: "Conference demo selected in the playlist.",
                sections: [
                    .init(title: "Now playing", body: "The selected row keeps codec, elapsed time, and paused state visible."),
                    .init(title: "Performance", body: "The player surface updates metadata without replacing the surrounding controls.")
                ]
            ),
            .init(
                title: "Audio sample",
                subtitle: "AAC stereo",
                badge: "0:48",
                detailSubtitle: "Audio-only playlist item selected.",
                sections: [
                    .init(title: "Now playing", body: "Audio-only selection swaps video metadata for waveform and channel context."),
                    .init(title: "Playlist detail", body: "The lower row keeps a distinct detail surface for audio playback.")
                ]
            )
        ],
        sections: [
            .init(title: "Transport controls", body: "The player exposes a steady hierarchy for playback state, duration, and metadata."),
            .init(title: "Playlist", body: "Playlist rows keep titles, durations, codecs, and selected-state detail easy to compare.")
        ]
    )

    public static let solderScope = QuillGenericQtAppSnapshot(
        windowTitle: "SolderScope",
        minimumWidth: 960,
        minimumHeight: 600,
        defaultWidth: 1280,
        defaultHeight: 720,
        sidebarTitle: "SolderScope",
        sidebarSubtitle: "USB microscope viewer",
        primaryActionTitle: "Snapshot",
        secondaryActionTitle: "Record",
        listTitle: "Cameras",
        status: "No camera connected",
        selectedIndex: 0,
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(),
        detailTitle: "Viewport",
        detailSubtitle: "Live microscope viewport with zoom, calibration, and capture controls.",
        items: [
            .init(
                title: "USB 2.0 Camera",
                subtitle: "1600x1200 YUYV",
                badge: "25 fps",
                detailSubtitle: "Live viewport with the floating tool pill (zoom, scale bar, flip, rotate).",
                sections: [
                    .init(title: "View controls", body: "Zoom 1-8x, flip horizontal/vertical, rotate in 90-degree steps; the status HUD keeps FPS, resolution, and zoom visible."),
                    .init(title: "Capture", body: "Snapshot writes PNG; recording encodes H.264 into .mov via the AVAssetWriter surface.")
                ]
            ),
            .init(
                title: "No camera",
                subtitle: "Connect a USB microscope to begin",
                badge: "idle",
                detailSubtitle: "Empty state matching the GTK and macOS renders.",
                sections: [
                    .init(title: "Discovery", body: "Cameras enumerate from /dev/video*; YUYV-capable devices negotiate automatically on start."),
                    .init(title: "Calibration", body: "Draw a line over a feature of known length to set microns-per-pixel; the scale bar tracks zoom.")
                ]
            )
        ],
        sections: [
            .init(title: "Toolbar", body: "A floating pill keeps camera picker, zoom, scale bar, flip/rotate, pause, snapshot, and record in one row."),
            .init(title: "Status", body: "FPS, capture resolution, and zoom factor stay pinned to the lower-right corner of the viewport.")
        ]
    )
}

public enum QuillGenericQtNativeApp {
    public static func run(_ snapshot: QuillGenericQtAppSnapshot) -> Never {
        var launchSnapshot = snapshot
        if let selectedIndex = QuillQtNativeRuntimeSupport.boundedIndexOverride(
            environmentKeys: launchSnapshot.selectedIndexEnvironmentKeys,
            count: launchSnapshot.items.count
        ) {
            launchSnapshot.selectedIndex = selectedIndex
        }

        QuillQtNativeRuntimeSupport.runEncodedPayload(
            launchSnapshot,
            executableName: QuillQtNativeRuntimeSupport.executableName(fallback: "quill-generic-qt")
        ) { payloadPointer in
            quill_generic_qt_run_app_json(
                CommandLine.argc,
                CommandLine.unsafeArgv,
                payloadPointer
            )
        }
    }
}
#endif
