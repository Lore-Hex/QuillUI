// Buggy outer `#if !os(macOS) && !os(iOS) && !os(visionOS)` removed —
// it was making every public type below (QuillFloatingIconButton,
// QuillSystemSymbol, etc.) invisible on macOS even though the inner
// branches looked correct.
import Foundation
import Dispatch
import QuillKit
import QuillPaint
#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

public enum QuillSystemSymbol {
    public static func compatibleName(_ systemName: String) -> String {
        #if os(macOS) || os(iOS) || os(visionOS)
        return systemName
        #else
        switch systemName {
        case "xmark", "x.circle", "x.circle.fill":
            return "xmark.circle.fill"
        default:
            return systemName
        }
        #endif
    }
}

public struct QuillFloatingIconButton: View {
    public var systemImage: String
    private var action: () -> Void

    public init(systemImage: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: QuillSystemSymbol.compatibleName(systemImage))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.primary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(QuillGrowingButtonStyle())
        .contentShape(Rectangle())
    }
}

public struct QuillGrowingButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.12 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

public struct QuillPrompt: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var systemImage: String

    public init(id: String? = nil, title: String, systemImage: String) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
    }

    public static func selectedPrompts<Item>(
        from source: [Item],
        preferredTitles: [String],
        fallbackCount: Int = 4,
        id: (Item) -> String,
        title: (Item) -> String,
        systemImage: (Item) -> String
    ) -> [QuillPrompt] {
        let preferredItems = preferredTitles.compactMap { preferredTitle in
            source.first { title($0) == preferredTitle }
        }
        let selectedItems = preferredItems.count == preferredTitles.count
            ? preferredItems
            : Array(source.prefix(max(0, fallbackCount)))

        return selectedItems.map { item in
            QuillPrompt(id: id(item), title: title(item), systemImage: systemImage(item))
        }
    }
}

public struct QuillPromptGridLayout: Equatable, Sendable {
    public var columns: Int
    public var cardWidth: CGFloat
    public var cardHeight: CGFloat
    public var spacing: Int

    public init(
        columns: Int = 4,
        cardWidth: CGFloat = 155,
        cardHeight: CGFloat = 128,
        spacing: Int = 15
    ) {
        self.columns = max(1, columns)
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.spacing = spacing
    }

    public static let compactCards = QuillPromptGridLayout()
    public static let wideDesktopCards = QuillPromptGridLayout(
        columns: 4,
        cardWidth: 302,
        cardHeight: 128,
        spacing: 15
    )
}

private extension String {
    var quillPromptGridDisplayTitle: String {
        #if os(macOS) || os(iOS) || os(visionOS)
        return self
        #else
        var lines: [String] = []
        var current = ""

        let maxLines = 5

        for word in split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > 15, !current.isEmpty {
                lines.append(current)
                current = String(word)
                if lines.count == maxLines { break }
            } else {
                current = candidate
            }
        }

        if lines.count < maxLines, !current.isEmpty {
            lines.append(current)
        }

        if lines.count == maxLines, lines.joined(separator: " ").count < count {
            lines[maxLines - 1] = lines[maxLines - 1].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return lines.joined(separator: "\n")
        #endif
    }
}

#if !(os(macOS) || os(iOS) || os(visionOS))
private func quillBackendEnvironmentDouble(
    _ canonical: String,
    gtkLegacy: String,
    qtScoped: String
) -> Double? {
    let environment = ProcessInfo.processInfo.environment
    return QuillBackendRegistry
        .backendScopedEnvironmentValue(
            canonical,
            gtkLegacy: gtkLegacy,
            qtScoped: qtScoped,
            from: environment,
            preferred: QuillBackendRuntimeContext.selectedBackend
        )
        .flatMap(Double.init)
}

private var quillBackendReferenceWindowWidth: Double? {
    quillBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH",
        gtkLegacy: "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH",
        qtScoped: "QUILLUI_QT_DEFAULT_WINDOW_WIDTH"
    )
}

private var quillBackendReferenceWindowHeight: Double? {
    quillBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT",
        gtkLegacy: "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT",
        qtScoped: "QUILLUI_QT_DEFAULT_WINDOW_HEIGHT"
    )
}
#endif

public struct QuillPromptList: View {
    public var prompts: [QuillPrompt]
    public var rowWidth: CGFloat
    public var action: (QuillPrompt) -> Void

    public init(
        prompts: [QuillPrompt],
        rowWidth: CGFloat = 620,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.prompts = prompts
        self.rowWidth = rowWidth
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(prompts) { prompt in
                Button(action: { action(prompt) }) {
                    HStack(spacing: 12) {
                        Image(systemName: QuillSystemSymbol.compatibleName(prompt.systemImage))
                            .frame(width: 24)
                        Text(prompt.title)
                            .frame(width: max(80, rowWidth - 80), alignment: .leading)
                    }
                    .padding(14)
                    .frame(width: rowWidth, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

public struct QuillPromptGrid: View {
    public var prompts: [QuillPrompt]
    public var columns: Int
    public var cardWidth: CGFloat
    public var cardHeight: CGFloat
    public var spacing: Int
    public var action: (QuillPrompt) -> Void

    public init(
        prompts: [QuillPrompt],
        layout: QuillPromptGridLayout,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.prompts = prompts
        self.columns = layout.columns
        self.cardWidth = layout.cardWidth
        self.cardHeight = layout.cardHeight
        self.spacing = layout.spacing
        self.action = action
    }

    public init(
        prompts: [QuillPrompt],
        columns: Int = 4,
        cardWidth: CGFloat = 155,
        cardHeight: CGFloat = 128,
        spacing: Int = 15,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.init(
            prompts: prompts,
            layout: QuillPromptGridLayout(
                columns: columns,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                spacing: spacing
            ),
            action: action
        )
    }

    public var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing) {
            ForEach(prompts) { prompt in
                promptButton(prompt)
            }
        }
    }

    #if os(macOS) || os(iOS) || os(visionOS)
    private var gridSpacing: CGFloat { CGFloat(spacing) }
    #else
    private var gridSpacing: Double { Double(spacing) }
    #endif

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns)
    }

    @ViewBuilder
    private func promptButton(_ prompt: QuillPrompt) -> some View {
        Button(action: { action(prompt) }) {
            promptCard(prompt)
        }
        .quillPaint(.macBordered)
        .accessibilityLabel(prompt.title)
        .help(prompt.title)
    }

    private func promptCard(_ prompt: QuillPrompt) -> some View {
        promptCardContent(prompt)
            .padding(promptCardPadding)
            // Wide branch (single-column macOS slice) keeps a fixed width; narrow
            // branch (multi-column row, e.g. Enchanted's genuine 4-card empty
            // state) fills its flexible LazyVGrid slot so the cards form an even
            // row like the real macOS app instead of fixed-width cards with a
            // ragged right edge.
            .frame(
                maxWidth: cardWidth >= 400 ? cardWidth : .infinity,
                minHeight: cardHeight,
                maxHeight: cardHeight,
                alignment: .leading
            )
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func promptCardContent(_ prompt: QuillPrompt) -> some View {
        if cardWidth >= 400 {
            // Wide single-column row (macOS Enchanted parity): icon-left, one line
            // of text, vertically centered. Used by the core app + upstream slice.
            HStack(spacing: 10) {
                promptAccessory(for: prompt)
                Text(prompt.title)
                    .font(.system(size: promptFontSize))
                    .foregroundColor(Color(hex: "#1D1D1F"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else {
            // Narrow multi-column card: wrapped title top-left, icon bottom-right.
            // Kept for the generated upstream profile's 2-column grid (a single
            // truncated line there is too little text for the visual-smoke budget).
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(height: promptCardContentHeight)

                Text(prompt.title.quillPromptGridDisplayTitle)
                    .font(.system(size: promptFontSize))
                    .foregroundColor(Color(hex: "#1D1D1F"))
                    // Fill the (flexible) card width instead of a FIXED width — a
                    // fixed cardWidth-based title kept each card ~272pt wide so the
                    // 4-card row could not shrink to fit a narrow detail pane and
                    // overflowed off the right edge. maxWidth:.infinity lets the card
                    // shrink with its LazyVGrid column.
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        promptAccessory(for: prompt)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: promptCardContentHeight,
                    maxHeight: promptCardContentHeight,
                    alignment: .bottomTrailing
                )
            }
        }
    }

    private var promptFontSize: CGFloat {
        #if os(Linux)
        cardHeight >= 220 ? 24 : 15
        #else
        15
        #endif
    }
    #if os(macOS) || os(iOS) || os(visionOS)
    private var promptCardPadding: CGFloat { 15 }
    #else
    private var promptCardPadding: Int { 15 }
    #endif
    private var promptCardPaddingWidth: CGFloat { CGFloat(promptCardPadding) }
    private var promptCardContentHeight: CGFloat {
        max(1, cardHeight - (promptCardPaddingWidth * 2))
    }
    private var promptIconSize: CGFloat { 16 }

    private var cardBackgroundColor: Color {
        QuillDesktopChromeStyle.promptCardBackground
    }

    @ViewBuilder
    private func promptAccessory(for prompt: QuillPrompt) -> some View {
        if prompt.systemImage.lowercased().contains("questionmark") {
            // Draw the circled "?" directly so it renders cleanly on every
            // backend. The mapped Material glyph (help_outline) renders as a
            // broken partial arc on GTK — matching the genuine native app's
            // clean "?" circle is more reliable with an explicit Circle + Text.
            ZStack {
                Circle()
                    .stroke(Color(hex: "#2E2E31"), lineWidth: 1.3)
                Text("?")
                    .font(.system(size: promptIconSize * 0.62, weight: .medium))
                    .foregroundColor(Color(hex: "#2E2E31"))
            }
            .frame(width: promptIconSize, height: promptIconSize)
        } else if prompt.systemImage.lowercased().contains("lightbulb") {
            // Same approach for the action prompts: draw the circle, overlay the
            // bulb with primitive shapes, matching the genuine app's circled
            // bulb without relying on tiny Material Symbol glyph rendering.
            ZStack {
                Circle()
                    .stroke(Color(hex: "#2E2E31"), lineWidth: 1.3)
                QuillPromptLightbulbGlyph(color: Color(hex: "#2E2E31"))
            }
            .frame(width: promptIconSize, height: promptIconSize)
        } else {
            Image(systemName: QuillSystemSymbol.compatibleName(prompt.systemImage))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: promptIconSize, height: promptIconSize)
                .foregroundColor(Color(hex: "#2E2E31"))
        }
    }
}

private struct QuillPromptLightbulbGlyph: View {
    var color: Color

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .stroke(color, lineWidth: 1.1)
                .frame(width: 5.8, height: 5.8)
            Rectangle()
                .fill(color)
                .frame(width: 3.3, height: 2)
            Rectangle()
                .fill(color)
                .frame(width: 5.2, height: 1.2)
        }
        .frame(width: 8, height: 10, alignment: .center)
    }
}

public struct QuillConversationHistoryItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var lastMessage: String
    public var updatedAt: Date

