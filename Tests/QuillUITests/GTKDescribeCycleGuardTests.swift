import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import QuillSwiftUICompatibility
import SwiftUI

@Suite("GTK describe cycle guard", .serialized)
@MainActor
struct GTKDescribeCycleGuardTests {
    @Test("cyclic AnyView body records diagnostic chain")
    func cyclicAnyViewBodyRecordsDiagnosticChain() {
        let previousHandler = gtkDescribeDepthLimitExceededHandler
        var capturedNames: [String] = []

        gtkDescribeDepthLimitExceededHandler = { names in
            capturedNames = names
        }
        defer { gtkDescribeDepthLimitExceededHandler = previousHandler }

        _ = gtkDescribeView(Cyclic())

        #expect(capturedNames.count == 8)
        #expect(
            capturedNames.contains { $0.contains("Cyclic") },
            "Expected cycle chain to include Cyclic, got \(capturedNames.joined(separator: " -> "))"
        )
    }

    @Test("TabView descriptor captures task payloads from tab content")
    func tabViewDescriptorCapturesTaskPayloadsFromTabContent() {
        let captured = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(TabTaskDescriptorProbe())
        }

        #expect(
            captured.taskPayloads.count == 1,
            "Expected TabView descriptor capture to include the .task payload from its selected-route content"
        )
    }

    @Test("Explore-style modifier chain preserves task payloads")
    func exploreStyleModifierChainPreservesTaskPayloads() {
        let view = ExploreTaskModifierProbe()
        let parentCaptured = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(view)
        }
        let captured = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(view.body)
        }

        #expect(parentCaptured.descriptor.kind == .statefulLifecycleScope)
        #expect(
            parentCaptured.taskPayloads.isEmpty,
            "The parent descriptor must not steal tasks owned by the nested stateful host"
        )
        #expect(
            captured.taskPayloads.count == 2,
            "Expected both the load .task and search .task(id:) payloads to survive the Explore modifier chain"
        )
    }

    @Test("task(id:) carries lifecycle identity")
    func taskIDCarriesLifecycleIdentity() {
        let alpha = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(TaskIDProbe(taskID: "alpha"))
        }
        let beta = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(TaskIDProbe(taskID: "beta"))
        }

        #expect(alpha.taskPayloads.count == 1)
        #expect(beta.taskPayloads.count == 1)
        #expect(alpha.taskPayloads.first?.lifecycleID?.contains("alpha") == true)
        #expect(beta.taskPayloads.first?.lifecycleID?.contains("beta") == true)
        #expect(alpha.taskPayloads.first?.lifecycleID != beta.taskPayloads.first?.lifecycleID)
    }

    @Test("ForEach descriptor identities survive row reordering")
    func forEachDescriptorIdentitiesSurviveReordering() throws {
        let oldRoot = gtkIdentifyDescriptorTree(
            gtkDescribeView(ForEach([1, 2], id: \.self) { Text("\($0)") })
        )
        let newRoot = gtkIdentifyDescriptorTree(
            gtkDescribeView(ForEach([2, 1], id: \.self) { Text("\($0)") })
        )
        let oldByType = Dictionary(
            uniqueKeysWithValues: oldRoot.children.map { ($0.descriptor.typeName, $0.identity) }
        )
        let newByType = Dictionary(
            uniqueKeysWithValues: newRoot.children.map { ($0.descriptor.typeName, $0.identity) }
        )

        #expect(Set(oldByType.keys) == Set(newByType.keys))
        for typeName in oldByType.keys {
            #expect(typeName.hasPrefix("GTKStateNamespaceView<ForEach["))
            #expect(try #require(oldByType[typeName]) == newByType[typeName])
        }
    }

    @Test("ForEach nested with siblings keeps keyed button actions")
    func nestedForEachKeepsKeyedButtonActions() throws {
        var activated: [Int] = []
        let captured = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(
                VStack {
                    ForEach([1, 2], id: \.self) { value in
                        Button("Account \(value)") {
                            activated.append(value)
                        }
                    }
                    Text("Add Account")
                }
            )
        }
        let root = gtkIdentifyDescriptorTree(captured.descriptor)
        let payloads = gtkButtonPayloadsByIdentity(
            descriptorRoot: root,
            payloads: captured.buttonPayloads
        )

        func firstNode(
            in node: GTK4IdentifiedDescriptorNode,
            matching predicate: (GTK4IdentifiedDescriptorNode) -> Bool
        ) -> GTK4IdentifiedDescriptorNode? {
            if predicate(node) { return node }
            for child in node.children {
                if let match = firstNode(in: child, matching: predicate) {
                    return match
                }
            }
            return nil
        }

        let forEach = try #require(firstNode(in: root) {
            $0.descriptor.typeName.hasPrefix("ForEach<")
        })
        #expect(forEach.children.count == 2)
        #expect(forEach.children.allSatisfy {
            $0.descriptor.typeName.hasPrefix("GTKStateNamespaceView<ForEach[")
        })

        for keyedRow in forEach.children {
            let button = try #require(firstNode(in: keyedRow) {
                $0.descriptor.kind == .button
            })
            let payload = try #require(payloads[button.identity])
            payload.action()
        }
        #expect(activated == [1, 2])
    }

    @Test("List ForEach buttons execute the model painted in each row")
    func listForEachButtonsExecutePaintedModel() throws {
        guard gtkTestDisplayIsAvailable() else { return }

        var activated: [Int] = []
        let alpha = State(wrappedValue: KeyedButtonProbe(id: 1, title: "alpha loading"))
        let zulu = State(wrappedValue: KeyedButtonProbe(id: 2, title: "zulu loading"))
        let widget = widgetFromOpaque(gtkRenderView(
            List {
                Section {
                    ForEach([
                        KeyedButtonStateProbe(id: 1, account: alpha),
                        KeyedButtonStateProbe(id: 2, account: zulu),
                    ]) { row in
                        KeyedButtonRowProbe(account: row.account) { accountID in
                            activated.append(accountID)
                        }
                    }
                    Text("Add Account")
                }
            }
        ))
        let window = gtk_window_new()!
        gtk_window_set_child(windowPointer(window), widget)
        defer {
            gtk_window_destroy(windowPointer(window))
            drainGTKMainContext(maxIterations: 100)
        }
        drainGTKMainContext(maxIterations: 100)

        // Resolve the rows in the opposite order, matching independent async
        // credential requests completing after the initial list render.
        zulu.storage.setValue(KeyedButtonProbe(id: 2, title: "zulu@mastodon.social"))
        drainGTKMainContext(maxIterations: 100)
        alpha.storage.setValue(KeyedButtonProbe(id: 1, title: "alpha@mastodon.social"))
        drainGTKMainContext(maxIterations: 100)

        var buttons: [UnsafeMutablePointer<GtkWidget>] = []
        collectGTKButtons(in: widget, into: &buttons)
        let alphaButton = try #require(buttons.first { button in
            guard let label = try? firstGTKLabel(in: button) else { return false }
            return String(cString: gtk_label_get_text(OpaquePointer(label))) == "alpha@mastodon.social"
        })

        #expect(gtkTestActivateButton(alphaButton))
        drainGTKMainContext(maxIterations: 100)
        #expect(activated == [1])
    }

    @Test("SwiftUI shadow foregroundStyle reaches GTK labels through wrappers")
    func swiftUIShadowForegroundStyleReachesGTKLabelsThroughWrappers() throws {
        if !gtkTestDisplayIsAvailable() {
            return
        }

        let widget = widgetFromOpaque(gtkRenderView(
            LazyVStack([0]) { _ in
                Text("Ask QuillCode")
                    .font(.title3.weight(.semibold))
            }
            .background(Color(red: 0.03, green: 0.06, blue: 0.08))
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let window = gtk_window_new()!
        defer { gtk_window_destroy(windowPointer(window)) }
        gtk_window_set_child(windowPointer(window), widget)
        gtk_window_present(windowPointer(window))
        drainGTKMainContext(maxIterations: 100)
        let label = try firstGTKLabel(in: widget)

        #expect(String(cString: gtk_label_get_text(OpaquePointer(label))) == "Ask QuillCode")
        #expect(gtk_swift_label_get_use_markup(label) != 0)
    }

    @Test("SwiftUI shadow textSelection toggles GTK label selectability")
    func swiftUIShadowTextSelectionTogglesGTKLabelSelectability() throws {
        let enabled = Text("Selectable transcript").textSelection(.enabled)
        let disabled = Text("Locked transcript").textSelection(.disabled)

        let enabledIsSelectable: Bool
        switch enabled.selection {
        case .enabled: enabledIsSelectable = true
        case .disabled: enabledIsSelectable = false
        }
        #expect(enabledIsSelectable)

        let disabledIsSelectable: Bool
        switch disabled.selection {
        case .enabled: disabledIsSelectable = true
        case .disabled: disabledIsSelectable = false
        }
        #expect(!disabledIsSelectable)

        let typeName = String(describing: type(of: enabled))
        #expect(
            typeName.contains("QuillCompatibilityTextSelectionView") || typeName.contains("TextSelectionView"),
            "Expected a text-selection metadata wrapper, got \(typeName)"
        )
    }

    @Test("SwiftUI shadow onHover preserves callback metadata")
    func swiftUIShadowOnHoverPreservesCallbackMetadata() throws {
        var states: [Bool] = []
        let hoverable = Text("Hoverable transcript").onHover { states.append($0) }
        hoverable.action(true)
        hoverable.action(false)
        #expect(states == [true, false])
        let typeName = String(describing: type(of: hoverable))
        #expect(
            typeName.contains("QuillCompatibilityOnHoverView") || typeName.contains("OnHoverView"),
            "Expected a hover metadata wrapper, got \(typeName)"
        )
    }

    @Test("SwiftUI shadow allowsHitTesting preserves hit-test metadata")
    func swiftUIShadowAllowsHitTestingPreservesHitTestMetadata() throws {
        let disabled = Text("Decorative transcript").allowsHitTesting(false)
        let typeName = String(describing: type(of: disabled))
        #expect(
            typeName.contains("QuillCompatibilityAllowsHitTestingView") || typeName.contains("AllowsHitTestingView"),
            "Expected a hit-testing metadata wrapper, got \(typeName)"
        )
    }

    @Test("SwiftUI compatibility wrappers have transparent body fallbacks")
    func swiftUICompatibilityWrappersHaveTransparentBodyFallbacks() throws {
        let hitTesting = QuillCompatibilityAllowsHitTestingView(
            content: Text("Decorative transcript"),
            enabled: false
        )
        let shaped = QuillCompatibilityContentShapeView(
            content: Text("Expanded target"),
            shape: Rectangle()
        )
        let selectable = QuillCompatibilityTextSelectionView(
            content: Text("Selectable transcript"),
            selection: .enabled
        )
        let hoverable = QuillCompatibilityOnHoverView(
            content: Text("Hoverable transcript"),
            action: { _ in }
        )
        let labeled = AccessibilityLabelView(
            content: Text("Readable transcript"),
            label: "Readable transcript"
        )
        let valued = AccessibilityValueView(
            content: Text("Unread count"),
            value: "3 unread"
        )
        let hinted = AccessibilityHintView(
            content: Text("Open"),
            hint: "Opens the selected timeline"
        )
        let element = AccessibilityElementView(
            content: Text("Combined row"),
            children: .combine
        )

        #expect(String(describing: type(of: hitTesting.body)).contains("Text"))
        #expect(String(describing: type(of: shaped.body)).contains("Text"))
        #expect(String(describing: type(of: selectable.body)).contains("Text"))
        #expect(String(describing: type(of: hoverable.body)).contains("Text"))
        #expect(String(describing: type(of: labeled.body)).contains("Text"))
        #expect(String(describing: type(of: valued.body)).contains("Text"))
        #expect(String(describing: type(of: hinted.body)).contains("Text"))
        #expect(String(describing: type(of: element.body)).contains("Text"))
    }
}

