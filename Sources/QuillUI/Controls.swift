// Buggy outer `#if !os(macOS) && !os(iOS) && !os(visionOS)` removed —
// it was making every public type below (QuillFloatingIconButton,
// QuillSystemSymbol, etc.) invisible on macOS even though the inner
// branches looked correct.
import Foundation
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
        case "paperplane.fill":
            return "arrow.forward.circle.fill"
        case "photo", "photo.fill":
            return "folder.badge.plus"
        case "lightbulb", "lightbulb.circle", "lightbulb.circle.fill":
            return "info.circle"
        case "character.cursor.ibeam", "textformat", "textformat.abc":
            return "doc.text"
        case "keyboard", "keyboard.fill":
            return "doc.on.doc"
        case "waveform":
            return "ellipsis.circle"
        case "x.circle.fill":
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
        columns: Int = 4,
        cardWidth: CGFloat = 155,
        cardHeight: CGFloat = 128,
        spacing: Int = 15,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.prompts = prompts
        self.columns = max(1, columns)
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.spacing = spacing
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: stackSpacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(alignment: .top, spacing: stackSpacing) {
                    ForEach(indices(for: row), id: \.self) { index in
                        promptButton(prompts[index])
                    }
                }
            }
        }
    }

    #if os(macOS) || os(iOS) || os(visionOS)
    private var stackSpacing: CGFloat { CGFloat(spacing) }
    #else
    private var stackSpacing: Int { spacing }
    #endif

    private var rowCount: Int {
        guard !prompts.isEmpty else { return 0 }
        return Int(ceil(Double(prompts.count) / Double(columns)))
    }

    private func indices(for row: Int) -> [Int] {
        let start = row * columns
        let end = min(start + columns, prompts.count)
        guard start < end else { return [] }
        return Array(start..<end)
    }

    @ViewBuilder
    private func promptButton(_ prompt: QuillPrompt) -> some View {
        Button(action: { action(prompt) }) {
            promptCard(prompt)
        }
        .buttonStyle(.plain)
    }

    private func promptCard(_ prompt: QuillPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt.title.quillPromptGridDisplayTitle)
                .font(.system(size: promptFontSize))
                .foregroundColor(Color(hex: "#1D1D1F"))
                .frame(width: max(40, cardWidth - (promptCardPaddingWidth * 2)), alignment: .leading)
            Spacer()
            HStack {
                Spacer()
                promptAccessory(for: prompt)
            }
        }
        .padding(promptCardPadding)
        .frame(width: cardWidth, height: cardHeight, alignment: .leading)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    #if os(Linux)
    private var promptFontSize: CGFloat { 24 }
    private var promptCardPadding: Int { 28 }
    private var promptCardPaddingWidth: CGFloat { CGFloat(promptCardPadding) }
    private var promptIconSize: CGFloat { 20 }
    #else
    private var promptFontSize: CGFloat { 15 }
    private var promptCardPadding: CGFloat { 15 }
    private var promptCardPaddingWidth: CGFloat { promptCardPadding }
    private var promptIconSize: CGFloat { 16 }
    #endif

    private var cardBackgroundColor: Color {
        #if os(Linux)
        return Color(hex: "#E8E8EE")
        #else
        return Color(hex: "#F4F4F6")
        #endif
    }

    @ViewBuilder
    private func promptAccessory(for prompt: QuillPrompt) -> some View {
        #if os(Linux)
        ZStack {
            Circle()
                .stroke(Color(hex: "#2E2E31"), lineWidth: 2)
                .frame(width: promptIconSize, height: promptIconSize)
            Text(prompt.systemImage.contains("lightbulb") ? "!" : "?")
                .font(.system(size: 12))
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: "#2E2E31"))
        }
        #else
        Image(systemName: QuillSystemSymbol.compatibleName(prompt.systemImage))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: promptIconSize, height: promptIconSize)
            .foregroundColor(Color(hex: "#2E2E31"))
        #endif
    }
}

public struct QuillConversationHistoryItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var updatedAt: Date

    public init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

private struct QuillConversationHistorySection: Identifiable {
    var id: String { title }
    var title: String
    var items: [QuillConversationHistoryItem]
}

public struct QuillConversationHistoryList: View {
    public var items: [QuillConversationHistoryItem]
    public var selectedID: String?
    public var onSelect: (QuillConversationHistoryItem) -> Void