    public init(id: String, title: String, updatedAt: Date, lastMessage: String = "") {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
    }
}

public enum QuillDesktopChromeStyle {
    public static var sidebarBackground: Color {
        Color(red: 0.91, green: 0.93, blue: 0.89)
    }

    public static var detailBackground: Color {
        Color(hex: "#FAFAFA")
    }

    public static var cardBackground: Color {
        Color.white
    }

    public static var promptCardBackground: Color {
        Color(red: 0.925, green: 0.93, blue: 0.955)
    }

    public static var selectedRowBackground: Color {
        Color(red: 0.88, green: 0.94, blue: 1.0)
    }

    public static var selectedRowCornerRadius: CGFloat {
        #if os(Linux)
        return 7
        #else
        return 6
        #endif
    }
}

public struct QuillConversationHistoryList: View {
    public var items: [QuillConversationHistoryItem]
    public var selectedID: String?
    public var emptyTitle: String
    public var emptySubtitle: String
    public var onSelect: (QuillConversationHistoryItem) -> Void
    @State private var hoveredItemID: String?

    public init(
        items: [QuillConversationHistoryItem],
        selectedID: String? = nil,
        emptyTitle: String = "No saved chats yet",
        emptySubtitle: String = "Start a chat and it will be saved locally.",
        onSelect: @escaping (QuillConversationHistoryItem) -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: listSpacing) {
                if sortedItems.isEmpty {
                    emptyHistory
                } else {
                    ForEach(sortedItems) { item in
                        let isSelected = selectedID == item.id
                        let isHovered = hoveredItemID == item.id
                        let rowState = PaintControlState(isHovered: isHovered, isSelected: isSelected)
                        let lastMessage = lastMessagePreview(for: item)
                        VStack(alignment: .leading, spacing: rowTextSpacing) {
                            Text(item.title)
                                .font(.system(size: rowFontSize))
                                .lineLimit(1)
                                .foregroundColor(rowTitleColor(for: rowState))

                            if !lastMessage.isEmpty {
                                Text(lastMessage)
                                    .font(.system(size: rowPreviewFontSize))
                                    .lineLimit(2)
                                    .foregroundColor(rowPreviewColor(for: rowState))
                            }
                        }
                        .padding(rowPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(rowBackgroundColor(for: rowState))
                        .cornerRadius(rowCornerRadius)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.lastMessage)
                        .help(accessibilitySummary(for: item))
                        .onHover { hovering in
                            hoveredItemID = hovering ? item.id : nil
                        }
                        .onTapGesture { onSelect(item) }
                    }
                }
            }
        }
    }

    private var rowFontSize: CGFloat { 15 }
    private var rowPreviewFontSize: CGFloat { 12 }
    private var rowPadding: CGFloat { 11 }
    private var rowTextSpacing: CGFloat { 5 }
    private var rowCornerRadius: CGFloat { CGFloat(MacMetrics.ListRow.cornerRadius) }
    private var listSpacing: CGFloat { 8 }
    private var emptyTitleFontSize: CGFloat { 15 }
    private var emptySubtitleFontSize: CGFloat { 12 }
    private var emptyTitleFontWeight: Font.Weight { .bold }
    private var emptyHistoryPadding: CGFloat { 12 }
    private var emptyHistorySpacing: CGFloat { 8 }
    private var emptyHistoryCornerRadius: CGFloat { 8 }

    private var rowBackgroundColor: Color { Color(quillPaint: MacColors.controlBackground) }
    private var rowTitleColor: Color { rowTitleColor(for: .normal) }
    private var rowPreviewColor: Color { rowPreviewColor(for: .normal) }

    private func rowBackgroundColor(for state: PaintControlState) -> Color {
        Color(quillPaint: MacListRowPaint.effectiveFillColor(for: state))
    }

    private func rowTitleColor(for state: PaintControlState) -> Color {
        Color(quillPaint: MacListRowPaint.primaryTextColor(for: state))
    }

    private func rowPreviewColor(for state: PaintControlState) -> Color {
        Color(quillPaint: MacListRowPaint.secondaryTextColor(for: state))
    }

    private var sortedItems: [QuillConversationHistoryItem] {
        items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: emptyHistorySpacing) {
            Text(emptyTitle)
                .font(.system(size: emptyTitleFontSize, weight: emptyTitleFontWeight))
                .foregroundColor(rowTitleColor)
            Text(emptySubtitle)
                .font(.system(size: emptySubtitleFontSize))
                .foregroundColor(rowPreviewColor)
        }
        .padding(emptyHistoryPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundColor)
        .cornerRadius(emptyHistoryCornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(emptyTitle)
        .accessibilityValue(emptySubtitle)
        .help(emptySubtitle)
    }

    private func accessibilitySummary(for item: QuillConversationHistoryItem) -> String {
        let lastMessage = lastMessagePreview(for: item)
        guard !lastMessage.isEmpty else { return item.title }
        return "\(item.title)\n\(lastMessage)"
    }

    private func lastMessagePreview(for item: QuillConversationHistoryItem) -> String {
        item.lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct QuillConversationHistoryDayGroup: Identifiable {
    var date: Date
    var items: [QuillConversationHistoryItem]

    var id: Date { date }
}

public struct QuillDateGroupedConversationHistoryList: View {
    public var items: [QuillConversationHistoryItem]
    public var selectedID: String?
    public var dateTitle: (Date) -> String
    public var deleteDayTitle: String
    public var deleteItemTitle: String
    public var onSelect: (QuillConversationHistoryItem) -> Void
    public var onDelete: ((QuillConversationHistoryItem) -> Void)?
    public var onDeleteDay: ((Date) -> Void)?

    @State private var hoveredItemID: String?

    public init(
        items: [QuillConversationHistoryItem],
        selectedID: String? = nil,
        dateTitle: @escaping (Date) -> String,
        deleteDayTitle: String = "Delete daily conversations",
        deleteItemTitle: String = "Delete",
        onSelect: @escaping (QuillConversationHistoryItem) -> Void,
        onDelete: ((QuillConversationHistoryItem) -> Void)? = nil,
        onDeleteDay: ((Date) -> Void)? = nil
    ) {
        self.items = items
        self.selectedID = selectedID
        self.dateTitle = dateTitle
        self.deleteDayTitle = deleteDayTitle
        self.deleteItemTitle = deleteItemTitle
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onDeleteDay = onDeleteDay
    }

    public init<SourceItem>(
        items: [SourceItem],
        selectedID: String? = nil,
        id: @escaping (SourceItem) -> String,
        title: @escaping (SourceItem) -> String,
        updatedAt: @escaping (SourceItem) -> Date,
        lastMessage: @escaping (SourceItem) -> String = { _ in "" },
        dateTitle: @escaping (Date) -> String,
        deleteDayTitle: String = "Delete daily conversations",
        deleteItemTitle: String = "Delete",
        onSelect: @escaping (SourceItem) -> Void,
        onDelete: ((SourceItem) -> Void)? = nil,
        onDeleteDay: ((Date) -> Void)? = nil
    ) {
        var sourceItemsByID: [String: SourceItem] = [:]
        let historyItems = items.map { item in
            let itemID = id(item)
            sourceItemsByID[itemID] = item
            return QuillConversationHistoryItem(
                id: itemID,
                title: title(item),
                updatedAt: updatedAt(item),
                lastMessage: lastMessage(item)
            )
        }

        self.init(
            items: historyItems,
            selectedID: selectedID,
            dateTitle: dateTitle,
            deleteDayTitle: deleteDayTitle,
            deleteItemTitle: deleteItemTitle,
            onSelect: { item in
                if let sourceItem = sourceItemsByID[item.id] {
                    onSelect(sourceItem)
                }
            },
            onDelete: onDelete.map { delete in
                { item in
                    if let sourceItem = sourceItemsByID[item.id] {
                        delete(sourceItem)
                    }
                }
            },
            onDeleteDay: onDeleteDay
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: groupedListSpacing) {
                ForEach(dayGroups) { group in
                    HStack {
                        Text(dateTitle(group.date))
                            .font(.system(size: groupedSectionFontSize))
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "#8F8F96"))
                            .padding(.bottom, groupedSectionBottomPadding)

                        Spacer()
                    }
                    .contextMenu(menuItems: {
                        dayContextMenu(for: group.date)
                    })

                    ForEach(group.items) { item in
                        groupedRow(for: item)
                    }

                    Divider()
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var dayGroups: [QuillConversationHistoryDayGroup] {
        Dictionary(grouping: items) { item in
            Calendar.current.startOfDay(for: item.updatedAt)
        }
        .map { date, items in
            QuillConversationHistoryDayGroup(
                date: date,
                items: items.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
        .sorted { $0.date > $1.date }
    }

    private func groupedRow(for item: QuillConversationHistoryItem) -> some View {
        let isSelected = selectedID == item.id
        let isHovered = hoveredItemID == item.id
        let textState = PaintControlState(isHovered: isHovered, isSelected: false)

        return HStack {
            if isSelected {
                Circle()
                    .frame(width: groupedSelectionDotSize, height: groupedSelectionDotSize)
                    .transition(.opacity)
            }

            Text(item.title)
                .lineLimit(1)
                .font(.system(size: groupedRowFontSize))
                .foregroundColor(Color(quillPaint: MacListRowPaint.primaryTextColor(for: textState)))
                .transition(.opacity)

            Spacer()
        }
        .padding(.vertical, groupedRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: groupedRowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .help(item.title)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
        .onTapGesture { onSelect(item) }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu(menuItems: {
            itemContextMenu(for: item)
        })
    }

    @ViewBuilder
    private func dayContextMenu(for date: Date) -> some View {
        if let onDeleteDay {
            Button(role: .destructive, action: { onDeleteDay(date) }) {
                Label(deleteDayTitle, systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: QuillConversationHistoryItem) -> some View {
        if let onDelete {
            Button(role: .destructive, action: { onDelete(item) }) {
                Label(deleteItemTitle, systemImage: "trash")
            }
        }
    }

    #if os(Linux)
    private var groupedSectionFontSize: CGFloat { 24 }
    private var groupedRowFontSize: CGFloat { 23 }
    private var groupedRowMinHeight: CGFloat { 48 }
    private var groupedRowVerticalPadding: CGFloat { 10 }
    private var groupedSelectionDotSize: CGFloat { 8 }
    #else
    private var groupedSectionFontSize: CGFloat { 14 }
    private var groupedRowFontSize: CGFloat { 16 }
    private var groupedRowMinHeight: CGFloat { 32 }
    private var groupedRowVerticalPadding: CGFloat { 12 }
    private var groupedSelectionDotSize: CGFloat { 6 }
    #endif
    private var groupedListSpacing: CGFloat { 17 }
    private var groupedSectionBottomPadding: CGFloat { 30 }
}

private extension Color {
    init(quillPaint color: PaintColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

public struct QuillSidebarNavigationAction: Identifiable {
    public var id: String
    public var title: String
    public var systemImage: String
    private var action: () -> Void

    public init(
        id: String? = nil,
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public func perform() {
        action()
    }

    public static func completions(action: @escaping () -> Void) -> QuillSidebarNavigationAction {
        QuillSidebarNavigationAction(title: "Completions", systemImage: "textformat.abc", action: action)
    }

    public static func shortcuts(action: @escaping () -> Void) -> QuillSidebarNavigationAction {
        QuillSidebarNavigationAction(title: "Shortcuts", systemImage: "keyboard.fill", action: action)
    }

    public static func settings(action: @escaping () -> Void) -> QuillSidebarNavigationAction {
        QuillSidebarNavigationAction(title: "Settings", systemImage: "gearshape.fill", action: action)
    }

    public static func desktopChatUtilities(
        onCompletions: @escaping () -> Void,
        onShortcuts: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> [QuillSidebarNavigationAction] {
        #if os(macOS) || os(Linux)
        return [
            .completions(action: onCompletions),
            .shortcuts(action: onShortcuts),
            .settings(action: onSettings)
        ]
        #else
        return [
            .settings(action: onSettings)
        ]
        #endif
    }

    public static func desktopChatUtilityToggles(
        showCompletions: Binding<Bool>,
        showShortcuts: Binding<Bool>,
        showSettings: Binding<Bool>,
        onSettings: @escaping () -> Void = {}
    ) -> [QuillSidebarNavigationAction] {
        desktopChatUtilities(
            onCompletions: { showCompletions.wrappedValue.toggle() },
            onShortcuts: { showShortcuts.wrappedValue.toggle() },
            onSettings: {
                showSettings.wrappedValue.toggle()
                onSettings()
            }
        )
    }
}

public struct QuillSidebarBottomNavigation: View {
    public var actions: [QuillSidebarNavigationAction]

    public init(actions: [QuillSidebarNavigationAction]) {
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(actions) { action in
                QuillSidebarNavigationButton(
                    title: action.title,
                    systemImage: action.systemImage,
                    action: action.perform
                )
            }
        }
    }
}

public struct QuillDesktopSidebar<Content: View>: View {
    public var bottomActions: [QuillSidebarNavigationAction]
    private var content: Content

    public init(
        bottomActions: [QuillSidebarNavigationAction],
        @ViewBuilder content: () -> Content
    ) {
        self.bottomActions = bottomActions
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .padding(.bottom, 24)

            QuillSidebarBottomNavigation(actions: bottomActions)
                .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 88)
        .padding(.bottom, 18)
    }
}

public extension View {
    @ViewBuilder
    func quillDesktopChatUtilitySheets<
        SettingsContent: View,
        CompletionsContent: View,
        ShortcutsContent: View
    >(
        showSettings: Binding<Bool>,
        showCompletions: Binding<Bool>,
        showShortcuts: Binding<Bool>,
        settingsFocusedValue: WritableKeyPath<FocusedValues, Binding<Bool>?>? = nil,
        @ViewBuilder settings: @escaping () -> SettingsContent,
        @ViewBuilder completions: @escaping () -> CompletionsContent,
        @ViewBuilder shortcuts: @escaping () -> ShortcutsContent
    ) -> some View {
        #if os(macOS) || os(Linux)
        if let settingsFocusedValue {
            self
                .focusedSceneValue(settingsFocusedValue, showSettings)
                .sheet(isPresented: showSettings) {
                    settings()
                }
                .sheet(isPresented: showCompletions) {
                    completions()
                }
                .sheet(isPresented: showShortcuts) {
                    shortcuts()
                }
        } else {
            self
                .sheet(isPresented: showSettings) {
                    settings()
                }
                .sheet(isPresented: showCompletions) {
                    completions()
                }
                .sheet(isPresented: showShortcuts) {
                    shortcuts()
                }
        }
        #else
        self
            .sheet(isPresented: showSettings) {
                settings()
            }
        #endif
    }

    func quillSyncEditableMessage<Message: Equatable>(
        _ editMessage: Binding<Message?>,
        draft: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        content: @escaping (Message) -> String
    ) -> some View {
        onChange(of: editMessage.wrappedValue, initial: false) { _, newMessage in
            if let newMessage {
                draft.wrappedValue = content(newMessage)
                isFocused.wrappedValue = true
            }
        }
    }
}

public struct QuillSidebarNavigationButton: View {
    public var title: String
    public var systemImage: String
    private var action: () -> Void

    public init(title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                sidebarIcon
                    .frame(width: 24, height: 20, alignment: .leading)

                Text(title)
                    .lineLimit(1)
                    .font(.system(size: navigationFontSize))

                Spacer()
            }
            .foregroundColor(Color(hex: "#3A3A3C"))
            .frame(maxWidth: .infinity, minHeight: navigationRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(Linux)
    private var navigationFontSize: CGFloat { 20 }
    private var navigationRowHeight: CGFloat { 34 }
    #else
    private var navigationFontSize: CGFloat { 15 }
    private var navigationRowHeight: CGFloat { 24 }
    #endif

    @ViewBuilder
    private var sidebarIcon: some View {
        #if os(Linux)
        if systemImage == "textformat.abc" {
            Text("Abc")
                .font(.system(size: 13, weight: .regular))
                .frame(width: 24, height: 20, alignment: .leading)
        } else if systemImage == "keyboard" || systemImage == "keyboard.fill" {
            QuillSidebarKeyboardGlyph(color: Color(hex: "#3A3A3C"))
                .frame(width: 24, height: 20, alignment: .leading)
        } else if systemImage == "gearshape" || systemImage == "gearshape.fill" || systemImage == "gear" {
            QuillSidebarGearGlyph(color: Color(hex: "#3A3A3C"))
                .frame(width: 24, height: 20, alignment: .leading)
        } else {
            Image(systemName: sidebarSystemImageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17, alignment: .center)
        }
        #else
        Image(systemName: sidebarSystemImageName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 17, height: 17, alignment: .center)
        #endif
    }

    private var sidebarSystemImageName: String {
        #if os(Linux)
        switch systemImage {
        case "character.cursor.ibeam", "textformat", "textformat.abc",
             "keyboard", "keyboard.fill",
             "gearshape", "gearshape.fill", "gear":
            return systemImage
        default:
            return QuillSystemSymbol.compatibleName(systemImage)
        }
        #else
        return QuillSystemSymbol.compatibleName(systemImage)
        #endif
    }
}

private struct QuillSidebarKeyboardGlyph: View {
    var color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(color, lineWidth: 1.3)
                .frame(width: 17, height: 11)

            VStack(spacing: 1.5) {
                HStack(spacing: 1.5) {
                    key
                    key
                    key
                    key
                    key
                }
                HStack(spacing: 1.5) {
                    key
                    Rectangle()
                        .fill(color)
                        .frame(width: 5.6, height: 1.4)
                    key
                }
            }
            .padding(.top, 1)
        }
        .frame(width: 17, height: 13, alignment: .center)
    }

    private var key: some View {
        Rectangle()
            .fill(color)
            .frame(width: 1.8, height: 1.4)
    }
}

private struct QuillSidebarGearGlyph: View {
    var color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: 3.2, height: 17)
            Rectangle()
                .fill(color)
                .frame(width: 17, height: 3.2)
            Circle()
                .fill(QuillDesktopChromeStyle.sidebarBackground)
                .frame(width: 11.2, height: 11.2)
            Circle()
                .stroke(color, lineWidth: 1.6)
                .frame(width: 10, height: 10)
            Circle()
                .fill(color)
                .frame(width: 3.3, height: 3.3)
        }
        .frame(width: 17, height: 17, alignment: .center)
    }
}

public struct QuillStatusBanner: View {
    public var message: String
    public var actionTitle: String?
    public var showsActivity: Bool
    private var action: (() -> Void)?

    public init(
        message: String,
        actionTitle: String? = nil,
        showsActivity: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.showsActivity = showsActivity
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 14) {
            Text(message)
                .font(.system(size: bannerFontSize))
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: "#2E2E2E"))
                .lineLimit(nil)
                .frame(width: messageWidth, alignment: .leading)

            Spacer(minLength: 0)

            if showsActivity {
                Circle()
                    .fill(Color(hex: "#2E2E31"))
                    .frame(width: activitySize, height: activitySize)
                    .padding(.horizontal, activityHorizontalPadding)
            }

            if let actionTitle {
                Button(action: {
                    action?()
                }) {
                    Text(actionTitle)
                        .font(.system(size: actionFontSize))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, actionHorizontalPadding)
                        .padding(.vertical, actionVerticalPadding)
                        .background(Color.black)
                        .cornerRadius(actionCornerRadius)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F5C8D2"))
        .cornerRadius(cornerRadius)
    }

    #if os(Linux)
    private var bannerFontSize: CGFloat { 24 }
    private var actionFontSize: CGFloat { 22 }
    private var messageWidth: Double? {
        guard let windowWidth = quillBackendReferenceWindowWidth, windowWidth >= 1600 else { return nil }
        let sidebarWidth = max(320, min(620, windowWidth * 0.285))
        let detailWidth = windowWidth - sidebarWidth - 1
        let availableTextWidth = detailWidth - 56 - 60 - 230
        return min(1180, max(760, availableTextWidth))
    }
    private var horizontalPadding: Int { 30 }
    private var verticalPadding: Int { 31 }
    private var cornerRadius: CGFloat { 16 }
    private var actionHorizontalPadding: Int { 20 }
    private var actionVerticalPadding: Int { 12 }
    private var actionCornerRadius: CGFloat { 24 }
    private var activitySize: CGFloat { 20 }
    private var activityHorizontalPadding: Int { 8 }
    #else
    private var bannerFontSize: CGFloat { 12 }
    private var actionFontSize: CGFloat { 12 }
    private var messageWidth: CGFloat? { nil }
    private var horizontalPadding: CGFloat { 16 }
    private var verticalPadding: CGFloat { 13 }
    private var cornerRadius: CGFloat { 9 }
    private var actionHorizontalPadding: CGFloat { 13 }
    private var actionVerticalPadding: CGFloat { 8 }
    private var actionCornerRadius: CGFloat { 14 }
    private var activitySize: CGFloat { 10 }
    private var activityHorizontalPadding: CGFloat { 0 }
    #endif
}

public struct QuillSheetStatusBanner<SheetContent: View>: View {
    public var message: String
    public var actionTitle: String
    public var showsActivity: Bool
    public var horizontalPadding: CGFloat
    public var topPadding: CGFloat
    public var bottomPadding: CGFloat
    private var sheetContent: () -> SheetContent

    @State private var isPresented = false

    public init(
        message: String,
        actionTitle: String,
        showsActivity: Bool = false,
        horizontalPadding: CGFloat = 0,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        @ViewBuilder sheet: @escaping () -> SheetContent
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.showsActivity = showsActivity
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.sheetContent = sheet
    }

    public var body: some View {
        QuillStatusBanner(
            message: message,
            actionTitle: actionTitle,
            showsActivity: showsActivity
        ) {
            isPresented.toggle()
        }
        .padding(.horizontal, resolvedHorizontalPadding)
        .padding(.top, resolvedTopPadding)
        .padding(.bottom, resolvedBottomPadding)
        .sheet(isPresented: $isPresented) {
            sheetContent()
        }
    }

    #if os(macOS) || os(iOS) || os(visionOS)
    private var resolvedHorizontalPadding: CGFloat { horizontalPadding }
    private var resolvedTopPadding: CGFloat { topPadding }
    private var resolvedBottomPadding: CGFloat { bottomPadding }
    #else
    private var resolvedHorizontalPadding: Int { Int(horizontalPadding.rounded()) }
    private var resolvedTopPadding: Int { Int(topPadding.rounded()) }
    private var resolvedBottomPadding: Int { Int(bottomPadding.rounded()) }
    #endif
}

public struct QuillMacWindowControls: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(Color(hex: "#FF605C"))
                Circle().fill(Color(hex: "#FFBD44"))
                Circle().fill(Color(hex: "#00CA4E"))
            }
            .frame(width: 82, height: 14, alignment: .leading)

            Color.clear
                .frame(width: 48, height: 1)

            sidebarToggleGlyph
        }
        .frame(width: 176, height: 24, alignment: .leading)
    }

    private var sidebarToggleGlyph: some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(Color(hex: "#6F7072"), lineWidth: 1.6)
            .frame(width: 24, height: 24)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(hex: "#6F7072"))
                    .frame(width: 1.4, height: 17)
                    .padding(.leading, 7)
            }
    }
}

