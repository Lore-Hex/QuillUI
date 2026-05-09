#if os(Linux)
import Foundation

@_exported import OpenCombine
@_exported import OpenCombineDispatch
@_exported import OpenCombineFoundation

public typealias _CombineScheduler = OpenCombine.Scheduler

public extension AnyPublisher where Failure == Never {
    init() {
        self.init(Empty<Output, Never>())
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
