import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import SwiftUI

@Suite("GTK refresh shortcut visibility", .serialized)
@MainActor
struct GTKRefreshShortcutVisibilityTests {
    @Test("hidden refreshable does not steal shortcut from visible stack page")
    func hiddenRefreshableDoesNotStealShortcutFromVisibleStackPage() async {
        guard gtkTestDisplayIsAvailable() else { return }

        let previousEnvironment = getCurrentEnvironment()
        var environment = previousEnvironment
        environment.windowID = 948_201
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previousEnvironment) }

        let visibleCount = GTKRefreshCounter()
        let hiddenCount = GTKRefreshCounter()

        // Register the visible destination first, then the hidden root. The
        // registry must skip the newer hidden registration during dispatch.
        let visiblePage = widgetFromOpaque(gtkRenderView(
            ScrollView { Text("Status detail") }
                .refreshable { visibleCount.value += 1 }
        ))
        let hiddenPage = widgetFromOpaque(gtkRenderView(
            ScrollView { Text("Home") }
                .refreshable { hiddenCount.value += 1 }
        ))

        let stack = gtk_stack_new()!
        gtk_stack_add_named(OpaquePointer(stack), visiblePage, "detail")
        gtk_stack_add_named(OpaquePointer(stack), hiddenPage, "home")
        gtk_stack_set_visible_child_name(OpaquePointer(stack), "detail")

        let window = gtk_window_new()!
        defer {
            gtk_window_destroy(windowPointer(window))
            drainRefreshShortcutGTKMainContext()
        }
        gtk_window_set_child(windowPointer(window), stack)
        gtk_window_present(windowPointer(window))
        drainRefreshShortcutGTKMainContext(maxIterations: 100)

        #expect(gtk_widget_get_mapped(visiblePage) != 0)
        #expect(gtk_widget_get_mapped(hiddenPage) == 0)

        let shortcut = KeyboardShortcut(KeyEquivalent("r"), modifiers: .command)
        #expect(KeyboardShortcutRegistry.shared.dispatch(shortcut, windowID: environment.windowID))

        for _ in 0..<20 where visibleCount.value == 0 {
            await Task.yield()
            drainRefreshShortcutGTKMainContext()
        }
        #expect(visibleCount.value == 1)
        #expect(hiddenCount.value == 0)
    }
}

private final class GTKRefreshCounter: @unchecked Sendable {
    var value = 0
}

private func drainRefreshShortcutGTKMainContext(maxIterations: Int = 20) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
#endif
