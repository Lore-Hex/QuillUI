import Foundation

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import SwiftUI

/// Runs GTK work on one dedicated OS thread for the whole test process.
///
/// GTK is thread-affine: its home thread is wherever `gtk_init` ran, and
/// widget construction, CSS, and pango state must stay on that thread. But
/// swift-testing services `@MainActor` test jobs on cooperative-pool threads
/// on Linux (`SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE=legacy` — set
/// workflow-wide in linux-ci.yml — makes the `MainActor.assumeIsolated`
/// inside `gtkRenderView` permissive rather than trapping). Actor
/// serialization does not pin the OS thread, so a test that calls
/// `gtkRenderView` directly migrates GTK across threads and can segfault —
/// proven by PR #581's first CI run (Thread 14 crashed in
/// `Button.gtkCreateWidget` under `Runner._runTestCase`, run 28564318558).
///
/// Every GTK-touching test must wrap its GTK work in `perform` (or use the
/// `render`/`drainMainContext` conveniences), which executes it synchronously
/// on the pinned home thread. `gtk_init_check` itself runs on that thread, so
/// the home thread is the host thread by construction. Source hygiene
/// enforces the pairing (see "GTK widget tests route through GTKTestHost").
final class GTKTestHost: @unchecked Sendable {
    static let shared = GTKTestHost()

    private final class WorkItem: @unchecked Sendable {
        let run: () -> Void
        let done = DispatchSemaphore(value: 0)

        init(_ run: @escaping () -> Void) {
            self.run = run
        }
    }

    private let condition = NSCondition()
    private var pending: [WorkItem] = []
    private var started = false
    private var gtkAvailable = false
    // Written once on the host thread before `started` is broadcast; `init`
    // blocks on that, so post-init reads are ordered after the write.
    private var hostThread: Thread?

    /// Whether GTK could initialize on the host thread (false in display-less
    /// environments where `gtk_init_check` fails — tests should skip).
    var isGTKAvailable: Bool {
        condition.lock()
        defer { condition.unlock() }
        return gtkAvailable
    }

    private init() {
        let thread = Thread { [self] in
            let available = gtk_is_initialized() != 0 || gtk_init_check() != 0
            condition.lock()
            gtkAvailable = available
            hostThread = Thread.current
            started = true
            condition.broadcast()
            while true {
                while pending.isEmpty {
                    condition.wait()
                }
                let item = pending.removeFirst()
                condition.unlock()
                item.run()
                item.done.signal()
                condition.lock()
            }
        }
        thread.name = "GTKTestHost"
        thread.stackSize = 4 << 20
        thread.start()

        condition.lock()
        while !started {
            condition.wait()
        }
        condition.unlock()
    }

    /// Executes `body` synchronously on the GTK home thread and returns its
    /// result. Re-entrant: a `perform` from within host-thread work runs
    /// inline instead of deadlocking.
    func perform<T>(_ body: () throws -> T) throws -> T {
        if Thread.current === hostThread {
            return try body()
        }
        var result: Result<T, Error>?
        withoutActuallyEscaping(body) { escapable in
            let box = ResultBox<T>()
            let item = WorkItem {
                box.value = Result(catching: escapable)
            }
            condition.lock()
            pending.append(item)
            condition.broadcast()
            condition.unlock()
            item.done.wait()
            result = box.value
        }
        return try result!.get()
    }

    func perform<T>(_ body: () -> T) -> T {
        try! perform({ () throws -> T in body() })
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: Result<T, Error>?
    }

    /// Renders a SwiftUI view into a GTK widget on the home thread.
    func render(_ view: some View) -> UnsafeMutablePointer<GtkWidget> {
        perform { widgetFromOpaque(gtkRenderView(view)) }
    }

    /// Iterates the default GLib main context on the home thread so idle
    /// sources (button actions, focus grabs) fire where they were installed.
    func drainMainContext(maxIterations: Int = 100) {
        perform {
            for _ in 0..<maxIterations {
                if g_main_context_iteration(nil, 0) == 0 {
                    break
                }
            }
        }
    }
}
#endif