private struct QuillPromptGridMetrics {
    var cardWidth: CGFloat
    var cardHeight: CGFloat
    var spacing: Int
    var gridWidth: CGFloat
}

public struct QuillChatEmptyState: View {
    public var brandTitle: String
    public var prompts: [QuillPrompt]
    public var columns: Int
    public var cardWidth: CGFloat
    public var cardHeight: CGFloat
    public var spacing: Int
    public var action: (QuillPrompt) -> Void

    public init(
        brandTitle: String = "Quill",
        prompts: [QuillPrompt],
        layout: QuillPromptGridLayout,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.brandTitle = brandTitle
        self.prompts = prompts
        self.columns = layout.columns
        self.cardWidth = layout.cardWidth
        self.cardHeight = layout.cardHeight
        self.spacing = layout.spacing
        self.action = action
    }

    public init(
        brandTitle: String = "Quill",
        prompts: [QuillPrompt],
        columns: Int = 4,
        cardWidth: CGFloat = 155,
        cardHeight: CGFloat = 128,
        spacing: Int = 15,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.init(
            brandTitle: brandTitle,
            prompts: prompts,
            layout: QuillPromptGridLayout(
                columns: columns,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                spacing: spacing
            ),
            action: action
        )
    }

    public var body: some View {
        #if os(Linux)
        if let referenceHeight = Self.referenceHeight {
            linuxReferenceEmptyStateContent
                .frame(height: referenceHeight, alignment: .top)
        } else {
            emptyStateContent
                .frame(maxHeight: 980)
        }
        #else
        emptyStateContent
        #endif
    }