    public init(
        items: [QuillConversationHistoryItem],
        selectedID: String? = nil,
        onSelect: @escaping (QuillConversationHistoryItem) -> Void
    ) {
        self.items = items
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        Text(section.title)
                            .font(.system(size: sectionFontSize))
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "#8E8E93"))
                            .padding(.top, sectionTopPadding)

                        ForEach(section.items) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .frame(width: 6, height: 6)
                                    .opacity(selectedID == item.id ? 1 : 0)

                                Text(item.title)
                                    .font(.system(size: rowFontSize))
                                    .lineLimit(1)
                                    .foregroundColor(Color(hex: "#3A3A3C"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: rowHeight, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item) }
                        }

                        Divider()
                            .padding(.top, dividerTopPadding)
                    }
                }

                if items.isEmpty {
                    Text("No conversations yet")
                        .font(.caption)
                        .foregroundColor(Color(hex: "#8E8E93"))
                        .padding(.top, 12)
                }
            }
        }
    }

    #if os(Linux)
    private var sectionFontSize: CGFloat { 18 }
    private var rowFontSize: CGFloat { 20 }
    private var rowHeight: CGFloat { 30 }
    private var sectionSpacing: CGFloat { 6 }
    private var sectionTopPadding: CGFloat { 18 }
    private var dividerTopPadding: CGFloat { 16 }
    #else
    private var sectionFontSize: CGFloat { 14 }
    private var rowFontSize: CGFloat { 16 }
    private var rowHeight: CGFloat { 24 }
    private var sectionSpacing: CGFloat { 13 }
    private var sectionTopPadding: CGFloat { 12 }
    private var dividerTopPadding: CGFloat { 10 }
    #endif

    private var sections: [QuillConversationHistorySection] {
        var result: [QuillConversationHistorySection] = []
        let sortedItems = items.sorted { $0.updatedAt > $1.updatedAt }

        for item in sortedItems {
            let title = Self.sectionTitle(for: item.updatedAt)
            if let index = result.firstIndex(where: { $0.title == title }) {
                result[index].items.append(item)
            } else {
                result.append(QuillConversationHistorySection(title: title, items: [item]))
            }
        }

        return result
    }

    private static func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: target, to: today).day ?? 0

        switch days {
        case 0:
            return "Today"
        case 1:
            return "Yesterday"
        default:
            return "\(days) days ago"
        }
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
        switch systemImage {
        case "character.cursor.ibeam", "textformat", "textformat.abc":
            Text("Abc")
                .font(.system(size: 11))
        #if os(Linux)
        case "keyboard", "keyboard.fill":
            Text("⌨")
                .font(.system(size: 18))
        case "gearshape", "gearshape.fill", "gear":
            Text("⚙")
                .font(.system(size: 22))
        #endif
        default:
            Image(systemName: QuillSystemSymbol.compatibleName(systemImage))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17, alignment: .center)
        }
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

public struct QuillMacWindowControls: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: "#FF605C"))
            Circle().fill(Color(hex: "#FFBD44"))
            Circle().fill(Color(hex: "#00CA4E"))
        }
        .frame(width: 82, height: 14, alignment: .leading)
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
        columns: Int = 4,
        cardWidth: CGFloat = 155,
        cardHeight: CGFloat = 128,
        spacing: Int = 15,
        action: @escaping (QuillPrompt) -> Void
    ) {
        self.brandTitle = brandTitle
        self.prompts = prompts
        self.columns = max(1, columns)
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.spacing = spacing
        self.action = action
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
                .frame(width: metrics.gridWidth, alignment: .center)

                Spacer()
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
                .frame(width: metrics.gridWidth, alignment: .center)

                Spacer()
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
        if totalWidth >= 1200 {
            let visible = CGFloat(min(columns, max(1, prompts.count)))
            resolvedSpacing = 28
            let availableGridWidth = CGFloat(totalWidth) * 0.86
            let spacingWidth = CGFloat(max(0, Int(visible) - 1) * resolvedSpacing)
            let candidateWidth = (availableGridWidth - spacingWidth) / visible
            resolvedCardWidth = min(305, max(cardWidth, candidateWidth))
            resolvedCardHeight = max(cardHeight, 280)
        }
        #endif

        return QuillPromptGridMetrics(
            cardWidth: resolvedCardWidth,
            cardHeight: resolvedCardHeight,
            spacing: resolvedSpacing,
            gridWidth: gridWidth(cardWidth: resolvedCardWidth, spacing: resolvedSpacing)
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
        Text(brandTitle)
            .foregroundColor(Color(hex: "#9B72CB"))
            .font(Font.system(size: 66, weight: .thin))
            .multilineTextAlignment(.center)
        #endif
    }
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
                    .background(Color(hex: "#E9E9E7"))
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
                            .font(.system(size: 16))
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "#444446"))
                        Spacer()
                        HStack(spacing: 14) {
                            toolbarContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: resolvedToolbarHeight, alignment: .center)
                    .background(Color(hex: "#FAFAFA"))

                    Divider()

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: "#FAFAFA"))
                }
            }
            .background(Color(hex: "#FAFAFA"))
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
