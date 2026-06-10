//
// SignalServiceKit Foundation-extension port for QuillOS (Track B).
//
// Darwin Foundation gives NotificationCenter an async sequence accessor,
//   func notifications(named:object:) -> NotificationCenter.Notifications
// (an AsyncSequence of Notification), used by `for await _ in ...` loops.
// swift-corelibs-foundation has no such member, so NetworkManager (the
// reachability observer) fails to compile. Faithful drop-in: same method shape
// returning an AsyncStream<Notification>, registering a real observer and
// tearing it down on stream termination. AsyncStream conforms to AsyncSequence,
// so `for await` works and chained operators are also satisfied.
//
#if os(Linux)
import Foundation

public extension NotificationCenter {
    func notifications(named name: Notification.Name, object: AnyObject? = nil) -> AsyncStream<Notification> {
        AsyncStream { continuation in
            let token = self.addObserver(forName: name, object: object, queue: nil) { note in
                continuation.yield(note)
            }
            continuation.onTermination = { @Sendable _ in
                self.removeObserver(token)
            }
        }
    }
}
#endif
