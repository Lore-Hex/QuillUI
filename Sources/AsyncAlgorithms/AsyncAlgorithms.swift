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

public extension ContinuousClock {
    static var continuous: ContinuousClock { ContinuousClock() }
}

public extension AsyncTimerSequence {
    static func repeating(every interval: C.Duration, clock: C) -> AsyncTimerSequence<C> {
        AsyncTimerSequence(interval: interval, clock: clock)
    }
}

public struct AsyncChunkedBySignalSequence<Base: AsyncSequence, Signal: AsyncSequence>: AsyncSequence {
    public typealias Element = [Base.Element]

    private let base: Base
    private let signal: Signal

    public init(_ base: Base, signal: Signal) {
        self.base = base
        self.signal = signal
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), signal: signal.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: Base.AsyncIterator
        private var signal: Signal.AsyncIterator

        init(base: Base.AsyncIterator, signal: Signal.AsyncIterator) {
            self.base = base
            self.signal = signal
        }

        public mutating func next() async -> [Base.Element]? {
            var chunk: [Base.Element] = []
            if let first = try? await base.next() {
                chunk.append(first)
            }
            _ = try? await signal.next()
            return chunk.isEmpty ? nil : chunk
        }
    }
}

public struct AsyncDebouncedSequence<Base: AsyncSequence, C: Clock>: AsyncSequence {
    public typealias Element = Base.Element

    private let base: Base
    private let interval: C.Duration
    private let clock: C

    public init(_ base: Base, interval: C.Duration, clock: C) {
        self.base = base
        self.interval = interval
        self.clock = clock
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), interval: interval, clock: clock)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: Base.AsyncIterator
        private let interval: C.Duration
        private let clock: C

        init(base: Base.AsyncIterator, interval: C.Duration, clock: C) {
            self.base = base
            self.interval = interval
            self.clock = clock
        }

        public mutating func next() async -> Base.Element? {
            guard let value = try? await base.next() else { return nil }
            try? await clock.sleep(for: interval)
            return value
        }
    }
}

public extension AsyncSequence {
    func chunked<C: Clock>(by timer: AsyncTimerSequence<C>) -> AsyncChunkedBySignalSequence<Self, AsyncTimerSequence<C>> {
        AsyncChunkedBySignalSequence(self, signal: timer)
    }

    func chunked(by timer: AsyncTimerSequence<ContinuousClock>) -> AsyncChunkedBySignalSequence<Self, AsyncTimerSequence<ContinuousClock>> {
        AsyncChunkedBySignalSequence(self, signal: timer)
    }

    func debounce<C: Clock>(for interval: C.Duration, clock: C) -> AsyncDebouncedSequence<Self, C> {
        AsyncDebouncedSequence(self, interval: interval, clock: clock)
    }

    func debounce(for interval: Duration) -> AsyncDebouncedSequence<Self, ContinuousClock> {
        AsyncDebouncedSequence(self, interval: interval, clock: .continuous)
    }
}
