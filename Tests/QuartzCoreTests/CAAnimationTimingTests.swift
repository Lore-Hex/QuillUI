//
//  CAAnimationTimingTests.swift
//  QuillUI — QuartzCore shim tests (Linux)
//
//  Exercises the FUNCTIONAL MODEL semantics of the QuartzCore shim:
//    - CAAnimationDelegate callbacks (animationDidStart / animationDidStop)
//      delivered asynchronously on the main queue after the effective duration.
//    - isRemovedOnCompletion semantics (auto-removal vs. sticky animations).
//    - CATransaction completion blocks: explicit begin/commit, implicit
//      transactions, nesting, setDisableActions scoping, and the guarantee
//      that a transaction's completion block runs only after the animations
//      added inside it have delivered their own completion.
//    - CADisplayLink: actually ticks its target via QuillSelectorDispatching,
//      honors isPaused, and maintains timestamp/targetTimestamp.
//
//  Honest Linux semantics: there is NO pixel rendering / compositing on
//  QuillOS yet (that arrives later via QuillPaint). These tests therefore
//  assert MODEL + TIMING behavior only — hierarchy, callback delivery, and
//  ordering — never rendered output.
//
//  CI-stability rules (few-core, starved Linux runners — hard-won):
//    - Every async assertion goes through XCTestExpectation + wait(for:timeout:)
//      with a timeout of at least 5 seconds.
//    - Animation durations are tiny (0.02...0.1s) so the nominal work is fast,
//      but we NEVER assert precise elapsed times — only ordering and eventual
//      delivery.
//    - No Thread.sleep polling loops; "grace periods" are modeled with
//      DispatchQueue.main.asyncAfter + an expectation so the run loop keeps
//      pumping while we wait.
//

import Foundation
import Dispatch
import XCTest
import QuartzCore

// MARK: - Helpers

/// Records CAAnimationDelegate callbacks and fulfills optional expectations.
/// Callbacks are expected on the main queue, but state is NSLock-guarded
/// anyway so the recorder is safe under @unchecked Sendable.
private final class AnimationDelegateRecorder: NSObject, CAAnimationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0
    private var finishedFlags: [Bool] = []

    let didStart: XCTestExpectation?
    let didStop: XCTestExpectation?

    /// Invoked from animationDidStop(_:finished:) BEFORE the didStop
    /// expectation is fulfilled. Used for cross-callback ordering checks.
    var onStop: ((Bool) -> Void)?

    init(didStart: XCTestExpectation? = nil, didStop: XCTestExpectation? = nil) {
        self.didStart = didStart
        self.didStop = didStop
        super.init()
    }

    var recordedStartCount: Int {
        lock.lock(); defer { lock.unlock() }
        return startCount
    }

    var recordedFinishedFlags: [Bool] {
        lock.lock(); defer { lock.unlock() }
        return finishedFlags
    }

    func animationDidStart(_ anim: CAAnimation) {
        lock.lock()
        startCount += 1
        lock.unlock()
        didStart?.fulfill()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        lock.lock()
        finishedFlags.append(flag)
        lock.unlock()
        onStop?(flag)
        didStop?.fulfill()
    }
}

/// NSLock-guarded append-only event log for asserting callback ordering.
private final class EventOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// Display-link target. The source-lowering pass turns #selector(...) into an
/// opaque Selector token and delivery happens via QuillSelectorDispatching,
/// so this is exactly the shape real lowered Signal/Telegram code presents.
private final class TickTarget: NSObject, QuillSelectorDispatching, @unchecked Sendable {
    private let lock = NSLock()
    private var ticks = 0

    let exp: XCTestExpectation
    let fulfillAtTick: Int

    init(expectation: XCTestExpectation, fulfillAtTick: Int = 3) {
        self.exp = expectation
        self.fulfillAtTick = fulfillAtTick
        super.init()
    }

    var tickCount: Int {
        lock.lock(); defer { lock.unlock() }
        return ticks
    }