    #if os(Linux)
    private static var referenceHeight: CGFloat? {
        guard let windowHeight = quillBackendReferenceWindowHeight, windowHeight >= 1200 else { return nil }
        return CGFloat(min(900, max(740, windowHeight * 0.64)))
    }

    private var linuxReferenceEmptyStateContent: some View {
        GeometryReader { geometry in
            let metrics = promptGridMetrics(totalWidth: Double(geometry.size.width))
            // Never let the row exceed the pane width (otherwise it overflows and
            // anchors to an edge); constrain the grid to the available width so the
            // flexible cards shrink to fit. Flanking Spacers force horizontal
            // centering — GTK did not honor the .frame(maxWidth:.infinity,
            // alignment:) centering here (the content anchored to the right edge).
            let available = max(160, CGFloat(geometry.size.width) - 56)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 78) {
                    wordmark

                    QuillPromptGrid(
                        prompts: prompts,
                        columns: columns,
                        cardWidth: metrics.cardWidth,
                        cardHeight: metrics.cardHeight,
                        spacing: metrics.spacing,
                        action: action
                    )
                    .frame(maxWidth: min(metrics.gridWidth, available), alignment: .center)

                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 188)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
    #endif

    private var emptyStateContent: some View {
        GeometryReader { geometry in
            let metrics = promptGridMetrics(totalWidth: Double(geometry.size.width))
            // Force horizontal centering with flanking Spacers — GTK did not honor
            // the implicit centering of .frame(maxWidth: .infinity) here (the
            // wordmark + grid anchored to the right edge of the detail pane).
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: emptyStateVerticalSpacing) {
                    Spacer()
                    wordmark

                    QuillPromptGrid(
                        prompts: prompts,
                        columns: columns,
                        cardWidth: metrics.cardWidth,
                        cardHeight: metrics.cardHeight,
                        spacing: metrics.spacing,
                        action: action
                    )
                    // Constrain to the available width so the row can't overflow +
                    // anchor off-edge; flexible cards shrink to fit, then center.
                    .frame(maxWidth: min(metrics.gridWidth, max(160, CGFloat(geometry.size.width) - 56)), alignment: .center)

                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    #if os(macOS) || os(iOS) || os(visionOS)
    private var emptyStateVerticalSpacing: CGFloat { 40 }
    #else
    private var emptyStateVerticalSpacing: Int { 70 }
    #endif

    private func promptGridMetrics(totalWidth: Double) -> QuillPromptGridMetrics {
        var resolvedCardWidth = cardWidth
        var resolvedCardHeight = cardHeight
        var resolvedSpacing = spacing

        #if os(Linux)
        let horizontalInset: CGFloat = 28
        let availableWidth = max(240, CGFloat(totalWidth) - horizontalInset * 2)
        if columns <= 1 {
            // Single-column rows (macOS Enchanted parity): size the card to the
            // available pane width so the fixed card frame matches the flexible
            // LazyVGrid column. A fixed card WIDER than its column makes
            // SwiftOpenUI's GTK4 LazyVGrid relayout in a loop -- on the generated
            // upstream Enchanted profile that spun CPU to ~170% and blew the
            // CPU/RSS budget. Clamping the card to the column width avoids it.
            resolvedSpacing = max(12, spacing)
            resolvedCardWidth = min(cardWidth, availableWidth)
            if totalWidth >= 1200 {
                // Reference-window mode renders ~2x: fill the pane, taller row.
                resolvedCardWidth = min(CGFloat(totalWidth) * 0.86, availableWidth)
                resolvedCardHeight = max(cardHeight, 96)
            }
        } else if totalWidth >= 1200 {
            let visible = CGFloat(min(columns, max(1, prompts.count)))
            resolvedSpacing = 28
            let availableGridWidth = CGFloat(totalWidth) * 0.86
            let spacingWidth = CGFloat(max(0, Int(visible) - 1) * resolvedSpacing)
            let candidateWidth = (availableGridWidth - spacingWidth) / visible
            resolvedCardWidth = min(305, max(cardWidth, candidateWidth))
            resolvedCardHeight = max(cardHeight, 280)
        } else {
            // Multi-column at the standard (non-reference) window width. Clamp
            // each card to its flexible LazyVGrid column width — same rationale as
            // the single-column branch above. Without this, the fixed card frame
            // (e.g. the generated Enchanted profile's 302pt cards) is far WIDER
            // than its column in a ~1180pt window, so the row (gridWidth) overflows
            // the detail pane and is pushed flush-right, AND the over-wide fixed
            // card spins SwiftOpenUI's GTK4 LazyVGrid relayout and collapses it to
            // a single column. Clamping the card to its column width makes the
            // N-card row fit the pane — so .frame(width: gridWidth, alignment:
            // .center) can center it — and lets all `columns` columns render.
            let visible = CGFloat(min(columns, max(1, prompts.count)))
            let spacingWidth = CGFloat(max(0, Int(visible) - 1) * resolvedSpacing)
            let columnWidth = max(80, (availableWidth - spacingWidth) / visible)
            resolvedCardWidth = min(cardWidth, columnWidth)
        }
        #endif

        let resolvedGridWidth = gridWidth(cardWidth: resolvedCardWidth, spacing: resolvedSpacing)
        return QuillPromptGridMetrics(
            cardWidth: resolvedCardWidth,
            cardHeight: resolvedCardHeight,
            spacing: resolvedSpacing,
            gridWidth: resolvedGridWidth
        )
    }

    private func gridWidth(cardWidth: CGFloat, spacing: Int) -> CGFloat {
        let visibleColumns = min(columns, max(1, prompts.count))
        return (CGFloat(visibleColumns) * cardWidth) + CGFloat(max(0, visibleColumns - 1) * spacing)
    }

    @ViewBuilder
    private var wordmark: some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        Text(brandTitle)
            .font(Font.system(size: 46, weight: .thin))
            .multilineTextAlignment(.center)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: "4285f4"), Color(hex: "9b72cb"), Color(hex: "d96570")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        #else
        HStack(spacing: 0) {
            ForEach(Array(brandTitle.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .foregroundColor(linuxWordmarkColor(at: index))
                    .font(Font.system(size: 66, weight: .thin))
            }
        }
        .multilineTextAlignment(.center)
        #endif
    }

    #if !(os(macOS) || os(iOS) || os(visionOS))
    private func linuxWordmarkColor(at index: Int) -> Color {
        let colors = [
            Color(hex: "#657BE8"),
            Color(hex: "#8173DC"),
            Color(hex: "#A66FBF"),
            Color(hex: "#C76B8F"),
            Color(hex: "#D96570"),
        ]
        return colors[min(index, colors.count - 1)]
    }
    #endif
}

public struct QuillDesktopSplitLayout<Sidebar: View, ToolbarContent: View, Content: View>: View {
    public var title: String
    public var sidebarWidth: CGFloat
    public var toolbarHeight: CGFloat
    private var sidebar: Sidebar
    private var toolbarContent: ToolbarContent
    private var content: Content

    public init(
        title: String,
        sidebarWidth: CGFloat = 320,
        toolbarHeight: CGFloat = 48,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder toolbar: () -> ToolbarContent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sidebarWidth = sidebarWidth
        self.toolbarHeight = toolbarHeight
        self.sidebar = sidebar()
        self.toolbarContent = toolbar()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let resolvedSidebarWidth = resolvedSidebarWidth(totalWidth: Double(geometry.size.width))
            HStack(spacing: 0) {
                sidebar
                    .frame(width: resolvedSidebarWidth, alignment: .leading)
                    .background(QuillDesktopChromeStyle.sidebarBackground)
                    .overlay(alignment: .topLeading) {
                        #if os(Linux)
                        if Self.showsMacWindowControls {
                            QuillMacWindowControls()
                                .padding(.leading, 36)
                                .padding(.top, 17)
                        }
                        #endif
                    }

                Divider()

                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text(title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color(hex: "#444446"))
                        Spacer()
                        HStack(spacing: 14) {
                            toolbarContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: resolvedToolbarHeight, alignment: .center)
                    .background(QuillDesktopChromeStyle.detailBackground)

                    Divider()

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(QuillDesktopChromeStyle.detailBackground)
                }
            }
            .background(QuillDesktopChromeStyle.detailBackground)
        }
    }

