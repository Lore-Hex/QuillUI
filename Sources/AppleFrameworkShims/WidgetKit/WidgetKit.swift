import Foundation

public final class WidgetCenter: @unchecked Sendable {
    public static let shared = WidgetCenter()

    private let lock = NSLock()
    private var reloadedTimelineKinds: [String] = []
    private var allTimelineReloadCount = 0

    private init() {}

    public func reloadTimelines(ofKind kind: String) {
        lock.lock()
        reloadedTimelineKinds.append(kind)
        lock.unlock()
    }

    public func reloadAllTimelines() {
        lock.lock()
        allTimelineReloadCount += 1
        lock.unlock()
    }

    public var quillReloadedTimelineKinds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return reloadedTimelineKinds
    }

    public var quillAllTimelineReloadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return allTimelineReloadCount
    }

    public func quillResetReloadTracking() {
        lock.lock()
        reloadedTimelineKinds.removeAll()
        allTimelineReloadCount = 0
        lock.unlock()
    }
}
