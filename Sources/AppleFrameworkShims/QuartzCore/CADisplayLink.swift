//===----------------------------------------------------------------------===//
//
//  CADisplayLink.swift
//  QuartzCore shim — QuillUI Apple-framework reimplementation for Linux
//
//  A FUNCTIONAL CADisplayLink for QuillOS (Debian/Ubuntu, Swift 6.2,
//  swift-corelibs-foundation).
//
//  What this provides:
//    - The Apple CADisplayLink API surface (init(target:selector:),
//      add(to:forMode:), remove(from:forMode:), invalidate(), isPaused,
//      preferredFramesPerSecond, timestamp, duration, targetTimestamp).
//    - A link that genuinely TICKS: a DispatchSourceTimer on
//      DispatchQueue.main fires at the preferred frame rate and dispatches
//      back into real app code via QuillSelectorDispatching.quillPerform.
//      The source-lowering pass rewrites #selector(...) call sites into
//      opaque Selector("name") tokens and synthesizes switch-based
//      quillPerform conformances on the classes that used them, so the
//      callback reaches the original target method without any
//      Objective-C runtime.
//
//  Honest Linux semantics:
//    - There is no real display, vsync, or compositor behind this yet
//      (pixel compositing arrives later via QuillPaint). This is a TIMING
//      object only: it provides a steady main-queue heartbeat with
//      Apple-shaped timestamps, which is exactly what display-link-driven
//      animators (Signal-iOS, Telegram-iOS-style code) need to advance
//      their models.
//    - preferredFramesPerSecond == 0 means "native cadence"; with no real
//      display to query, the shim assumes 60 Hz.
//    - The runloop/mode parameters of add/remove are accepted for API
//      compatibility but the link always ticks on DispatchQueue.main (see
//      add(to:forMode:) for why).
//
//===----------------------------------------------------------------------===//

import CoreFoundation
import Dispatch
import Foundation
import QuillFoundation

/// The frame-rate range type used by `preferredFrameRateRange` (the modern,
/// ProMotion-era replacement for `preferredFramesPerSecond`).
public struct CAFrameRateRange: Equatable, Sendable {
    public var minimum: Float
    public var maximum: Float
    public var preferred: Float

    public init(minimum: Float, maximum: Float, preferred: Float = 0) {
        self.minimum = minimum
        self.maximum = maximum
        self.preferred = preferred
    }

    /// Apple's "let the system decide" sentinel.
    public static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
}

/// A timer object bound (conceptually) to the display refresh, allowing an
/// application to synchronize its drawing or animation model updates.
///
/// On QuillOS there is no display refresh to bind to yet, so the link is a
/// fixed-rate main-queue timer with Apple-compatible timing fields.
open class CADisplayLink: NSObject {

    // MARK: - Public state