    private func resolvedSidebarWidth(totalWidth: Double) -> CGFloat {
        #if os(Linux)
        guard totalWidth > 0 else { return sidebarWidth }
        return CGFloat(max(Double(sidebarWidth), min(620.0, totalWidth * 0.285)))
        #else
        return sidebarWidth
        #endif
    }

    #if os(Linux)
    private static var showsMacWindowControls: Bool {
        guard let windowHeight = quillBackendReferenceWindowHeight else { return false }
        return windowHeight >= 1200
    }

    private var resolvedToolbarHeight: CGFloat {
        Self.showsMacWindowControls ? max(toolbarHeight, 68) : toolbarHeight
    }
    #else
    private var resolvedToolbarHeight: CGFloat { toolbarHeight }
    #endif
}

public struct QuillMessageList<Message: Identifiable & Hashable, RowContent: View, OverlayContent: View>: View
where Message.ID: Hashable {
    public var messages: [Message]
    public var scrollToken: AnyHashable
    public var rowVerticalPadding: CGFloat
    public var rowHorizontalPadding: CGFloat
    private var actions: (Message) -> [QuillMenuAction]
    private var rowContent: (Message) -> RowContent
    private var overlayContent: () -> OverlayContent

    public init(
        messages: [Message],
        scrollToken: AnyHashable? = nil,
        rowVerticalPadding: CGFloat = 10,
        rowHorizontalPadding: CGFloat = 10,
        actions: @escaping (Message) -> [QuillMenuAction] = { _ in [] },
        @ViewBuilder row: @escaping (Message) -> RowContent,
        @ViewBuilder overlay: @escaping () -> OverlayContent
    ) {
        self.messages = messages
        self.scrollToken = scrollToken ?? Self.defaultScrollToken(for: messages)
        self.rowVerticalPadding = rowVerticalPadding
        self.rowHorizontalPadding = rowHorizontalPadding
        self.actions = actions
        self.rowContent = row
        self.overlayContent = overlay
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack {
                        ForEach(messages) { message in
                            rowContent(message)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .padding(.vertical, rowVerticalPadding)
                                .padding(.horizontal, rowHorizontalPadding)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    ForEach(actions(message)) { action in
                                        contextMenuItem(for: action)
                                    }
                                }
                                .id(message)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomSentinelID)
                    }
                }
                .onAppear {
                    scrollToBottom(scrollViewProxy)
                }
                .onChange(of: scrollToken) { _, _ in
                    scrollToBottom(scrollViewProxy)
                }
            }

            overlayContent()
        }
    }

    private static var bottomSentinelID: String { "quill-message-list-bottom" }

    private static func defaultScrollToken(for messages: [Message]) -> AnyHashable {
        AnyHashable(messages.map { AnyHashable($0.id) })
    }

    @ViewBuilder
    private func contextMenuItem(for action: QuillMenuAction) -> some View {
        switch action.kind {
        case .divider:
            Divider()
        case .item:
            Button(action: { action.perform() }) {
                if let systemImage = action.systemImage {
                    Label(action.title, systemImage: QuillSystemSymbol.compatibleName(systemImage))
                } else {
                    Text(action.title)
                }
            }
            .disabled(action.isDisabled)
        }
    }

    private func scrollToBottom(_ scrollViewProxy: ScrollViewProxy) {
        #if os(Linux)
        scrollViewProxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
        let deferredProxy = QuillUncheckedSendableScrollViewProxy(proxy: scrollViewProxy)
        DispatchQueue.main.async {
            deferredProxy.proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
        }
        #else
        if let last = messages.last {
            scrollViewProxy.scrollTo(last, anchor: .bottom)
        } else {
            scrollViewProxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
        }
        #endif
    }
}