private struct Cyclic: View {
    var body: some View {
        AnyView(Cyclic())
    }
}

private struct TabTaskDescriptorProbe: View {
    var body: some View {
        TabView(initialTab: 1) {
            Tab("Timeline", id: "timeline") {
                Text("Timeline")
            }
            Tab("Explore", id: "explore") {
                List {
                    Text("Explore row")
                }
                .task {}
            }
        }
    }
}

private enum ExploreTaskProbeScope: Hashable {
    case all
}

private struct ExploreTaskModifierProbe: View {
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @State private var searchScope = ExploreTaskProbeScope.all

    var body: some View {
        ScrollViewReader { _ in
            List {
                Text("Explore row")
            }
            .task {}
            .refreshable {}
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchQuery,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search")
            )
            .searchScopes($searchScope) {
                Text("All")
            }
            .task(id: searchQuery) {}
        }
    }
}

private struct TaskIDProbe: View {
    let taskID: String

    var body: some View {
        Text("Task ID")
            .task(id: taskID) {}
    }
}

private struct KeyedButtonProbe: Identifiable {
    let id: Int
    let title: String
}

private struct KeyedButtonStateProbe: Identifiable {
    let id: Int
    let account: State<KeyedButtonProbe>
}

private struct KeyedButtonRowProbe: View {
    @State private var account: KeyedButtonProbe
    let action: (Int) -> Void

    init(account: State<KeyedButtonProbe>, action: @escaping (Int) -> Void) {
        _account = account
        self.action = action
    }

    var body: some View {
        Button {
            action(account.id)
        } label: {
            Text(account.title)
        }
    }
}

private func collectGTKButtons(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into buttons: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if gtk_swift_widget_is_button(widget) != 0 {
        buttons.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        collectGTKButtons(in: current, into: &buttons)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func firstGTKLabel(in widget: UnsafeMutablePointer<GtkWidget>) throws -> UnsafeMutablePointer<GtkWidget> {
    if gtkWidgetTypeName(widget) == "GtkLabel" {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = try? firstGTKLabel(in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    struct MissingGTKLabel: Error {}
    throw MissingGTKLabel()
}

private func gtkWidgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func drainGTKMainContext(maxIterations: Int = 20) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
#endif
