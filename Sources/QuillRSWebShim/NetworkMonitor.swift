import Foundation

public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    private let lock = NSLock()
    private var connected = true
    private var expensive = false
    private var constrained = false

    private init() {}

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    public var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expensive
    }

    public var isConstrained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return constrained
    }

    @MainActor public func start() {}

    public func configure(isConnected: Bool, isExpensive: Bool = false, isConstrained: Bool = false) {
        lock.lock()
        connected = isConnected
        expensive = isExpensive
        constrained = isConstrained
        lock.unlock()
    }
}
