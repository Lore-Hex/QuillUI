import Foundation
import Testing
@testable import QuillRSCoreShim

@Suite("QuillRSCoreShim — MainThreadOperationQueue")
@MainActor
struct MainThreadOperationTests {

    @Test("runs an available operation and calls its completion block")
    func runsOperationAndCompletion() async {
        var events = [String]()
        let queue = MainThreadOperationQueue()
        let operation = RecordingOperation(name: "single") {
            events.append("run")
        }
        operation.completionBlock = { _ in
            events.append("complete")
        }

        queue.add(operation)
        await waitFor {
            events == ["run", "complete"] && queue.pendingOperationsCount == 0
        }

        #expect(events == ["run", "complete"])
        #expect(queue.pendingOperationsCount == 0)
    }

    @Test("honors dependencies before running dependent operations")
    func runsDependenciesFirst() async {
        var events = [String]()
        let queue = MainThreadOperationQueue()
        let parent = RecordingOperation(name: "parent") {
            events.append("parent")
        }
        let child = RecordingOperation(name: "child") {
            events.append("child")
        }
        child.addDependency(parent)

        queue.add(child)
        await Task.yield()
        #expect(events.isEmpty)
        #expect(queue.pendingOperationsCount == 1)

        queue.add(parent)
        await waitFor {
            events == ["parent", "child"] && queue.pendingOperationsCount == 0
        }

        #expect(events == ["parent", "child"])
        #expect(queue.pendingOperationsCount == 0)
    }
}

@MainActor
private func waitFor(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<50 {
        if condition() {
            return
        }
        await Task.yield()
    }
}

@MainActor
private final class RecordingOperation: MainThreadOperation, @unchecked Sendable {
    private let body: () -> Void

    init(name: String, body: @escaping () -> Void) {
        self.body = body
        super.init(name: name)
    }

    override func run() {
        body()
        didComplete()
    }
}
