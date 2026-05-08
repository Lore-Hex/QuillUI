public struct AsyncTimerSequence<C: Clock>: AsyncSequence {
    public typealias Element = C.Instant

    private let interval: C.Duration
    private let clock: C

    public init(interval: C.Duration, clock: C) {
        self.interval = interval
        self.clock = clock
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(interval: interval, clock: clock)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let interval: C.Duration
        private let clock: C
        private var isCancelled = false

        init(interval: C.Duration, clock: C) {
            self.interval = interval
            self.clock = clock
        }

        public mutating func next() async -> C.Instant? {
            guard !isCancelled else { return nil }
            do {
                try await clock.sleep(for: interval)
                return clock.now
            } catch {
                isCancelled = true
                return nil
            }
        }
    }
}
