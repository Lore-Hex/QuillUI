import Foundation
import Testing
@testable import QuillRSCoreShim

private final class BatchSpy: @unchecked Sendable {
    var fireCount = 0
}

/// Pins the vendored RSCore `BatchUpdate` nesting counter: `isPerforming`
/// tracks start/end depth, and `.BatchUpdateDidPerform` posts exactly once when
/// the outermost batch ends. Fresh instances are used (not `.shared`) to avoid
/// cross-test state. All main-thread + synchronous, so it's deterministic.
@Suite("QuillRSCoreShim — BatchUpdate (coalescing counter)")
@MainActor
struct BatchUpdateTests {

    private func observe(_ spy: BatchSpy) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .BatchUpdateDidPerform, object: nil, queue: nil
        ) { _ in spy.fireCount += 1 }
    }

    @Test("isPerforming tracks nested start/end depth")
    func nestedDepth() {
        let b = BatchUpdate()
        #expect(!b.isPerforming)
        b.start(); #expect(b.isPerforming)
        b.start(); #expect(b.isPerforming)   // depth 2
        b.end();   #expect(b.isPerforming)    // back to depth 1
        b.end();   #expect(!b.isPerforming)   // back to 0
    }

    @Test("perform runs the block while performing and is not performing after")
    func performBlock() {
        let b = BatchUpdate()
        var performingDuringBlock = false
        b.perform { performingDuringBlock = b.isPerforming }
        #expect(performingDuringBlock)
        #expect(!b.isPerforming)
    }

    @Test("ending the outermost batch posts .BatchUpdateDidPerform once")
    func notificationOnOutermostEnd() {
        let spy = BatchSpy()
        let token = observe(spy)
        defer { NotificationCenter.default.removeObserver(token) }

        let b = BatchUpdate()
        b.start()
        b.start()
        b.end()
        #expect(spy.fireCount == 0)  // still nested, no post yet
        b.end()
        #expect(spy.fireCount == 1)  // outermost end -> exactly one post
    }

    @Test("a nested perform inside a batch does not post until the batch ends")
    func nestedPerformNoEarlyPost() {
        let spy = BatchSpy()
        let token = observe(spy)
        defer { NotificationCenter.default.removeObserver(token) }

        let b = BatchUpdate()
        b.start()           // depth 1
        b.perform { }       // depth 1 -> 2 -> 1, no post
        #expect(spy.fireCount == 0)
        b.end()             // depth 0 -> post
        #expect(spy.fireCount == 1)
    }
}
