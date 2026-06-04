import Foundation
import Testing
@testable import QuillRSCoreShim

/// Captures notification deliveries synchronously. `NotificationCenter.post`
/// runs observers inline on the posting thread, so the test reads these back
/// immediately after posting. `@unchecked Sendable` is sound here because every
/// access happens on the main thread within a single `@MainActor` test.
private final class ProgressNotificationSpy: @unchecked Sendable {
    var fireCount = 0
    var lastObject: AnyObject?
}

/// Pins the vendored RSCore `RSProgress` family. The contract that matters is
/// the normalization invariant the doc comment promises: after every mutation
/// `numberOfTasks == numberCompleted + numberRemaining` and all three are `>= 0`
/// — refresh UI math depends on it never going nonsense.
@Suite("QuillRSCoreShim — RSProgress / ProgressInfo (RSCore refresh progress)")
@MainActor
struct RSProgressTests {

    /// The invariant the RSProgress doc comment guarantees.
    private func expectConsistent(_ p: RSProgress, _ label: String = "") {
        #expect(p.numberOfTasks >= 0, "numberOfTasks >= 0 \(label)")
        #expect(p.numberCompleted >= 0, "numberCompleted >= 0 \(label)")
        #expect(p.numberRemaining >= 0, "numberRemaining >= 0 \(label)")
        #expect(p.numberOfTasks == p.numberCompleted + p.numberRemaining,
                "tasks == completed + remaining \(label)")
    }

    // MARK: - ProgressInfo value type

    @Test("ProgressInfo defaults to zero and reports complete")
    func progressInfoDefaults() {
        let info = ProgressInfo()
        #expect(info.numberOfTasks == 0)
        #expect(info.numberCompleted == 0)
        #expect(info.numberRemaining == 0)
        #expect(info.isComplete) // numberRemaining < 1
    }

    @Test("ProgressInfo is incomplete while work remains")
    func progressInfoIncomplete() {
        let info = ProgressInfo(numberOfTasks: 3, numberCompleted: 1, numberRemaining: 2)
        #expect(!info.isComplete)
    }

    @Test("ProgressInfo.combined sums the three counts across infos")
    func progressInfoCombined() {
        let combined = ProgressInfo.combined([
            ProgressInfo(numberOfTasks: 2, numberCompleted: 1, numberRemaining: 1),
            ProgressInfo(numberOfTasks: 5, numberCompleted: 2, numberRemaining: 3),
            ProgressInfo(),
        ])
        #expect(combined.numberOfTasks == 7)
        #expect(combined.numberCompleted == 3)
        #expect(combined.numberRemaining == 4)
    }

    // MARK: - RSProgress mutation + invariant

    @Test("init seeds remaining from the estimate and clamps negatives to zero")
    func initSeedsRemaining() {
        let p = RSProgress(numberOfTasks: 5)
        #expect(p.numberOfTasks == 5)
        #expect(p.numberRemaining == 5)
        #expect(p.numberCompleted == 0)
        expectConsistent(p, "after init")

        let neg = RSProgress(numberOfTasks: -3)
        #expect(neg.numberOfTasks == 0)
        #expect(neg.numberRemaining == 0)
        expectConsistent(neg, "after negative init")
    }

    @Test("completeTask advances completed and keeps the invariant")
    func completeTask() {
        let p = RSProgress(numberOfTasks: 2)
        p.completeTask()
        #expect(p.numberCompleted == 1)
        #expect(p.numberRemaining == 1)
        expectConsistent(p, "after one completion of two")
        #expect(p.progressInfo == ProgressInfo(numberOfTasks: 2, numberCompleted: 1, numberRemaining: 1))
    }

    @Test("completing more than estimated grows the total to keep the invariant")
    func completeBeyondEstimate() {
        let p = RSProgress(numberOfTasks: 2)
        p.completeTasks(5)
        #expect(p.numberCompleted == 5)
        #expect(p.numberOfTasks == 5) // estimate caught up to reality
        #expect(p.numberRemaining == 0)
        expectConsistent(p, "after over-completion")
    }

    @Test("addTasks grows the total and the remaining work")
    func addTasks() {
        let p = RSProgress(numberOfTasks: 1)
        p.completeTask()           // 1 of 1 done
        p.addTasks(3)              // estimate grew
        #expect(p.numberOfTasks == 4)
        #expect(p.numberCompleted == 1)
        #expect(p.numberRemaining == 3)
        expectConsistent(p, "after adding tasks post-completion")
    }

    @Test("updateNumberRemaining clamps negatives and recomputes completed")
    func updateNumberRemaining() {
        let p = RSProgress(numberOfTasks: 10)
        p.updateNumberRemaining(4)
        #expect(p.numberRemaining == 4)
        #expect(p.numberCompleted == 6)
        expectConsistent(p, "after setting remaining within estimate")

        p.updateNumberRemaining(-1) // clamped to 0
        #expect(p.numberRemaining == 0)
        expectConsistent(p, "after negative remaining")
    }

    @Test("updateNumberCompleted beyond the estimate grows the total")
    func updateNumberCompleted() {
        let p = RSProgress(numberOfTasks: 3)
        p.updateNumberCompleted(8)
        #expect(p.numberCompleted == 8)
        #expect(p.numberOfTasks == 8)
        #expect(p.numberRemaining == 0)
        expectConsistent(p, "after completed exceeds estimate")
    }

    @Test("completeAll zeroes remaining; reset zeroes everything")
    func completeAllThenReset() {
        let p = RSProgress(numberOfTasks: 4)
        p.completeAll()
        #expect(p.numberCompleted == 4)
        #expect(p.numberRemaining == 0)
        expectConsistent(p, "after completeAll")

        p.reset()
        #expect(p.numberOfTasks == 0)
        #expect(p.numberCompleted == 0)
        #expect(p.numberRemaining == 0)
        expectConsistent(p, "after reset")
    }

    @Test("addChild folds the child's progress into the parent's progressInfo")
    func childAggregation() {
        let parent = RSProgress(numberOfTasks: 2)
        parent.completeTask() // parent: 1 of 2

        let child = RSProgress(numberOfTasks: 4)
        child.completeTasks(1) // child: 1 of 4

        parent.addChild(child)

        // progressInfo aggregates parent + child raw counts.
        #expect(parent.progressInfo.numberOfTasks == 6)   // 2 + 4
        #expect(parent.progressInfo.numberCompleted == 2) // 1 + 1
        #expect(parent.progressInfo.numberRemaining == 4) // 1 + 3
    }

    // MARK: - ProgressInfoReporter notification

    @Test("changing progressInfo posts .progressInfoDidChange with the reporter as object")
    func progressNotificationFires() {
        let spy = ProgressNotificationSpy()
        let token = NotificationCenter.default.addObserver(
            forName: .progressInfoDidChange, object: nil, queue: nil
        ) { note in
            spy.fireCount += 1
            spy.lastObject = note.object as AnyObject?
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let p = RSProgress(numberOfTasks: 2)
        p.completeTask() // progressInfo (0,0,0) -> (2,1,1): changed -> posts

        #expect(spy.fireCount == 1)
        #expect(spy.lastObject === p)
    }

    @Test("an unchanged progressInfo does not post")
    func noNotificationWhenUnchanged() {
        let spy = ProgressNotificationSpy()
        let token = NotificationCenter.default.addObserver(
            forName: .progressInfoDidChange, object: nil, queue: nil
        ) { _ in
            spy.fireCount += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let p = RSProgress() // progressInfo already == ProgressInfo()
        p.reset()            // recomputes to the same (0,0,0): no change, no post

        #expect(spy.fireCount == 0)
    }
}
