import Testing

#if os(Linux)
@testable import BackendGTK4
import QuillSwiftUICompatibility
import SwiftUI

@Suite("GTK describe cycle guard")
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
        let captured = gtkDescribeCapturingCanvasPayloads {
            gtkDescribeView(ExploreTaskModifierProbe())
        }

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
#endif
