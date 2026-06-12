import Foundation

public typealias VoidBlock = @Sendable () -> Void
public typealias VoidCompletionBlock = VoidBlock

private final class QuillLockedState<State>: @unchecked Sendable {
    private var state: State
    private let lock = NSLock()

    init(_ state: State) {
        self.state = state
    }

    func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}

@MainActor open class MainThreadOperation: Hashable, @unchecked Sendable {
    public let id: Int
    private static var incrementingID = 0

    private struct State: Sendable {
        var isCanceled = false
    }

    private let state = QuillLockedState(State())

    nonisolated public var isCanceled: Bool {
        get { state.withLock { $0.isCanceled } }
        set { state.withLock { $0.isCanceled = newValue } }
    }

    public let name: String?

    public typealias MainThreadOperationCompletionBlock = @MainActor (MainThreadOperation) -> Void
    public var completionBlock: MainThreadOperationCompletionBlock?

    public weak var operationQueue: MainThreadOperationQueue?

    var dependencies = Set<MainThreadOperation>()

    public init(name: String? = nil, completionBlock: MainThreadOperationCompletionBlock? = nil) {
        self.id = Self.incrementingID
        Self.incrementingID += 1
        self.name = name
        self.completionBlock = completionBlock
    }

    open func run() {
        preconditionFailure("MainThreadOperation.run must be overridden.")
    }

    public func cancel() {
        isCanceled = true
        dependencies.removeAll()
        Task { @MainActor in
            didComplete()
        }
    }

    public func addDependency(_ parentOperation: MainThreadOperation) {
        dependencies.insert(parentOperation)
    }

    func removeDependency(_ parentOperation: MainThreadOperation) {
        dependencies.remove(parentOperation)
    }

    func hasDependency(_ parentOperation: MainThreadOperation) -> Bool {
        dependencies.contains(parentOperation)
    }

    nonisolated public func didComplete() {
        Task { @MainActor in
            operationQueue?.operationDidComplete(self)
        }
    }

    open func noteDidComplete() {}

    func callCompletionBlock() {
        completionBlock?(self)
        completionBlock = nil
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated public static func ==(lhs: MainThreadOperation, rhs: MainThreadOperation) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor public final class MainThreadBlockOperation: MainThreadOperation, @unchecked Sendable {
    private let block: VoidBlock

    public init(name: String? = nil, block: @escaping VoidBlock) {
        self.block = block
        super.init(name: name, completionBlock: nil)
    }

    public override func run() {
        block()
        didComplete()
    }
}

@MainActor public final class MainThreadOperationQueue: ProgressInfoReporter {
    public static let shared = MainThreadOperationQueue()

    private var pendingOperations = [MainThreadOperation]()
    private var currentOperation: MainThreadOperation?
    private var completedOrCanceledOperationIDs = Set<Int>()
    private var isSuspended = false
    private var hasPendingRunScheduled = false

    public var isTrackingProgress = false {
        didSet {
            if isTrackingProgress != oldValue {
                completedOrCanceledOperationIDs = Set<Int>()
            }
        }
    }

    public var progressInfo = ProgressInfo() {
        didSet {
            if isTrackingProgress && progressInfo != oldValue {
                postProgressInfoDidChangeNotification()
            }
        }
    }

    public var pendingOperationsCount: Int {
        pendingOperations.filter { !$0.isCanceled }.count
    }

    public init() {}

    public func add(_ operation: MainThreadOperation) {
        operation.operationQueue = self
        if pendingOperations.contains(operation) {
            assertionFailure("Tried to add operation to MainThreadOperationQueue that had already been added.")
            return
        }
        pendingOperations.append(operation)
        runNextOperationIfNeeded()
    }

    public func add(_ operations: [MainThreadOperation]) {
        operations.forEach(add)
    }

    public func cancelAll() {
        var operationsToCancel = Set(pendingOperations)
        if let currentOperation {
            operationsToCancel.insert(currentOperation)
        }
        cancel(Array(operationsToCancel))
    }

    public func cancel(_ operations: [MainThreadOperation]) {
        for operation in operations {
            operation.cancel()
            if isTrackingProgress {
                completedOrCanceledOperationIDs.insert(operation.id)
            }
        }
        runNextOperationIfNeeded()
    }

    public func cancel(named name: String) {
        guard let operationsToCancel = pendingAndCurrentOperations(named: name) else {
            return
        }
        cancel(operationsToCancel)
    }

    public func suspend() {
        isSuspended = true
    }

    public func resume() {
        isSuspended = false
        runNextOperationIfNeeded()
    }

    public func operationDidComplete(_ operation: MainThreadOperation) {
        operation.callCompletionBlock()
        operation.noteDidComplete()

        if isTrackingProgress {
            completedOrCanceledOperationIDs.insert(operation.id)
        }

        pendingOperations.removeAll { $0 == operation }
        if currentOperation == operation {
            currentOperation = nil
        }

        let operationWasCanceled = operation.isCanceled
        let dependentOperations = pendingOperations.filter { $0.hasDependency(operation) }
        for dependentOperation in dependentOperations {
            dependentOperation.removeDependency(operation)
            if operationWasCanceled {
                dependentOperation.cancel()
            }
        }

        removeCanceledOperations()
        runNextOperationIfNeeded()
    }
}

private extension MainThreadOperationQueue {
    func removeCanceledOperations() {
        pendingOperations.removeAll { $0.isCanceled }
        updateProgressInfo()
    }

    func pendingAndCurrentOperations(named name: String) -> [MainThreadOperation]? {
        var operations = pendingOperations.filter { $0.name == name }
        if let currentOperation, currentOperation.name == name {
            operations.append(currentOperation)
        }
        return operations.isEmpty ? nil : operations
    }

    func runNextOperationIfNeeded() {
        updateProgressInfo()

        guard !isSuspended && !hasPendingRunScheduled else {
            return
        }
        hasPendingRunScheduled = true

        Task { @MainActor in
            hasPendingRunScheduled = false
            guard !isSuspended && currentOperation == nil else {
                return
            }
            guard let operation = popNextAvailableOperation() else {
                return
            }
            currentOperation = operation
            updateProgressInfo()
            operation.run()
        }
    }

    func popNextAvailableOperation() -> MainThreadOperation? {
        guard let index = pendingOperations.firstIndex(where: operationIsAvailable) else {
            return nil
        }
        return pendingOperations.remove(at: index)
    }

    func operationIsAvailable(_ operation: MainThreadOperation) -> Bool {
        !operation.isCanceled && operation.dependencies.isEmpty
    }

    func updateProgressInfo() {
        guard isTrackingProgress else {
            return
        }

        var pendingOperationIDs = Set(pendingOperations.map(\.id))
        if let currentOperationID = currentOperation?.id {
            pendingOperationIDs.insert(currentOperationID)
        }
        pendingOperationIDs.subtract(completedOrCanceledOperationIDs)

        let numberCompleted = completedOrCanceledOperationIDs.count
        let numberRemaining = pendingOperationIDs.count
        progressInfo = ProgressInfo(
            numberOfTasks: numberCompleted + numberRemaining,
            numberCompleted: numberCompleted,
            numberRemaining: numberRemaining
        )
    }
}
