#if os(Linux)
import Foundation

@_exported import OpenCombine
@_exported import OpenCombineDispatch
@_exported import OpenCombineFoundation

public typealias _CombineScheduler = OpenCombine.Scheduler

public extension NotificationCenter {
    typealias Publisher = OCombine.Publisher

    func publisher(
        for name: Notification.Name,
        object: AnyObject? = nil
    ) -> OCombine.Publisher {
        ocombine.publisher(for: name, object: object)
    }
}

public extension AnyPublisher where Failure == Never {
    init() {
        self.init(Empty<Output, Never>())
    }
}

// Combine's KVO publisher: `object.publisher(for: \.keyPath)`. On Apple
// platforms this is `NSObject.KeyValueObservingPublisher`, backed by real KVO.
// On Linux there is no Objective-C runtime, so this is inert in the same way as
// QuillFoundation's `observe(_:)` clone: it emits the keyPath's *current* value
// once (honoring Combine's default `.initial` semantics so a leading `.sink`
// still sees a value) and then never fires again. SignalUI's
// StackSheetViewController subscribes to `\.bounds` this way; the downstream
// `.removeDuplicates().sink {}` pipeline type-checks and runs without crashing.
//
// The `options` parameter is a local OptionSet rather than Foundation's
// `NSKeyValueObservingOptions` (defined in QuillFoundation, which the low-level
// Combine shim deliberately does not depend on). It mirrors the option names so
// call sites that pass `.initial` / `.new` keep compiling.
public struct _KVOPublisherOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let new = _KVOPublisherOptions(rawValue: 0x01)
    public static let old = _KVOPublisherOptions(rawValue: 0x02)
    public static let initial = _KVOPublisherOptions(rawValue: 0x04)
    public static let prior = _KVOPublisherOptions(rawValue: 0x08)
}

// The KVO publisher must carry a keypath rooted in the *receiver's* type so a
// bare `\.bounds` literal can infer its root from the call (`view.publisher(for:
// \.bounds)`). A plain `NSObject` extension method generic over `Root` cannot do
// this — Swift won't bind a free `Root` from a keypath literal, hence "cannot
// infer key path type from context." A protocol extension, however, MAY use
// `Self` in parameter position, which pins the keypath root to the concrete
// receiver and makes inference succeed.
public protocol _KVOPublishing: NSObject {}
extension NSObject: _KVOPublishing {}

public extension _KVOPublishing {
    // `KeyPath<Self, Value>` pins the root to the receiver's static type, so the
    // `\.bounds` literal infers its root. Inert on Linux (no KVO) beyond emitting
    // the keypath's current value once when `.initial` is requested.
    func publisher<Value>(
        for keyPath: KeyPath<Self, Value>,
        options: _KVOPublisherOptions = [.initial, .new]
    ) -> AnyPublisher<Value, Never> {
        if options.contains(.initial) {
            return Just(self[keyPath: keyPath]).eraseToAnyPublisher()
        }
        return Empty<Value, Never>(completeImmediately: false).eraseToAnyPublisher()
    }
}

public extension Publishers {
    struct Merge<UpstreamA: Publisher, UpstreamB: Publisher>: Publisher
        where UpstreamA.Output == UpstreamB.Output, UpstreamA.Failure == UpstreamB.Failure
    {
        public typealias Output = UpstreamA.Output
        public typealias Failure = UpstreamA.Failure

        private let first: UpstreamA
        private let second: UpstreamB

        public init(_ first: UpstreamA, _ second: UpstreamB) {
            self.first = first
            self.second = second
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Downstream.Input == Output, Downstream.Failure == Failure
        {
            let inner = Inner(downstream: subscriber)
            subscriber.receive(subscription: inner)
            first.receive(subscriber: inner)
            second.receive(subscriber: inner)
        }

        private final class Inner<Downstream: Subscriber>: Subscriber, Subscription
            where Downstream.Input == Output, Downstream.Failure == Failure
        {
            typealias Input = Output

            private let lock = NSRecursiveLock()
            private var downstream: Downstream?
            private var subscriptions: [any Subscription] = []
            private var demand: Subscribers.Demand = .none
            private var buffer: [Output] = []
            private var finishedInputs = 0

            let combineIdentifier = CombineIdentifier()

            init(downstream: Downstream) {
                self.downstream = downstream
            }

            func receive(subscription: any Subscription) {
                lock.withLock {
                    subscriptions.append(subscription)
                }
                subscription.request(.unlimited)
            }

            func receive(_ input: Output) -> Subscribers.Demand {
                lock.withLock {
                    buffer.append(input)
                    drain()
                }
                return .none
            }

            func receive(completion: Subscribers.Completion<Failure>) {
                lock.withLock {
                    switch completion {
                    case .finished:
                        finishedInputs += 1
                        drain()
                    case .failure:
                        complete(completion)
                    }
                }
            }

            func request(_ newDemand: Subscribers.Demand) {
                guard newDemand > .none else { return }
                lock.withLock {
                    demand += newDemand
                    drain()
                }
            }

            func cancel() {
                let currentSubscriptions = lock.withLock {
                    let subscriptions = self.subscriptions
                    self.subscriptions.removeAll()
                    self.buffer.removeAll()
                    self.downstream = nil
                    return subscriptions
                }
                currentSubscriptions.forEach { $0.cancel() }
            }

            private func drain() {
                while demand > .none, buffer.isEmpty == false, let downstream {
                    let value = buffer.removeFirst()
                    if demand != .unlimited {
                        demand -= 1
                    }
                    demand += downstream.receive(value)
                }

                if finishedInputs >= 2, buffer.isEmpty {
                    complete(.finished)
                }
            }

            private func complete(_ completion: Subscribers.Completion<Failure>) {
                guard let downstream else { return }
                self.downstream = nil
                buffer.removeAll()
                subscriptions.removeAll()
                downstream.receive(completion: completion)
            }
        }
    }
}
#endif
