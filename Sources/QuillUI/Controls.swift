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

    public func makeBody(configuration: Configuration) -> some View {
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

    private func promptButton(_ prompt: QuillPrompt) -> some View {
        Button(action: { action(prompt) }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(prompt.title.quillPromptGridDisplayTitle)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "#1D1D1F"))
                    .frame(width: max(40, cardWidth - 30), alignment: .leading)
                Spacer()
            }
            .padding(15)
            .frame(width: cardWidth, height: cardHeight, alignment: .leading)
            .background(Color(hex: "#F4F4F6"))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
                    VStack(alignment: .leading, spacing: 13) {
                        Text(section.title)
                            .font(.system(size: 14))
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "#8E8E93"))
                            .padding(.top, 12)

                        ForEach(section.items) { item in
                            Button(action: { onSelect(item) }) {
                                Text(item.title)
                                    .font(.system(size: 16))
                                    .lineLimit(1)
                                    .foregroundColor(Color(hex: "#3A3A3C"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()
                            .padding(.top, 10)
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
        HStack(spacing: 10) {
            sidebarIcon
                .frame(width: 24, height: 20, alignment: .leading)

            Text(title)
                .lineLimit(1)
                .font(.system(size: 15))

            Spacer()
        }
        .foregroundColor(Color(hex: "#3A3A3C"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    @ViewBuilder
    private var sidebarIcon: some View {
        switch systemImage {
        case "character.cursor.ibeam", "textformat", "textformat.abc":
            Text("Abc")
                .font(.system(size: 11))
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
    private var action: (() -> Void)?

    public init(
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 14) {
            Text(message)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: "#2E2E2E"))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle {
                Button(actionTitle) {
                    action?()
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color.black)
                .cornerRadius(14)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(hex: "#F5C8D2"))
        .cornerRadius(9)
    }
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
        VStack(spacing: 40) {
            Spacer()
            wordmark

            QuillPromptGrid(
                prompts: prompts,
                columns: columns,
                cardWidth: cardWidth,
                cardHeight: cardHeight,
                spacing: spacing,
                action: action
            )
            .frame(width: gridWidth, alignment: .center)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridWidth: CGFloat {
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
            .font(Font.system(size: 46, weight: .thin))
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
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth, alignment: .leading)
                .background(Color(hex: "#E9E9E7"))

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
                .frame(height: toolbarHeight, alignment: .center)
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
        HStack(spacing: 4) {
            Image(systemName: QuillSystemSymbol.compatibleName(systemImage))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)

            if showsChevron {
                Image(systemName: QuillSystemSymbol.compatibleName("chevron.down"))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10, height: 10)
            }
        }
        .foregroundColor(Color(hex: "#3A3A3C"))
        .frame(width: width, height: 30, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
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
        HStack(spacing: 9) {
            menuIcon(for: action)

            Text(action.title)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()
        }
        .foregroundColor(action.isDisabled ? Color(hex: "#9A9A9E") : Color(hex: "#2C2C2E"))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !action.isDisabled else { return }
            isExpanded = false
            action.perform()
        }
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