private struct QuillUncheckedSendableScrollViewProxy: @unchecked Sendable {
    var proxy: ScrollViewProxy
}

public extension Array where Element: Identifiable, Element.ID: Hashable {
    func quillMessageListScrollToken(content: (Element) -> String) -> AnyHashable {
        let itemIDs = map { String(describing: $0.id) }.joined(separator: "|")
        let lastContent = last.map(content) ?? ""
        return AnyHashable(itemIDs + "|" + lastContent)
    }
}

public struct QuillDesktopChatScaffold<
    Sidebar: View,
    ToolbarContent: View,
    SelectedContent: View,
    EmptyContent: View,
    StatusContent: View,
    ComposerContent: View
>: View {
    public var title: String
    public var sidebarWidth: CGFloat
    public var composerMaxWidth: CGFloat
    public var composerHorizontalPadding: CGFloat
    public var composerVerticalPadding: CGFloat
    public var hasSelection: Bool
    public var showsStatus: Bool
    private var sidebar: Sidebar
    private var toolbarContent: ToolbarContent
    private var selectedContent: SelectedContent
    private var emptyContent: EmptyContent
    private var statusContent: StatusContent
    private var composerContent: ComposerContent

    public init(
        title: String,
        sidebarWidth: CGFloat = 320,
        composerMaxWidth: CGFloat = .infinity,
        composerHorizontalPadding: CGFloat = 40,
        composerVerticalPadding: CGFloat = 16,
        hasSelection: Bool,
        showsStatus: Bool = false,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder toolbar: () -> ToolbarContent,
        @ViewBuilder selectedContent: () -> SelectedContent,
        @ViewBuilder emptyContent: () -> EmptyContent,
        @ViewBuilder statusContent: () -> StatusContent,
        @ViewBuilder composer: () -> ComposerContent
    ) {
        self.title = title
        self.sidebarWidth = sidebarWidth
        self.composerMaxWidth = composerMaxWidth
        self.composerHorizontalPadding = composerHorizontalPadding
        self.composerVerticalPadding = composerVerticalPadding
        self.hasSelection = hasSelection
        self.showsStatus = showsStatus
        self.sidebar = sidebar()
        self.toolbarContent = toolbar()
        self.selectedContent = selectedContent()
        self.emptyContent = emptyContent()
        self.statusContent = statusContent()
        self.composerContent = composer()
    }

    public var body: some View {
        QuillDesktopSplitLayout(title: title, sidebarWidth: sidebarWidth) {
            sidebar
        } toolbar: {
            toolbarContent
        } content: {
            VStack(alignment: .center, spacing: 0) {
                if hasSelection {
                    selectedContent
                } else {
                    emptyContent
                }

                if showsStatus {
                    statusContent
                }

                composerContent
                    .padding(.horizontal, composerHorizontalPadding)
                    .padding(.vertical, composerVerticalPadding)
                    .frame(maxWidth: composerMaxWidth)
            }
        }
    }
}