    func quillPerform(_ selector: Selector, with sender: Any?) {
        lock.lock()
        ticks += 1
        let n = ticks
        lock.unlock()
        XCTAssertTrue(sender is CADisplayLink, "display link must pass itself as the sender")
        // Fulfill exactly once, at the requested tick, so the expectation's
        // over-fulfill assertion can never trip even if ticks keep arriving
        // until invalidate().
        if n == fulfillAtTick {
            exp.fulfill()
        }
    }
}

// MARK: - Tests

final class CAAnimationTimingTests: XCTestCase {

    // 1. Delegate start/stop fire asynchronously; default
    //    isRemovedOnCompletion (true) removes the animation afterwards.
    func testDelegateCompletionFiresAsynchronouslyAndAnimationIsRemoved() {
        let didStart = expectation(description: "animationDidStart delivered")
        let didStop = expectation(description: "animationDidStop(finished: true) delivered")
        let recorder = AnimationDelegateRecorder(didStart: didStart, didStop: didStop)

        let layer = CALayer()
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.duration = 0.05
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.delegate = recorder

        layer.add(anim, forKey: "fade")

        // Eventual delivery only — never assert how long it actually took.
        wait(for: [didStart, didStop], timeout: 5.0)

        XCTAssertEqual(recorder.recordedStartCount, 1)
        XCTAssertEqual(recorder.recordedFinishedFlags, [true],
                       "natural completion must report finished == true exactly once")

        // Checked only AFTER didStop resolved: by then the default
        // isRemovedOnCompletion == true must have removed the animation.
        let keys = layer.animationKeys() ?? []
        XCTAssertTrue(keys.isEmpty,
                      "isRemovedOnCompletion should have removed the animation; found \(keys)")
    }

    // 2. Removing an in-flight animation delivers didStop(finished: false)
    //    promptly — long before its nominal 60s duration.
    func testRemovalMidFlightDeliversDidStopNotFinished() {
        let didStop = expectation(description: "animationDidStop(finished: false) delivered")
        let recorder = AnimationDelegateRecorder(didStop: didStop)

        let layer = CALayer()
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.duration = 60.0 // would "finish" far beyond any test timeout
        anim.delegate = recorder

        layer.add(anim, forKey: "longFade")
        layer.removeAnimation(forKey: "longFade")

        wait(for: [didStop], timeout: 5.0)

        XCTAssertEqual(recorder.recordedFinishedFlags, [false],
                       "interrupted animation must report finished == false exactly once")
        let keys = layer.animationKeys() ?? []
        XCTAssertTrue(keys.isEmpty, "removed animation must not linger; found \(keys)")
    }

    // 3. isRemovedOnCompletion = false keeps the animation attached after it
    //    finishes (the Telegram-style "fillMode: .forwards" idiom).
    func testNotRemovedOnCompletionKeepsAnimationAttached() {
        let didStop = expectation(description: "animationDidStop(finished: true) delivered")
        let recorder = AnimationDelegateRecorder(didStop: didStop)

        let layer = CALayer()
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.duration = 0.05
        anim.isRemovedOnCompletion = false
        anim.delegate = recorder

        layer.add(anim, forKey: "sticky")

        wait(for: [didStop], timeout: 5.0)

        XCTAssertEqual(recorder.recordedFinishedFlags, [true])
        let kept = layer.animation(forKey: "sticky")
        XCTAssertNotNil(kept, "isRemovedOnCompletion = false must keep the animation attached")
        XCTAssertEqual((kept as? CABasicAnimation)?.keyPath, "opacity")
    }

    // 4. A transaction's completion block runs only after the animations
    //    added inside it have completed — and after their didStop callbacks.
    func testTransactionCompletionFiresAfterItsAnimationsFinish() {
        let order = EventOrderRecorder()
        let didStop = expectation(description: "animation didStop delivered")
        let txnDone = expectation(description: "transaction completion block delivered")

        let recorder = AnimationDelegateRecorder(didStop: didStop)
        recorder.onStop = { _ in order.append("didStop") }

        let layer = CALayer()

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            order.append("transactionCompletion")
            txnDone.fulfill()
        }

        let anim = CABasicAnimation(keyPath: "position")
        anim.duration = 0.05
        anim.delegate = recorder
        layer.add(anim, forKey: "move")

        CATransaction.commit()

        wait(for: [didStop, txnDone], timeout: 5.0)

