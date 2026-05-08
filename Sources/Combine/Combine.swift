import Foundation

@_exported import OpenCombine
@_exported import OpenCombineDispatch
@_exported import OpenCombineFoundation

public extension AnyPublisher {
    init() {
        self.init(Empty<Output, Failure>(completeImmediately: false))
    }
}

public extension NotificationCenter {
    func publisher(
        for name: Notification.Name,
        object: AnyObject? = nil
    ) -> NotificationCenter.OCombine.Publisher {
        ocombine.publisher(for: name, object: object)
    }
}

public extension Publishers {
    struct Merge<A: Publisher, B: Publisher>: Publisher where A.Output == B.Output, A.Failure == B.Failure {
        public typealias Output = A.Output
        public typealias Failure = A.Failure

        private let first: A
        private let second: B

        public init(_ first: A, _ second: B) {
            self.first = first
            self.second = second
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
        where Downstream.Input == Output, Downstream.Failure == Failure {
            let subscription = QuillMergeSubscription(
                downstream: subscriber,
                first: first,
                second: second
            )
            subscriber.receive(subscription: subscription)
        }
    }
}

private final class QuillMergeSubscription<Downstream: Subscriber, A: Publisher, B: Publisher>: Subscription
where Downstream.Input == A.Output, Downstream.Failure == A.Failure, A.Output == B.Output, A.Failure == B.Failure {
    private enum InputSlot {
        case first
        case second
    }

    private let lock = NSLock()
    private var downstream: Downstream?
    private var first: A?
    private var second: B?
    private var firstSubscription: Subscription?
    private var secondSubscription: Subscription?
    private var demand: Subscribers.Demand = .none
    private var bufferedValues: [A.Output] = []
    private var started = false
    private var completedInputs = 0

    init(downstream: Downstream, first: A, second: B) {
        self.downstream = downstream
        self.first = first
        self.second = second
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand != .none else { return }

        let publishersAndSubscriptions = lock.withLock { () -> ((A, B)?, Subscription?, Subscription?, [A.Output], Downstream?, Subscribers.Completion<A.Failure>?) in
            guard downstream != nil else { return (nil, nil, nil, [], nil, nil) }
            self.demand += demand
            let values = drainBufferedValuesLocked()
            let completion = completionIfFinishedLocked()
            let downstream = self.downstream
            if completion != nil {
                self.downstream = nil
            }

            let publishers: (A, B)?
            if !started, let first, let second {
                started = true
                self.first = nil
                self.second = nil
                publishers = (first, second)
            } else {
                publishers = nil
            }

            return (publishers, firstSubscription, secondSubscription, values, downstream, completion)
        }

        deliver(publishersAndSubscriptions.3, to: publishersAndSubscriptions.4)
        if let downstream = publishersAndSubscriptions.4, let completion = publishersAndSubscriptions.5 {
            downstream.receive(completion: completion)
        }

        if let publishers = publishersAndSubscriptions.0 {
            publishers.0.subscribe(Inner(parent: self, slot: .first))
            publishers.1.subscribe(Inner(parent: self, slot: .second))
        } else {
            publishersAndSubscriptions.1?.request(demand)
            publishersAndSubscriptions.2?.request(demand)
        }
    }

    func cancel() {
        let subscriptions = lock.withLock { () -> (Subscription?, Subscription?) in
            let subscriptions = (firstSubscription, secondSubscription)
            downstream = nil
            first = nil
            second = nil
            firstSubscription = nil
            secondSubscription = nil
            bufferedValues.removeAll()
            return subscriptions
        }
        subscriptions.0?.cancel()
        subscriptions.1?.cancel()
    }

    private func receive(subscription: Subscription, slot: InputSlot) {
        let demandToRequest = lock.withLock { () -> Subscribers.Demand? in
            guard downstream != nil else { return nil }
            switch slot {
            case .first:
                firstSubscription = subscription
            case .second:
                secondSubscription = subscription
            }
            return demand
        }
        guard let demandToRequest else {
            subscription.cancel()
            return
        }
        if demandToRequest != .none {
            subscription.request(demandToRequest)
        }
    }

    private func receiveValue(_ value: A.Output) -> Subscribers.Demand {
        let delivery = lock.withLock { () -> (Downstream?, [A.Output], Subscribers.Completion<A.Failure>?) in
            guard downstream != nil else { return (nil, [], nil) }
            if demand == .none {
                bufferedValues.append(value)
                return (nil, [], nil)
            }
            decrementDemandLocked()
            return (downstream, [value], completionIfFinishedLocked())
        }

        let extraDemand = deliver(delivery.1, to: delivery.0)
        let followUp = lock.withLock { () -> (Downstream?, [A.Output], Subscribers.Completion<A.Failure>?) in
            if extraDemand != .none {
                demand += extraDemand
            }
            let values = drainBufferedValuesLocked()
            let downstream = self.downstream
            let completion = completionIfFinishedLocked()
            if completion != nil {
                self.downstream = nil
            }
            return (downstream, values, completion)
        }
        let moreDemand = deliver(followUp.1, to: followUp.0)
        if moreDemand != .none {
            lock.withLock {
                demand += moreDemand
            }
        }
        if let downstream = followUp.0, let completion = followUp.2 {
            downstream.receive(completion: completion)
        }
        return extraDemand
    }

    private func receiveCompletion(_ completion: Subscribers.Completion<A.Failure>, slot: InputSlot) {
        let downstreamToComplete = lock.withLock { () -> (Downstream?, Subscribers.Completion<A.Failure>?, Subscription?) in
            guard downstream != nil else { return (nil, nil, nil) }

            switch completion {
            case .failure:
                let downstream = self.downstream
                self.downstream = nil
                first = nil
                second = nil
                let otherSubscription: Subscription?
                switch slot {
                case .first:
                    otherSubscription = secondSubscription
                case .second:
                    otherSubscription = firstSubscription
                }
                firstSubscription = nil
                secondSubscription = nil
                bufferedValues.removeAll()
                return (downstream, completion, otherSubscription)
            case .finished:
                completedInputs += 1
                guard let completion = completionIfFinishedLocked() else { return (nil, nil, nil) }
                let downstream = self.downstream
                self.downstream = nil
                first = nil
                second = nil
                firstSubscription = nil
                secondSubscription = nil
                return (downstream, completion, nil)
            }
        }
        downstreamToComplete.2?.cancel()
        if let downstream = downstreamToComplete.0, let completion = downstreamToComplete.1 {
            downstream.receive(completion: completion)
        }
    }

    private func drainBufferedValuesLocked() -> [A.Output] {
        guard demand != .none, !bufferedValues.isEmpty else { return [] }
        var values: [A.Output] = []
        while demand != .none, !bufferedValues.isEmpty {
            values.append(bufferedValues.removeFirst())
            decrementDemandLocked()
        }
        return values
    }

    private func decrementDemandLocked() {
        if demand != .unlimited {
            demand -= 1
        }
    }

    private func completionIfFinishedLocked() -> Subscribers.Completion<A.Failure>? {
        guard completedInputs == 2, bufferedValues.isEmpty else { return nil }
        return .finished
    }

    @discardableResult
    private func deliver(_ values: [A.Output], to downstream: Downstream?) -> Subscribers.Demand {
        guard let downstream else { return .none }
        var extraDemand: Subscribers.Demand = .none
        for value in values {
            extraDemand += downstream.receive(value)
        }
        return extraDemand
    }

    private final class Inner: Subscriber {
        typealias Input = A.Output
        typealias Failure = A.Failure

        private weak var parent: QuillMergeSubscription?
        private let slot: InputSlot

        init(parent: QuillMergeSubscription, slot: InputSlot) {
            self.parent = parent
            self.slot = slot
        }

        func receive(subscription: Subscription) {
            parent?.receive(subscription: subscription, slot: slot)
        }

        func receive(_ input: A.Output) -> Subscribers.Demand {
            parent?.receiveValue(input) ?? .none
        }

        func receive(completion: Subscribers.Completion<A.Failure>) {
            parent?.receiveCompletion(completion, slot: slot)
        }
    }
}