public extension QuillDesktopChatScaffold where ToolbarContent == QuillDesktopChatToolbar {
    init(
        title: String,
        sidebarWidth: CGFloat = 320,
        composerMaxWidth: CGFloat = .infinity,
        composerHorizontalPadding: CGFloat = 40,
        composerVerticalPadding: CGFloat = 16,
        hasSelection: Bool,
        showsStatus: Bool = false,
        modelActions: [QuillMenuAction],
        optionsActions: [QuillMenuAction],
        onNewConversation: @escaping () -> Void,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder selectedContent: () -> SelectedContent,
        @ViewBuilder emptyContent: () -> EmptyContent,
        @ViewBuilder statusContent: () -> StatusContent,
        @ViewBuilder composer: () -> ComposerContent
    ) {
        self.init(
            title: title,
            sidebarWidth: sidebarWidth,
            composerMaxWidth: composerMaxWidth,
            composerHorizontalPadding: composerHorizontalPadding,
            composerVerticalPadding: composerVerticalPadding,
            hasSelection: hasSelection,
            showsStatus: showsStatus,
            sidebar: sidebar
        ) {
            QuillDesktopChatToolbar(
                modelActions: modelActions,
                optionsActions: optionsActions,
                onNewConversation: onNewConversation
            )
        } selectedContent: {
            selectedContent()
        } emptyContent: {
            emptyContent()
        } statusContent: {
            statusContent()
        } composer: {
            composer()
        }
    }
}

public struct QuillDesktopChatToolbar: View {
    public var modelActions: [QuillMenuAction]
    public var optionsActions: [QuillMenuAction]
    private var onNewConversation: () -> Void

    public init(
        modelActions: [QuillMenuAction],
        optionsActions: [QuillMenuAction],
        onNewConversation: @escaping () -> Void
    ) {
        self.modelActions = modelActions
        self.optionsActions = optionsActions
        self.onNewConversation = onNewConversation
    }

    public var body: some View {
        QuillToolbarActionRow {
            QuillToolbarMenuButton(
                systemImage: "chevron.down",
                menuWidth: 220,
                actions: modelActions
            )

            QuillToolbarMenuButton(
                systemImage: "ellipsis",
                showsChevron: true,
                width: 42,
                menuWidth: 180,
                actions: optionsActions
            )

            QuillToolbarIconButton(systemImage: "square.and.pencil", action: onNewConversation)
        }
    }
}

public struct QuillToolbarActionRow<Content: View>: View {
    public var spacing: Int
    private var content: Content

    public init(spacing: Int = 14, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: stackSpacing) {
            content
        }
        .frame(height: 32, alignment: .center)
    }

    #if os(macOS) || os(iOS) || os(visionOS)
    private var stackSpacing: CGFloat { CGFloat(spacing) }
    #else
    private var stackSpacing: Int { spacing }
    #endif
}

public struct QuillToolbarIconButton: View {
    public var systemImage: String
    public var showsChevron: Bool
    public var width: CGFloat
    private var action: () -> Void

    public init(
        systemImage: String,
        showsChevron: Bool = false,
        width: CGFloat = 30,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.showsChevron = showsChevron
        self.width = width
        self.action = action
    }

    public var body: some View {
        #if os(Linux)
        QuillGTKToolbarIconButton(
            systemImage: systemImage,
            showsChevron: showsChevron,
            width: width,
            action: action
        )
        #else
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: QuillSystemSymbol.compatibleName(systemImage))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)

                if showsChevron {
                    Image(systemName: QuillSystemSymbol.compatibleName("chevron.down"))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: chevronSize, height: chevronSize)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(toolbarIconColor)
        .frame(width: width, height: buttonHeight, alignment: .center)
        .contentShape(Rectangle())
        #endif
    }

    #if os(Linux)
    private var iconSize: CGFloat { 24 }
    private var chevronSize: CGFloat { 13 }
    private var buttonHeight: CGFloat { 34 }
    private var toolbarIconColor: Color { Color(hex: "#1F1F21") }
    #else
    private var iconSize: CGFloat { 17 }
    private var chevronSize: CGFloat { 10 }
    private var buttonHeight: CGFloat { 30 }
    private var toolbarIconColor: Color { Color(hex: "#3A3A3C") }
    #endif
}

