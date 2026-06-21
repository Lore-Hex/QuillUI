import Foundation
import QuillFoundation

@MainActor public final class CoalescingQueue {
    public static let standard = CoalescingQueue(name: "Standard", interval: 0.05, maxInterval: 0.1)

    public let name: String
    public var isPaused = false

    private let interval: TimeInterval
    private let maxInterval: TimeInterval
    private var lastCallTime = Date.distantFuture
    private var pendingWork = [@MainActor @Sendable () -> Void]()
    private var timerTask: Task<Void, Never>?

    nonisolated public init(name: String, interval: TimeInterval = 0.05, maxInterval: TimeInterval = 2.0) {
        self.name = name
        self.interval = interval
        self.maxInterval = maxInterval
    }

    public func add(_ work: @escaping @MainActor @Sendable () -> Void) {
        pendingWork.append(work)
        restartTimer()

        if Date().timeIntervalSince(lastCallTime) > maxInterval {
            performCallsImmediately()
        }
    }

    public func add(_ target: AnyObject, _ selector: Selector) {
        pendingWork.append { @MainActor in
            (target as? QuillSelectorDispatching)?.quillPerform(selector, with: nil)
        }
        restartTimer()

        if Date().timeIntervalSince(lastCallTime) > maxInterval {
            performCallsImmediately()
        }
    }

    public func performCallsImmediately() {
        guard !isPaused else { return }

        let work = pendingWork
        pendingWork.removeAll()
        lastCallTime = Date()

        for block in work {
            block()
        }
    }

    private func restartTimer() {
        timerTask?.cancel()

        let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
        timerTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            self?.performCallsImmediately()
        }
    }
}