        XCTAssertEqual(recorder.recordedFinishedFlags, [true])
        // Strict equality asserts both ordering AND exactly-once delivery.
        XCTAssertEqual(order.events, ["didStop", "transactionCompletion"],
                       "the animation's didStop must precede the transaction completion block")
    }

    // 5. A transaction with no animations still fires its completion block
    //    after commit.
    func testTransactionCompletionFiresWithoutAnimations() {
        let done = expectation(description: "empty transaction completion delivered")

        CATransaction.begin()
        CATransaction.setCompletionBlock { done.fulfill() }
        CATransaction.commit()

        wait(for: [done], timeout: 5.0)
    }

    // 6. Nested transactions scope setDisableActions: visible inside the
    //    inner transaction, restored when the inner one commits.
    func testNestedTransactionDisableActionsScoping() {
        CATransaction.begin()
        CATransaction.setDisableActions(false) // make the outer value explicit
        XCTAssertFalse(CATransaction.disableActions())

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        XCTAssertTrue(CATransaction.disableActions(),
                      "inner transaction must see its own setDisableActions(true)")
        CATransaction.commit()

        XCTAssertFalse(CATransaction.disableActions(),
                       "outer transaction's value must be restored after the inner commit")
        CATransaction.commit()
    }

    // 7. setCompletionBlock with NO explicit begin participates in the
    //    implicit transaction and still fires (when the run loop pumps,
    //    which wait(for:timeout:) guarantees).
    func testImplicitTransactionCompletionBlockFires() {
        let done = expectation(description: "implicit transaction completion delivered")

        CATransaction.setCompletionBlock { done.fulfill() }

        wait(for: [done], timeout: 5.0)
    }

    // 8. CADisplayLink actually ticks: the lowered Selector token is opaque,
    //    delivery is via QuillSelectorDispatching.quillPerform on the main
    //    queue, and timestamps advance.
    func testDisplayLinkTicksTargetViaQuillSelectorDispatching() {
        let threeTicks = expectation(description: "display link delivered three ticks")
        let target = TickTarget(expectation: threeTicks, fulfillAtTick: 3)

        let link = CADisplayLink(target: target, selector: Selector("tick"))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)

        // 3 ticks at 30fps is nominally ~0.1s; the generous timeout absorbs
        // starved-runner scheduling jitter. Never assert elapsed time.
        wait(for: [threeTicks], timeout: 10.0)

        XCTAssertGreaterThanOrEqual(target.tickCount, 3)
        // After ticking, the link must report a real timestamp and a target
        // timestamp strictly in its future. Read before invalidate(), on the
        // main thread, so nothing mutates concurrently.
        XCTAssertGreaterThan(link.timestamp, 0, "timestamp must be set once the link has ticked")
        XCTAssertGreaterThan(link.targetTimestamp, link.timestamp,
                             "targetTimestamp must be ahead of the last tick's timestamp")

        link.invalidate()
    }

    // 9. isPaused suppresses ticks; clearing it resumes them.
    func testDisplayLinkIsPausedSuppressesAndResumeDelivers() {
        // fulfillAtTick = 3 means: even if one tick slips through before the
        // pause takes effect (tolerated below), fulfillment still requires at
        // least two POST-unpause ticks — so an early stray tick can never
        // satisfy the resume expectation on its own.
        let resumed = expectation(description: "ticks delivered after unpause")
        let target = TickTarget(expectation: resumed, fulfillAtTick: 3)

        let link = CADisplayLink(target: target, selector: Selector("tick"))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        link.isPaused = true

        // Grace period WITHOUT sleeping: asyncAfter + expectation keeps the
        // run loop pumping, so a buggy unpaused link would tick repeatedly.
        let grace = expectation(description: "grace period elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { grace.fulfill() }
        wait(for: [grace], timeout: 5.0)

        XCTAssertLessThanOrEqual(target.tickCount, 1,
                                 "paused link must not tick (<= 1 tolerates one in-flight tick racing the pause)")

        link.isPaused = false
        wait(for: [resumed], timeout: 10.0)

        XCTAssertGreaterThanOrEqual(target.tickCount, 3, "ticks must resume after unpausing")
        link.invalidate()
    }
}