public struct QuillToolbarMenuButton: View {
    public var systemImage: String
    public var showsChevron: Bool
    public var width: CGFloat
    public var menuWidth: CGFloat
    public var actions: [QuillMenuAction]
    @State private var isExpanded = false

    public init(
        systemImage: String,
        showsChevron: Bool = false,
        width: CGFloat = 30,
        menuWidth: CGFloat = 190,
        actions: [QuillMenuAction]
    ) {
        self.systemImage = systemImage
        self.showsChevron = showsChevron
        self.width = width
        self.menuWidth = menuWidth
        self.actions = actions
    }

    public var body: some View {
        #if os(Linux)
        QuillGTKToolbarMenuButton(
            systemImage: systemImage,
            showsChevron: showsChevron,
            width: width,
            actions: actions
        )
        #else
        ZStack(alignment: .topTrailing) {
            QuillToolbarIconButton(systemImage: systemImage, showsChevron: showsChevron, width: width) {
                isExpanded.toggle()
            }

            if isExpanded {
                menuPopover
                    .offset(y: 32)
            }
        }
        .frame(width: width, height: 30, alignment: .topTrailing)
        #endif
    }

    private var menuPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(actions) { action in
                switch action.kind {
                case .divider:
                    Divider()
                        .padding(.vertical, 4)
                case .item:
                    menuRow(for: action)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: menuWidth, alignment: .leading)
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(8)
        .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.16), radius: 14, x: 0, y: 8)
    }

    private func menuRow(for action: QuillMenuAction) -> some View {
        Button(action: {
            guard !action.isDisabled else { return }
            isExpanded = false
            action.perform()
        }) {
            HStack(spacing: 9) {
                menuIcon(for: action)

                Text(action.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(action.isDisabled ? Color(hex: "#9A9A9E") : Color(hex: "#2C2C2E"))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func menuIcon(for action: QuillMenuAction) -> some View {
        if let systemImage = action.systemImage {
            Image(systemName: QuillSystemSymbol.compatibleName(systemImage))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        } else {
            Text("")
                .frame(width: 15, height: 15)
        }
    }

}

public struct QuillMenuAction: Identifiable {
    public enum Kind {
        case item
        case divider
    }

    public var id: String
    public var title: String
    public var systemImage: String?
    public var isDisabled: Bool
    public var kind: Kind
    private var action: () -> Void

    public init(
        id: String? = nil,
        title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.kind = .item
        self.action = action
    }

    public static func divider(id: String = UUID().uuidString) -> QuillMenuAction {
        var action = QuillMenuAction(id: id, title: "", action: {})
        action.kind = .divider
        return action
    }

    public static func disabled(id: String? = nil, title: String) -> QuillMenuAction {
        QuillMenuAction(id: id, title: title, isDisabled: true) {}
    }

    public static func copyText(
        _ text: String,
        title: String = "Copy",
        systemImage: String = "doc.on.doc",
        clipboard: QuillClipboard = .shared
    ) -> QuillMenuAction {
        QuillMenuAction(title: title, systemImage: systemImage) {
            clipboard.setString(text)
        }
    }

    public static func edit(
        title: String = "Edit",
        systemImage: String = "pencil",
        action: @escaping () -> Void
    ) -> QuillMenuAction {
        QuillMenuAction(title: title, systemImage: systemImage, action: action)
    }

    public static func unselect(
        title: String = "Unselect",
        systemImage: String = "pencil",
        action: @escaping () -> Void
    ) -> QuillMenuAction {
        QuillMenuAction(title: title, systemImage: systemImage, action: action)
    }

    public static func chatMessageActions(
        content: String,
        isUserMessage: Bool,
        isEditing: Bool,
        selectText: (() -> Void)? = nil,
        readAloud: (() -> Void)? = nil,
        additionalActions: [QuillMenuAction] = [],
        onEdit: @escaping () -> Void,
        onUnselect: @escaping () -> Void,
        clipboard: QuillClipboard = .shared
    ) -> [QuillMenuAction] {
        var actions = [QuillMenuAction.copyText(content, clipboard: clipboard)]
        if let selectText {
            actions.append(QuillMenuAction(title: "Select Text", systemImage: "selection.pin.in.out", action: selectText))
        }
        if let readAloud {
            actions.append(QuillMenuAction(title: "Read Aloud", systemImage: "speaker.wave.3.fill", action: readAloud))
        }
        actions.append(contentsOf: additionalActions)
        if isUserMessage {
            actions.append(.edit(action: onEdit))
        }
        if isEditing {
            actions.append(.unselect(action: onUnselect))
        }
        return actions
    }

    public static func copyChatActions(copy: @escaping (_ json: Bool) -> Void) -> [QuillMenuAction] {
        [
            QuillMenuAction(title: "Copy Chat", systemImage: "doc.on.doc") {
                copy(false)
            },
            QuillMenuAction(title: "Copy Chat as JSON", systemImage: "curlybraces") {
                copy(true)
            }
        ]
    }

    public static func selectableModels<Item, SelectionID: Hashable>(
        _ models: [Item],
        selectedID: SelectionID?,
        emptyTitle: String = "No models available",
        selectedSystemImage: String = "checkmark",
        id: @escaping (Item) -> SelectionID,
        name: @escaping (Item) -> String,
        version: @escaping (Item) -> String = { _ in "" },
        onSelect: @escaping (Item) -> Void
    ) -> [QuillMenuAction] {
        selectableItems(
            models,
            selectedID: selectedID,
            emptyTitle: emptyTitle,
            selectedSystemImage: selectedSystemImage,
            id: id,
            title: { model in
                let version = version(model)
                return version.isEmpty ? name(model) : "\(name(model)) \(version)"
            },
            onSelect: onSelect
        )
    }

    public static func selectableItems<Item, SelectionID: Hashable>(
        _ items: [Item],
        selectedID: SelectionID?,
        emptyTitle: String? = nil,
        selectedSystemImage: String = "checkmark",
        id: @escaping (Item) -> SelectionID,
        title: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void
    ) -> [QuillMenuAction] {
        guard !items.isEmpty else {
            return emptyTitle.map { [QuillMenuAction.disabled(title: $0)] } ?? []
        }

        return items.map { item in
            let itemID = id(item)
            return QuillMenuAction(
                id: String(describing: itemID),
                title: title(item),
                systemImage: selectedID == itemID ? selectedSystemImage : nil
            ) {
                onSelect(item)
            }
        }
    }

    public func perform() {
        guard !isDisabled else { return }
        action()
    }
}

public struct QuillMenuButton: View {
    public var title: String
    public var systemImage: String
    public var actions: [QuillMenuAction]

    public init(
        title: String = "More",
        systemImage: String = "ellipsis.circle",
        actions: [QuillMenuAction]
    ) {
        self.title = title
        self.systemImage = systemImage
        self.actions = actions
    }

    public var body: some View {
        #if os(macOS) || os(iOS) || os(visionOS)
        Menu {
            ForEach(actions) { action in
                switch action.kind {
                case .divider:
                    Divider()
                case .item:
                    Button(action.title) {
                        action.perform()
                    }
                    .disabled(action.isDisabled)
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        #else
        Menu(title) {
            for action in actions {
                switch action.kind {
                case .divider:
                    MenuDivider()
                case .item:
                    MenuItem(action.title) {
                        action.perform()
                    }
                }
            }
        }
        #endif
    }
}

#if os(Linux)
public extension MenuBuilder {
    static func buildArray(_ components: [[MenuElement]]) -> [MenuElement] {
        components.flatMap { $0 }
    }
}
#endif
// (Removed dangling outer #endif — the buggy Linux-only wrapper at
// the top of this file was deleted along with this closer.)