    /// When `true`, the link stays scheduled but the per-frame callback is
    /// suppressed. Matches Apple semantics: pausing does not tear down the
    /// underlying timing source; un-pausing resumes callbacks on the next
    /// tick. Lock-guarded because fire() reads it on the main queue while
    /// callers may toggle it from elsewhere.
    public var isPaused: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isPaused
        }
        set {
            lock.lock()
            _isPaused = newValue
            lock.unlock()
        }
    }
    private var _isPaused: Bool = false

    /// The preferred callback rate, in frames per second. `0` (the default)
    /// means the native display cadence — assumed to be 60 Hz on this shim,
    /// since there is no real display to query. Changing this while the link
    /// is scheduled re-arms the timer at the new interval.
    public var preferredFramesPerSecond: Int = 0 {
        didSet { rearmIfScheduled() }
    }

    /// Modern frame-rate hint. When set (preferred, else maximum, nonzero)
    /// it wins over `preferredFramesPerSecond` for the tick cadence.
    public var preferredFrameRateRange: CAFrameRateRange = .default {
        didSet { rearmIfScheduled() }
    }

    /// The time of the most recent callback, in the `CACurrentMediaTime()`
    /// timebase. Read-only, as on Apple platforms.
    public private(set) var timestamp: CFTimeInterval = 0

    /// The interval between callbacks at the current preferred rate.
    public private(set) var duration: CFTimeInterval = 0

    /// The expected time of the next callback.
    public private(set) var targetTimestamp: CFTimeInterval = 0

    // MARK: - Private state

    /// Guards `timer`, `invalidated`, and `target`. The normal lifecycle
    /// (add/remove/invalidate/fire) is assumed to happen on the main queue,
    /// but `deinit` can run on any thread, so the timer handle and the
    /// invalidation flag are lock-protected.
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var invalidated = false

    /// The callback target. Apple's CADisplayLink famously RETAINS its
    /// target (which is why UIKit code conventionally interposes a weak
    /// proxy). We reproduce that: the target is held strongly from init
    /// until `invalidate()` (or deinit). `remove(from:forMode:)` does NOT
    /// release it, matching Apple.
    private var target: Any?

    /// The resolved selector-token name, extracted once at init.
    private let selectorName: String

    // MARK: - Init / deinit

    /// Creates a display link.
    ///
    /// `selector` is typed `Any` because two different — but structurally
    /// identical — opaque selector-token types reach this initializer:
    /// `QuillFoundation.Selector`, and a same-shape `Selector` struct that
    /// SignalServiceKit's port shims define in their own module. The first
    /// is matched by a direct cast; the second is read out reflectively via
    /// `Mirror` (a `String` child labeled "name").
    ///
    /// The target is retained until `invalidate()`, exactly as on Apple
    /// platforms.
    public init(target: Any, selector: Any) {
        self.target = target
        self.selectorName = CADisplayLink.resolveSelectorName(selector)
        super.init()
    }

    deinit {
        // Tear the timer down if the link is deallocated without an explicit
        // invalidate(). deinit may run off the main queue, hence the lock.
        // The source is always resumed immediately after creation, so it is
        // never deallocated in a suspended state (which Dispatch forbids).
        lock.lock()
        timer?.cancel()
        timer = nil
        invalidated = true
        lock.unlock()
    }

    // MARK: - Scheduling

    /// Schedules the link to begin firing.
    ///
    /// Simplification (documented): the `runloop`/`mode` parameters are
    /// accepted for API compatibility but otherwise ignored — the link
    /// always ticks via a `DispatchSourceTimer` on `DispatchQueue.main`,
    /// NOT a RunLoop `Timer`. Rationale: swift-corelibs-foundation
    /// integrates the main queue with the main RunLoop, and XCTest's
    /// `waitForExpectations` drains the main queue, so a main-queue timer
    /// is both testable and equivalent in practice. GTK main-loop
    /// integration is a later concern.
    ///
    /// Calling this more than once (Apple allows registering in multiple
    /// runloop modes) is a no-op after the first call: one timer drives the
    /// link.
    public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidated, timer == nil else { return }

        let source = DispatchSource.makeTimerSource(flags: [], queue: .main)
        let interval = currentInterval()
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(2)
        )
        source.setEventHandler { [weak self] in
            self?.fire()
        }
        source.resume()
        timer = source
    }

    /// Unschedules the link. The target stays retained — only
    /// `invalidate()` releases it, matching Apple — and the link may be
    /// re-scheduled later with `add(to:forMode:)`.
    public func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
    }

    /// Permanently stops the link, releases the retained target, and makes
    /// further callbacks impossible (any tick already enqueued on the main
    /// queue sees the invalidated flag and returns without dispatching).
    /// Safe to call repeatedly.
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
        invalidated = true
        target = nil
    }

    // MARK: - Ticking

    /// One tick. Always runs on DispatchQueue.main (the timer's queue).
    private func fire() {
        lock.lock()
        if invalidated || _isPaused {
            lock.unlock()
            return
        }
        let interval = currentInterval()
        let now = CACurrentMediaTime()
        timestamp = now
        duration = interval
        targetTimestamp = now + interval
        let target = self.target
        lock.unlock()

        // The source-lowering pass generates QuillSelectorDispatching
        // conformances (a switch over selector names) on every class that
        // used #selector, so this call genuinely re-enters real,
        // unmodified app code (e.g. Signal's display-link-driven
        // animators).
        (target as? QuillSelectorDispatching)?
            .quillPerform(Selector(selectorName), with: self)
    }

    /// Re-arms a live timer after `preferredFramesPerSecond` changes.
    /// Re-calling `schedule` on an active dispatch timer source atomically
    /// replaces its cadence.
    private func rearmIfScheduled() {
        lock.lock()
        defer { lock.unlock() }
        guard let timer = timer, !invalidated else { return }
        let interval = currentInterval()
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(2)
        )
    }

    /// The current tick interval: 1/fps. `preferredFrameRateRange`
    /// (preferred, else maximum) wins when nonzero; then
    /// `preferredFramesPerSecond`; 0 means the assumed native 60 Hz.
    private func currentInterval() -> CFTimeInterval {
        let rangeFPS = preferredFrameRateRange.preferred > 0
            ? Int(preferredFrameRateRange.preferred)
            : Int(preferredFrameRateRange.maximum)
        let fps: Int
        if rangeFPS > 0 {
            fps = rangeFPS
        } else if preferredFramesPerSecond > 0 {
            fps = preferredFramesPerSecond
        } else {
            fps = 60
        }
        return 1.0 / Double(max(1, fps))
    }

    // MARK: - Selector token resolution

    /// Extracts the selector name from either QuillFoundation.Selector
    /// (direct cast) or any structurally identical foreign token type — a
    /// struct with a `String` property named `name` — via reflection.
    private static func resolveSelectorName(_ selector: Any) -> String {
        if let sel = selector as? Selector {
            return sel.name
        }
        let mirror = Mirror(reflecting: selector)
        for child in mirror.children where child.label == "name" {
            if let name = child.value as? String {
                return name
            }
        }
        // Unrecognized token shape: the link still ticks (timestamps
        // update), but quillPerform will be invoked with an empty selector,
        // which generated conformances treat as a no-op.
        return ""
    }
}
