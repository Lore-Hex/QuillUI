import Foundation
import Testing
import QuillUI

#if os(Linux)
@Suite("Upstream SwiftUI compatibility shims", .serialized)
struct UpstreamCompatibilityTests {
    @Test("compiles file import drop and visual effect modifiers")
    func compilesPortingSurface() {
        let isPresented = Binding(get: { false }, set: { _ in })
        let isTargeted = Binding(get: { false }, set: { _ in })

        _ = Text("Enchanted")
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: "4285f4"), Color(hex: "9b72cb")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .allowsHitTesting(true)
            .contentShape(Rectangle())
            .fileImporter(
                isPresented: isPresented,
                allowedContentTypes: [.png, .jpeg, .tiff],
                onCompletion: { _ in }
            )
            .onDrop(of: [.image], isTargeted: isTargeted) { _ in true }
            .symbolEffect(.variableColor.iterative, options: .repeat(2), value: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Composer")
            .accessibilityValue("Ready")

        _ = Text("System colors")
            .foregroundStyle(.label, .gray5Custom)
            .buttonStyle(QuillGrowingButtonStyle())
            .preferredColorScheme(.dark)
            .listStyle(PlainListStyle())
            .matchedGeometryEffect(id: "card", in: Namespace().wrappedValue)
        _ = Color(.label)
        _ = Color(.systemGray)
        _ = Color(.systemRed)
        _ = Color("label")
        _ = Color.grayCustom
        _ = Color.gray5Custom
        _ = ImageRenderer(content: Text("Render")).scale
        _ = PlatformImage()
        struct LinuxKeyboardReadable: KeyboardReadable {}
        _ = LinuxKeyboardReadable()

        _ = RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial)
        _ = RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
        _ = RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [10]))
        _ = Image(systemName: "photo.fill").renderingMode(.template)
        #expect(QuillSystemSymbol.compatibleName("paperplane.fill") == "arrow.forward.circle.fill")
        #expect(QuillSystemSymbol.compatibleName("photo.fill") == "folder.badge.plus")
        #expect(QuillSystemSymbol.compatibleName("keyboard") == "doc.on.doc")
        #expect(QuillSystemSymbol.compatibleName("keyboard.fill") == "doc.on.doc")
        #expect(QuillSystemSymbol.compatibleName("waveform") == "ellipsis.circle")
        #expect(QuillSystemSymbol.compatibleName("x.circle") == "xmark.circle.fill")
        #expect(QuillSystemSymbol.compatibleName("x.circle.fill") == "xmark.circle.fill")
        _ = QuillFloatingIconButton(systemImage: "paperplane.fill") {}
        _ = QuillPromptList(prompts: [
            QuillPrompt(title: "Open a feed", systemImage: "link"),
            QuillPrompt(title: "Mark everything read", systemImage: "checkmark.circle.fill")
        ]) { _ in }
        _ = QuillPromptGrid(prompts: [
            QuillPrompt(title: "Summarize a thread", systemImage: "info.circle"),
            QuillPrompt(title: "Attach an image", systemImage: "photo.fill"),
            QuillPrompt(title: "Send a message", systemImage: "paperplane.fill")
        ]) { _ in }
        _ = QuillConversationHistoryList(items: [
            QuillConversationHistoryItem(id: "1", title: "How to center div in HTML?", updatedAt: Date())
        ]) { _ in }
        _ = QuillSidebarBottomNavigation(actions: [
            QuillSidebarNavigationAction(title: "Completions", systemImage: "character.cursor.ibeam") {},
            QuillSidebarNavigationAction(title: "Shortcuts", systemImage: "keyboard") {},
            QuillSidebarNavigationAction(title: "Settings", systemImage: "gearshape.fill") {}
        ])
        _ = QuillSidebarNavigationButton(title: "Completions", systemImage: "textformat.abc") {}
        _ = QuillStatusBanner(message: "Quill is unreachable.", actionTitle: "Settings") {}
        _ = QuillChatEmptyState(prompts: [
            QuillPrompt(title: "How to center div in HTML?", systemImage: "questionmark.circle")
        ]) { _ in }
        _ = QuillChatEmptyState(
            brandTitle: "Quill",
            prompts: [
                QuillPrompt(title: "How to center div in HTML?", systemImage: "questionmark.circle"),
                QuillPrompt(title: "Explain supercomputers like I'm five years old", systemImage: "lightbulb.circle")
            ],
            columns: 4,
            cardWidth: 155,
            cardHeight: 128,
            spacing: 15
        ) { _ in }
        _ = QuillMenuButton(actions: [
            QuillMenuAction(title: "Refresh", systemImage: "arrow.clockwise") {},
            .divider(),
            QuillMenuAction(title: "Clear", systemImage: "trash", isDisabled: true) {}
        ])
        _ = QuillToolbarMenuButton(systemImage: "ellipsis", showsChevron: true, actions: [
            QuillMenuAction(title: "Copy Chat", systemImage: "doc.on.doc") {},
            .divider(),
            QuillMenuAction(title: "Copy JSON", systemImage: "curlybraces") {}
        ])
        _ = Menu {
            ForEach(["Copy", "Paste"], id: \.self) { title in
                Button(title) {}
            }
            Divider()
        } label: {
            Image(systemName: "ellipsis")
        }
        var selected = "a"
        let selection = Binding(get: { selected }, set: { selected = $0 })
        _ = Picker(selection: selection) {
            Text("A").tag("a")
            Text("B").tag("b")
        } label: {
            Label {
                Text("Letters")
            } icon: {
                Image(systemName: "textformat")
            }
        }
        .pickerStyle(.menu)
        let text = Binding(get: { "http://localhost:11434" }, set: { _ in })
        _ = Form {
            Section(header: Text("Quill")) {
                TextField("Endpoint", text: text)
                    .textContentType(.URL)
                    .disableAutocorrection(true)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            }
        }
        .formStyle(.grouped)
        _ = Text("Changed")
            .onChange(of: selected, initial: false) { _, _ in }
        _ = Text("Toolbar")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text("Quill Chat")
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button("New") {}
                }
            }
        struct QuillCommands: Commands {
            var body: some Commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings") {}
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates") {}
                        .disabled(true)
                }
            }
        }
        _ = QuillCommands()
        _ = URL(fileURLWithPath: "/tmp/image.png").startAccessingSecurityScopedResource()
    }

    @Test("compiles Enchanted chat component compatibility surface")
    func compilesEnchantedChatComponentSurface() {
        let focusState = FocusState<Bool>(wrappedValue: false)
        let focused = focusState.projectedValue
        focused.wrappedValue = true
        #expect(focusState.wrappedValue)

        let contextMenu = ContextMenu {
            Button("Copy") {}
            Divider()
        }

        _ = Text("Message")
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .minimumScaleFactor(0.5)
            .padding(CGFloat(10))
            .padding(.vertical, 10.0)
            .padding(.horizontal, 10.0)
            .padding(.bottom, CGFloat(10))
            .padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            .textSelection(.enabled)
            .focused(focused)
            .onHover { _ in }
            .transition(.asymmetric(
                insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)),
                removal: .slide
            ))
            .offset(CGSize(width: 4, height: -2))
            .contextMenu(contextMenu)

        _ = LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 80, maximum: 180), spacing: 12, alignment: .center)
            ],
            alignment: .leading,
            spacing: 16.0
        ) {
            Text("Prompt")
        }

        _ = HStack(alignment: .firstTextBaseline, spacing: 10.0) {
            Text("Quill")
            Text("Chat")
        }

        _ = VStack(spacing: 6.0) {
            Text("One")
            Text("Two")
        }

        _ = AngularGradient(
            colors: [.systemBlue, .systemRed],
            center: .center,
            startAngle: .zero,
            endAngle: .degrees(360)
        ).opacity(0.5)

        _ = Animation.snappy(duration: 0.2)
            .repeatForever(autoreverses: false)
            .delay(0.1)
    }

    @Test("compiles full-source Enchanted compatibility surface")
    func compilesFullSourceEnchantedCompatibilitySurface() {
        struct TableRow: Hashable {
            var title: String
            var count: Int
        }

        var focusedField: String?
        var moved: (IndexSet, Int)?
        let dragChanged = LockedTestValue(false)
        let dragEnded = LockedTestValue(false)
        var showingDialog = true

        _ = State(initialValue: "draft")
        _ = WindowGroup {
            Text("Quill")
        }

        _ = LabeledContent("Endpoint") {
            Text("http://localhost:11434")
        }.body

        let titleColumn = TableColumn<TableRow, Text>("Title") { row in
            Text(row.title)
        }
        _ = titleColumn.body
        _ = AnyTableColumn(titleColumn).body

        let table = Table([
            TableRow(title: "Chat", count: 3),
            TableRow(title: "Completions", count: 4)
        ]) {
            titleColumn.width(min: 80, max: 220)

            TableColumn("Count") { row in
                Text("\(row.count)")
            }
        }
        _ = table.body

        _ = Text("Full source")
            .antialiased(true)
            .focused(Binding(get: { focusedField }, set: { focusedField = $0 }), equals: "message")
            .lineLimit(2, reservesSpace: true)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .focusEffectDisabled()
            .edgesIgnoringSafeArea(.all)
            .ignoresSafeArea(.all)
            .onMove { source, destination in
                moved = (source, destination)
            }
            .gesture(
                DragGesture()
                    .onChanged { _ in dragChanged.set(true) }
                    .onEnded { _ in dragEnded.set(true) }
            )
            .symbolRenderingMode(.hierarchical)
            .confirmationDialog(
                "Delete",
                isPresented: Binding(get: { showingDialog }, set: { showingDialog = $0 })
            ) {
                Button("Delete") {}
            } message: {
                Text("Delete this completion?")
            }

        var completions = ["a", "b", "c", "d"]
        completions.move(fromOffsets: IndexSet([1, 2]), toOffset: 4)
        #expect(completions == ["a", "d", "b", "c"])
        #expect(moved == nil)
        #expect(dragChanged.value == false)
        #expect(dragEnded.value == false)

        #expect(Image(systemName: "gear") == Image(systemName: "gear"))
        #expect(Image(systemName: "gear").imageScale(.large) != Image(systemName: "gear"))
        #expect(Image(filePath: "/tmp/quill.png") == Image(filePath: "/tmp/quill.png"))
        #expect(Image(material: "search") == Image(material: "search"))
        #expect(Image(systemName: "gear") != Image(filePath: "gear"))

        let dragValue = DragGesture.Value(translation: CGSize(width: 3, height: -2))
        #expect(dragValue.translation == CGSize(width: 3, height: -2))

        let dismissed = LockedTestValue(false)
        PresentationMode {
            dismissed.set(true)
        }.dismiss()
        #expect(dismissed.value)
    }

    @Test("loads dropped file data through NSItemProvider compatibility")
    func loadsDroppedFileData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUI-UpstreamCompatibilityTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        try imageData.write(to: imageURL)

        let provider = NSItemProvider(fileURL: imageURL)
        var loadedData: Data?
        var loadedError: Error?
        _ = provider.loadDataRepresentation(for: .image) { data, error in
            loadedData = data
            loadedError = error
        }

        #expect(loadedData == imageData)
        #expect(loadedError == nil)
    }

    @Test("NSItemProvider reports unsupported and missing representations")
    func itemProviderReportsRepresentationFailures() throws {
        let dataProvider = NSItemProvider(data: Data([1, 2, 3]), type: .png)
        var loadedData: Data?
        var loadedError: Error?
        _ = dataProvider.loadDataRepresentation(for: .image) { data, error in
            loadedData = data
            loadedError = error
        }
        #expect(loadedData == Data([1, 2, 3]))
        #expect(loadedError == nil)

        var unsupportedError: Error?
        _ = dataProvider.loadDataRepresentation(for: .tiff) { data, error in
            #expect(data == nil)
            unsupportedError = error
        }
        #expect(unsupportedError?.localizedDescription.contains("public.tiff") == true)

        let emptyProvider = NSItemProvider()
        var emptyProviderError: Error?
        _ = emptyProvider.loadDataRepresentation(for: .image) { data, error in
            #expect(data == nil)
            emptyProviderError = error
        }
        #expect(emptyProviderError?.localizedDescription.contains("public.image") == true)
    }

    @Test("UTType compatibility handles image conformance and extension aliases")
    func utTypeConformanceAndAliases() throws {
        #expect(UTType.png.conforms(to: .image))
        #expect(UTType.jpeg.conforms(to: .image))
        #expect(UTType.tiff.conforms(to: .image))
        #expect(UTType.image.conforms(to: .png) == false)

        let directory = try temporaryDirectory()
        let jpgURL = directory.appendingPathComponent("photo").appendingPathExtension("JPG")
        let tifURL = directory.appendingPathComponent("scan").appendingPathExtension("tif")
        try Data([1]).write(to: jpgURL)
        try Data([2]).write(to: tifURL)

        QuillFileImporter.setTestSelection(jpgURL)
        defer { QuillFileImporter.setTestSelection(nil) }

        if case .success(let selectedURL) = QuillFileImporter.selectURL(allowedContentTypes: [.jpeg]) {
            #expect(selectedURL == jpgURL)
        } else {
            Issue.record("Expected uppercase JPG to match public.jpeg")
        }

        QuillFileImporter.setTestSelection(tifURL)
        if case .success(let selectedURL) = QuillFileImporter.selectURL(allowedContentTypes: [.image]) {
            #expect(selectedURL == tifURL)
        } else {
            Issue.record("Expected tif extension to match public.image")
        }
    }

    @Test("file importer validates test selections by content type")
    func fileImporterSelectionValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUI-UpstreamCompatibilityTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        let textURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        try Data([1, 2, 3]).write(to: imageURL)
        try Data([4, 5, 6]).write(to: textURL)

        QuillFileImporter.setTestSelection(imageURL)
        defer { QuillFileImporter.setTestSelection(nil) }

        if case .success(let selectedURL) = QuillFileImporter.selectURL(allowedContentTypes: [.png]) {
            #expect(selectedURL == imageURL)
        } else {
            Issue.record("Expected PNG selection to succeed")
        }

        QuillFileImporter.setTestSelection(textURL)
        if case .failure(let error) = QuillFileImporter.selectURL(allowedContentTypes: [.png]) {
            #expect(error.localizedDescription.contains("allowed file types"))
        } else {
            Issue.record("Expected TXT selection to fail against PNG-only importer")
        }
    }

    @Test("file importer accepts any selected file when no content types are specified")
    func fileImporterEmptyAllowedTypesAcceptsSelection() throws {
        let textURL = try temporaryDirectory()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("hello".utf8).write(to: textURL)

        QuillFileImporter.setTestSelection(textURL)
        defer { QuillFileImporter.setTestSelection(nil) }

        if case .success(let selectedURL) = QuillFileImporter.selectURL(allowedContentTypes: []) {
            #expect(selectedURL == textURL)
        } else {
            Issue.record("Expected empty allowedContentTypes to accept the test selection")
        }
    }

    @Test("disabled menu and command adapters suppress actions")
    func disabledMenuAndCommandAdaptersSuppressActions() {
        var menuActionCount = 0
        let menu = Menu {
            Button("Delete") {
                menuActionCount += 1
            }
            .disabled(true)
        } label: {
            Text("More")
        }

        if case .item(_, let action) = menu.elements.first {
            action()
        } else {
            Issue.record("Expected disabled button to build a menu item")
        }
        #expect(menuActionCount == 0)

        let enabled = QuillMenuAction(title: "Enabled") {
            menuActionCount += 1
        }
        let disabled = QuillMenuAction(title: "Disabled", isDisabled: true) {
            menuActionCount += 10
        }
        enabled.perform()
        disabled.perform()
        #expect(menuActionCount == 1)

        let commands = CommandGroup(replacing: .appSettings) {
            Button("Settings") {}
                .disabled(true)
        }
        #expect(commands.items.first?.isDisabled == true)
    }

    @Test("QuillUI controls build their bodies and run public actions")
    func quillControlsBuildBodiesAndActions() {
        var iconTapped = false
        let iconButton = QuillFloatingIconButton(systemImage: "paperplane.fill") {
            iconTapped = true
        }
        _ = iconButton.body

        let growingStyle = QuillGrowingButtonStyle()
        _ = growingStyle.makeBody(configuration: .init(label: Text("Send"), isPressed: true))
        _ = growingStyle.makeBody(configuration: .init(label: Text("Send"), isPressed: false))

        var selectedPrompt: QuillPrompt?
        let prompts = [
            QuillPrompt(title: "How to center div in HTML?", systemImage: "questionmark.circle"),
            QuillPrompt(title: "Explain supercomputers like I'm five years old", systemImage: "lightbulb.circle"),
            QuillPrompt(title: "Write a text message asking a friend to be my plus-one at a wedding", systemImage: "lightbulb.circle")
        ]
        _ = QuillPromptList(prompts: prompts, rowWidth: 320) { selectedPrompt = $0 }.body
        _ = QuillPromptGrid(prompts: prompts, columns: 2, cardWidth: 140, cardHeight: 110, spacing: 8) { selectedPrompt = $0 }.body
        _ = QuillChatEmptyState(brandTitle: "Quill", prompts: prompts, columns: 2) { selectedPrompt = $0 }.body

        let history = [
            QuillConversationHistoryItem(id: "today", title: "Today item", updatedAt: Date()),
            QuillConversationHistoryItem(
                id: "yesterday",
                title: "Yesterday item",
                updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            ),
            QuillConversationHistoryItem(
                id: "older",
                title: "Older item",
                updatedAt: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()
            )
        ]
        _ = QuillConversationHistoryList(items: history, selectedID: "today") { _ in }.body

        var navigationTapped = false
        let navigationAction = QuillSidebarNavigationAction(title: "Settings", systemImage: "gearshape.fill") {
            navigationTapped = true
        }
        navigationAction.perform()
        _ = QuillSidebarBottomNavigation(actions: [navigationAction]).body

        var bannerTapped = false
        _ = QuillStatusBanner(message: "Quill is unreachable.", actionTitle: "Settings") {
            bannerTapped = true
        }.body
        _ = QuillStatusBanner(message: "Quill is unreachable.", actionTitle: "Settings", showsActivity: true) {
            bannerTapped = true
        }.body
        _ = QuillStatusBanner(message: "Ready").body
        _ = QuillMacWindowControls().body

        var menuTapped = false
        let menuAction = QuillMenuAction(title: "Refresh", systemImage: "arrow.clockwise") {
            menuTapped = true
        }
        menuAction.perform()
        _ = QuillMenuButton(actions: [
            menuAction,
            .divider(id: "divider"),
            QuillMenuAction(title: "Disabled", isDisabled: true) {}
        ]).body
        _ = QuillToolbarMenuButton(systemImage: "ellipsis", showsChevron: true, actions: [
            menuAction,
            .divider(id: "toolbar-divider"),
            QuillMenuAction(title: "Copy JSON", systemImage: "curlybraces") {}
        ]).body

        #expect(iconTapped == false)
        #expect(selectedPrompt == nil)
        #expect(navigationTapped)
        #expect(bannerTapped == false)
        #expect(menuTapped)
    }

    @Test("QuillUI control view trees materialize nested Linux content")
    func quillControlViewTreesMaterializeNestedContent() {
        let prompts = [
            QuillPrompt(title: "", systemImage: "questionmark.circle"),
            QuillPrompt(
                title: "Explain an unusually long prompt title that should wrap across several display rows before truncating",
                systemImage: "lightbulb.circle"
            ),
            QuillPrompt(title: "Short", systemImage: "paperplane.fill")
        ]

        materializeStructuralViewTree(
            QuillPromptList(prompts: prompts, rowWidth: 96) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillPromptGrid(prompts: prompts, columns: 2, cardWidth: 92, cardHeight: 80, spacing: 6) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillPromptGrid(prompts: [], columns: 0) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillChatEmptyState(brandTitle: "Quill", prompts: prompts, columns: 2) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillChatEmptyState(
                brandTitle: "Quill",
                prompts: prompts,
                columns: 4,
                cardWidth: 155,
                cardHeight: 128,
                spacing: 15
            ) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillDesktopSplitLayout(title: "Quill Chat") {
                QuillConversationHistoryList(items: []) { _ in }
            } toolbar: {
                QuillToolbarActionRow {
                    QuillToolbarMenuButton(systemImage: "chevron.down", actions: [
                        QuillMenuAction(title: "Llama latest", systemImage: "checkmark") {}
                    ])
                    QuillToolbarMenuButton(systemImage: "ellipsis", showsChevron: true, width: 42, actions: [
                        QuillMenuAction(title: "Copy Chat") {},
                        QuillMenuAction(title: "Copy Chat as JSON") {}
                    ])
                    QuillToolbarIconButton(systemImage: "square.and.pencil") {}
                }
            } content: {
                QuillChatEmptyState(brandTitle: "Quill", prompts: prompts, columns: 4) { _ in }
            }.body
        )

        let now = Date()
        materializeStructuralViewTree(
            QuillConversationHistoryList(items: [
                QuillConversationHistoryItem(id: "today", title: "Today", updatedAt: now),
                QuillConversationHistoryItem(
                    id: "yesterday",
                    title: "Yesterday",
                    updatedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
                ),
                QuillConversationHistoryItem(
                    id: "older",
                    title: "Older",
                    updatedAt: Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now
                )
            ]) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillConversationHistoryList(items: []) { _ in }.body
        )
        materializeStructuralViewTree(
            QuillSidebarBottomNavigation(actions: [
                QuillSidebarNavigationAction(title: "Completions", systemImage: "textformat.abc") {},
                QuillSidebarNavigationAction(title: "Shortcuts", systemImage: "keyboard") {}
            ]).body
        )
        materializeStructuralViewTree(
            QuillStatusBanner(message: "Disconnected", actionTitle: "Retry") {}.body
        )
        materializeStructuralViewTree(
            QuillStatusBanner(message: "Disconnected", actionTitle: "Retry", showsActivity: true) {}.body
        )
        materializeStructuralViewTree(
            QuillStatusBanner(message: "Ready").body
        )
        materializeStructuralViewTree(
            QuillMacWindowControls().body
        )
        materializeStructuralViewTree(
            QuillMenuButton(actions: [
                QuillMenuAction(title: "Refresh", systemImage: "arrow.clockwise") {},
                .divider(id: "explicit-divider"),
                QuillMenuAction(title: "Disabled", isDisabled: true) {}
            ]).body
        )

        #expect(QuillSystemSymbol.compatibleName("lightbulb.circle.fill") == "info.circle")
        #expect(QuillSystemSymbol.compatibleName("textformat.abc") == "doc.text")
        #expect(QuillSystemSymbol.compatibleName("keyboard.fill") == "doc.on.doc")
        #expect(QuillSystemSymbol.compatibleName("x.circle") == "xmark.circle.fill")
        #expect(QuillSystemSymbol.compatibleName("x.circle.fill") == "xmark.circle.fill")
        #expect(QuillSystemSymbol.compatibleName("custom.symbol") == "custom.symbol")
    }

    @Test("menu command picker and drop adapters preserve Linux behavior")
    func menuCommandPickerAndDropAdaptersPreserveBehavior() throws {
        var menuHits: [String] = []
        let menu = Menu {
            Button("Copy") { menuHits.append("copy") }
                .keyboardShortcut("c", modifiers: .command)
            HStack {
                Button("One") { menuHits.append("one") }
                Button("Two") { menuHits.append("two") }
            }
            Button("Disabled false") { menuHits.append("enabled") }
                .disabled(false)
            Divider()
        } label: {
            HStack {
                Text("")
                Text("Actions")
            }
        }

        #expect(menu.title == "Actions")
        for element in menu.elements {
            if case .item(_, let action) = element {
                action()
            }
        }
        #expect(menuHits == ["copy", "one", "two", "enabled"])

        let imageLabelMenu = Menu {
            Button("Photo") {}
        } label: {
            Image(data: Data([0x89, 0x50, 0x4E, 0x47]))
        }
        #expect(imageLabelMenu.title == "photo")

        let fallbackIconLabel = Label {
            Text("Fallback")
        } icon: {
            Text("not-an-image")
        }
        #expect(fallbackIconLabel.systemImage == "circle")

        var commandHits: [String] = []
        struct AdapterCommands: Commands {
            var onRun: () -> Void
            var onNested: () -> Void

            var body: some Commands {
                CommandGroup(after: .appInfo) {
                    Button("Run", action: onRun)
                        .keyboardShortcut("r", modifiers: .command)
                    HStack {
                        Button("Nested", action: onNested)
                    }
                    Button("Blocked") {
                        commandHitsSink()
                    }
                    .disabled(true)
                }
                CommandGroup(replacing: .newItem) {
                    Button("New") {}
                }
            }

            private func commandHitsSink() {}
        }

        let groups = extractCommandGroups(from: AdapterCommands(
            onRun: { commandHits.append("run") },
            onNested: { commandHits.append("nested") }
        ))
        let infoItems = groups[.help] ?? []
        #expect(infoItems.count == 3)
        #expect(infoItems[0].shortcut != nil)
        #expect(infoItems[2].isDisabled)
        infoItems[0].action()
        infoItems[1].action()
        infoItems[2].action()
        #expect(commandHits == ["run", "nested"])

        var selected = "a"
        let picker = Picker(selection: Binding(get: { selected }, set: { selected = $0 })) {
            HStack {
                Text("").tag("a")
                Image(systemName: "photo.fill").tag("b")
            }
        } label: {
            Image(systemName: "textformat")
        }
        #expect(picker.label == "doc.text")
        #expect(picker.options == ["a", "folder.badge.plus"])
        picker.onChanged?(1)
        #expect(selected == "b")
        picker.onChanged?(99)
        #expect(selected == "b")

        let directory = try temporaryDirectory()
        let pngURL = directory.appendingPathComponent("drop").appendingPathExtension("png")
        let textURL = directory.appendingPathComponent("drop").appendingPathExtension("txt")
        try Data([1, 2, 3]).write(to: pngURL)
        try Data([4, 5, 6]).write(to: textURL)

        var targeted = false
        var droppedProviderCount = 0
        let dropView = Text("Drop").onDrop(
            of: [.png],
            isTargeted: Binding(get: { targeted }, set: { targeted = $0 })
        ) { providers in
            droppedProviderCount = providers.count
            return true
        }
        #expect(dropView.action([pngURL, textURL], .init(x: 0, y: 0)))
        #expect(droppedProviderCount == 1)
        dropView.isTargeted?(true)
        #expect(targeted)
    }

    @Test("compatibility helpers expose deterministic Linux behavior")
    func compatibilityHelpersExposeDeterministicLinuxBehavior() {
        _ = Color.foreground
        _ = Color.labelCustom
        _ = Color.systemGray
        _ = Color.systemGray2
        _ = Color.systemBlue
        _ = Color.systemRed
        _ = Color(.pink)
        _ = Color(.black)
        _ = Color(.white)
        _ = Color.gray2Custom
        _ = Color.gray3Custom
        _ = Color.gray4Custom
        _ = Color.bgCustom

        #expect(Color("label") == Color(red: 0.12, green: 0.12, blue: 0.13))
        #expect(Color("grayCustom") == Color(red: 0.56, green: 0.56, blue: 0.58))
        #expect(Color("gray2Custom") == Color(red: 0.68, green: 0.68, blue: 0.70))
        #expect(Color("gray3Custom") == Color(red: 0.78, green: 0.78, blue: 0.80))
        #expect(Color("gray4Custom") == Color(red: 0.86, green: 0.86, blue: 0.88))
        #expect(Color("gray5Custom") == Color(red: 0.91, green: 0.91, blue: 0.94))
        #expect(Color("bgCustom") == Color(red: 0.96, green: 0.96, blue: 0.97))
        #expect(Color("unknown") == .primary)
        #expect(Color(.sRGB, red: 2, green: -1, blue: 0.5, opacity: 2) == Color(red: 2, green: -1, blue: 0.5, opacity: 2))

        let platformImage = PlatformImage(data: Data([1, 2, 3]))
        #expect(platformImage.data == Data([1, 2, 3]))
        let renderer = ImageRenderer(content: Text("Render"))
        renderer.scale = 2
        #expect(renderer.scale == 2)
        #expect(renderer.uiImage == nil)
        #expect(renderer.nsImage == nil)

        let openedURL = LockedTestValue<URL?>(nil)
        let openURL = OpenURLAction { url in
            openedURL.set(url)
            return true
        }
        let url = URL(string: "https://example.com")!
        #expect(openURL(url))
        #expect(openedURL.value == url)

        var environment = EnvironmentValues()
        environment.openURL = openURL
        #expect(environment.openURL(url))
        #expect(openedURL.value == url)

        let dismissed = LockedTestValue(false)
        let presentationMode = PresentationMode {
            dismissed.set(true)
        }
        presentationMode.dismiss()
        #expect(dismissed.value)

        let environmentDismissed = LockedTestValue(false)
        environment.presentationMode = PresentationMode {
            environmentDismissed.set(true)
        }
        environment.presentationMode.dismiss()
        _ = environment.presentationMode.wrappedValue
        #expect(environmentDismissed.value)

        var value = "before"
        let binding = Binding(get: { value }, set: { value = $0 }).animation(.easeOut(duration: 0.1))
        binding.wrappedValue = "after"
        #expect(value == "after")

        var roleButtonTapped = false
        let destructive = Button("Delete", role: .destructive) {
            roleButtonTapped = true
        }
        destructive.action()
        #expect(roleButtonTapped)

        var customRoleButtonTapped = false
        let custom = Button(role: .cancel) {
            customRoleButtonTapped = true
        } label: {
            Text("Cancel")
        }
        custom.action()
        #expect(customRoleButtonTapped)

        var textValue = "hello"
        _ = TextField("Message", text: Binding(get: { textValue }, set: { textValue = $0 }), axis: .vertical)
        var committed = false
        _ = TextField("Message", text: Binding(get: { textValue }, set: { textValue = $0 })) {
            committed = true
        }
        #expect(committed == false)

        _ = Image(data: Data([0x89, 0x50, 0x4E, 0x47]))
        _ = Image("sidebar-icon")
        let taskView = Text("Task").task {}
        #expect(String(describing: type(of: taskView)).contains("ModifiedContent"))
        _ = Text("Scheme").preferredColorScheme(nil).listStyle(PlainListStyle())

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUI-UpstreamCompatibilityTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let importedURL = directory.appendingPathComponent("import").appendingPathExtension("png")
        try? Data([9]).write(to: importedURL)
        QuillFileImporter.setTestSelection(importedURL)
        defer { QuillFileImporter.setTestSelection(nil) }

        var importPresented = true
        var importedResult: Result<URL, Error>?
        let importerView = Text("Import").fileImporter(
            isPresented: Binding(get: { importPresented }, set: { importPresented = $0 }),
            allowedContentTypes: [.png],
            onCompletion: { importedResult = $0 }
        )
        importerView.action(false)
        #expect(importPresented)
        importerView.action(true)
        #expect(importPresented == false)
        if case .success(let selectedURL) = importedResult {
            #expect(selectedURL == importedURL)
        } else {
            Issue.record("Expected reflected fileImporter action to select the test PNG")
        }

        _ = Text("Color style").foregroundStyle(Color.label)
        _ = Text("Empty gradient").foregroundStyle(
            LinearGradient(colors: [], startPoint: .leading, endPoint: .trailing)
        )
        _ = Text("Radial style").foregroundStyle(
            RadialGradient(colors: [.systemBlue, .systemRed], center: .center, startRadius: 0, endRadius: 20)
        )
        _ = Text("Unknown style").foregroundStyle(42)
        _ = Text("Shape mask").mask(Rectangle())
        _ = Text("View mask").mask(Text("Mask"))
        _ = Text("Grouped form").formStyle(GroupedFormStyle())
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUI-UpstreamCompatibilityTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private func reflectedChild<T>(_ value: Any, named name: String, as type: T.Type = T.self) -> T? {
    Mirror(reflecting: value)
        .children
        .first { $0.label == name }?
        .value as? T
}

private func materializeStructuralViewTree(_ value: Any, depth: Int = 10) {
    guard depth > 0 else { return }

    if let multi = value as? any MultiChildView {
        for child in multi.children {
            materializeStructuralViewTree(child, depth: depth - 1)
        }
    }

    let mirror = Mirror(reflecting: value)
    let shouldWalkAllChildren: Bool
    switch mirror.displayStyle {
    case .collection, .optional, .tuple:
        shouldWalkAllChildren = true
    default:
        shouldWalkAllChildren = false
    }

    for child in mirror.children {
        guard shouldWalkAllChildren || child.label == "content" || child.label == "children" || child.label == "value" else {
            continue
        }
        materializeStructuralViewTree(child.value, depth: depth - 1)
    }
}

private final class LockedTestValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock {
            storage = value
        }
    }
}
#endif
