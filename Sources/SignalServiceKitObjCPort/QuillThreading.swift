//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Concurrency/Threading.{h,m} C helpers. The `.m` is not compiled by SwiftPM on
// Linux, and there is no bridging header, so these globals (which SSK Swift sees
// via the umbrella on Apple) are undefined. They are used only by
// `DispatchQueue.asyncIfNecessary` (PromiseKit/DispatchQueue+Promise.swift) — a
// "run synchronously if already on this queue and the stack isn't too deep,
// otherwise dispatch async" fast path:
//
//   BOOL   DispatchQueueIsCurrentQueue(dispatch_queue_t queue)
//   double _CurrentStackUsage(void)
//
// Inert on Linux: `DispatchQueueIsCurrentQueue` returns false, so
// `asyncIfNecessary` always takes the `async { work() }` branch. That is
// contract-safe (the API only promises "async if necessary"; the work still runs
// on the target queue) and short-circuits `_CurrentStackUsage` (the `&&`-style
// comma never evaluates it). A faithful current-queue check would require the
// queue to carry a `dispatch_queue_set_specific` key, which SSK's Swift side does
// not set up; revisit if a real on-queue fast path is needed.
//
import Foundation

public func DispatchQueueIsCurrentQueue(_ queue: DispatchQueue) -> Bool { false }

public func _CurrentStackUsage() -> Double { 0.0 }
