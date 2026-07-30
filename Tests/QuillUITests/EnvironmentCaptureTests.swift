#if os(Linux)
import Foundation
import SwiftUI
import Testing

private struct QuillDeferredEnvironmentKey: EnvironmentKey {
    static let defaultValue = "default"
}

private extension EnvironmentValues {
    var quillDeferredValue: String {
        get { self[QuillDeferredEnvironmentKey.self] }
        set { self[QuillDeferredEnvironmentKey.self] = newValue }
    }
}

private final class QuillLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

private final class QuillInjectedEnvironmentProbe: @unchecked Sendable {}

private final class QuillEnvironmentValuesBox: @unchecked Sendable {
    let values: EnvironmentValues

    init(_ values: EnvironmentValues) {
        self.values = values
    }
}

private final class QuillEnvironmentScopeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (value: String, hadTask: Bool)?

    func store(value: String, hadTask: Bool) {
        lock.withLock { storage = (value, hadTask) }
    }

    var value: (value: String, hadTask: Bool)? {
        lock.withLock { storage }
    }
}

@Suite("Deferred presentation context")
struct EnvironmentCaptureTests {
    @Test("A task created by a sheet action can dismiss after await")
    func childTaskInheritsDismissAction() async {
        let counter = QuillLockedCounter()
        var environment = EnvironmentValues()
        environment.dismiss = DismissAction(
            handler: { counter.increment() },
            debugName: "deferred-presentation-test"
        )
        guard let dismissAction = swiftOpenUIResolvePresentationDismissAction(in: environment) else {
            Issue.record("Expected the environment's presentation dismiss action")
            return
        }

        let task: Task<Void, Never> = swiftOpenUIWithPresentationDismissAction(dismissAction) {
            Task<Void, Never> {
                await Task.yield()
                Environment(\.dismiss).wrappedValue()
            }
        }

        await task.value
        #expect(counter.value == 1)
    }

    @Test("Nested presentation contexts restore their parent action")
    func nestedPresentationContextsRestore() {
        let outerCounter = QuillLockedCounter()
        let innerCounter = QuillLockedCounter()

        swiftOpenUIWithPresentationDismissAction({ outerCounter.increment() }) {
            swiftOpenUICurrentPresentationDismissAction()?()
            swiftOpenUIWithPresentationDismissAction({ innerCounter.increment() }) {
                swiftOpenUICurrentPresentationDismissAction()?()
            }
            swiftOpenUICurrentPresentationDismissAction()?()
        }

        #expect(outerCounter.value == 2)
        #expect(innerCounter.value == 1)
        #expect(swiftOpenUICurrentPresentationDismissAction() == nil)
    }

    @Test("The async environment scope survives suspension")
    func asyncEnvironmentSurvivesSuspension() async {
        var environment = EnvironmentValues()
        environment.quillDeferredValue = "async"

        let value = await withTaskEnvironment(environment) {
            await Task.yield()
            return Environment(\.quillDeferredValue).wrappedValue
        }
        #expect(value == "async")
    }

    @Test("A child task inherits a synchronous callback environment before its first read")
    func childTaskInheritsSynchronousEnvironment() async {
        let probe = QuillInjectedEnvironmentProbe()
        var environment = EnvironmentValues()
        environment.setObject(probe)

        let task: Task<Bool, Never> = withSynchronousTaskEnvironment(environment) {
            Task {
                await Task.yield()
                return Environment(QuillInjectedEnvironmentProbe.self).wrappedValue === probe
            }
        }

        #expect(await task.value)
    }

    @Test("A native thread without a Swift task uses the safe environment fallback")
    func synchronousEnvironmentWithoutCurrentTaskUsesThreadScope() {
        var environment = EnvironmentValues()
        environment.quillDeferredValue = "native-thread"
        let environmentBox = QuillEnvironmentValuesBox(environment)
        let result = QuillEnvironmentScopeResult()
        let completed = DispatchSemaphore(value: 0)

        Thread.detachNewThread {
            let value = withSynchronousTaskEnvironment(environmentBox.values) {
                let hadTask = withUnsafeCurrentTask { $0 != nil }
                return (Environment(\.quillDeferredValue).wrappedValue, hadTask)
            }
            result.store(value: value.0, hadTask: value.1)
            completed.signal()
        }

        #expect(completed.wait(timeout: .now() + 2) == .success)
        #expect(result.value?.value == "native-thread")
        #expect(result.value?.hadTask == false)
    }
}
#endif
