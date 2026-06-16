import XCTest
@testable import SwiftOpenUI

private final class RecordingViewHost: AnyViewHost {
    var rebuildCount = 0

    func scheduleRebuild() { rebuildCount += 1 }
    func suppressNextFocusRestore() {}
}

final class StateTests: XCTestCase {

    // MARK: - @State

    func testStateInitialValue() {
        let state = State<Int>(wrappedValue: 42)
        XCTAssertEqual(state.wrappedValue, 42)
    }

    func testStateSetValue() {
        let state = State<Int>(wrappedValue: 0)
        state.wrappedValue = 99
        XCTAssertEqual(state.wrappedValue, 99)
    }

    func testStateProjectedValueReturnsBinding() {
        let state = State<String>(wrappedValue: "hello")
        let binding = state.projectedValue
        XCTAssertEqual(binding.wrappedValue, "hello")
        binding.wrappedValue = "world"
        XCTAssertEqual(state.wrappedValue, "world")
    }

    func testStateStorageSharedAcrossCopies() {
        let state = State<Int>(wrappedValue: 10)
        let copy = state
        state.wrappedValue = 20
        XCTAssertEqual(copy.wrappedValue, 20, "Copies should share storage")
    }

    // MARK: - @Binding

    func testBindingGetSet() {
        var value = 5
        let binding = Binding<Int>(get: { value }, set: { value = $0 })
        XCTAssertEqual(binding.wrappedValue, 5)
        binding.wrappedValue = 10
        XCTAssertEqual(value, 10)
    }

    func testBindingConstant() {
        let binding = Binding<String>.constant("fixed")
        XCTAssertEqual(binding.wrappedValue, "fixed")
        binding.wrappedValue = "changed"
        XCTAssertEqual(binding.wrappedValue, "fixed", "Constant binding should not change")
    }

    func testBindingProjectedValue() {
        let binding = Binding<Int>(get: { 1 }, set: { _ in })
        let projected = binding.projectedValue
        XCTAssertEqual(projected.wrappedValue, 1)
    }

    // MARK: - @Published / ObservableObject

    class Counter: SwiftOpenUI.ObservableObject {
        @SwiftOpenUI.Published var count = 0
    }

    func testPublishedInitialValue() {
        let counter = Counter()
        XCTAssertEqual(counter.count, 0)
    }

    func testPublishedSetValue() {
        let counter = Counter()
        counter.count = 42
        XCTAssertEqual(counter.count, 42)
    }

    func testObservedObjectStorageSchedulesRebuildOnPublishedChange() {
        let counter = Counter()
        let storage = ObservedObjectStorage(counter)
        let host = RecordingViewHost()

        storage.host = host
        counter.count = 1

        XCTAssertEqual(host.rebuildCount, 1)
    }

    func testObservedObjectStorageGenerationIncrementsOnPublishedChange() {
        let counter = Counter()
        let storage = ObservedObjectStorage(counter)
        let host = RecordingViewHost()

        storage.host = host
        XCTAssertEqual(storage.generation, 0)

        counter.count = 1

        XCTAssertEqual(storage.generation, 1)
    }

    // MARK: - Superclass @Published wiring

    class BaseModel: SwiftOpenUI.ObservableObject {
        @SwiftOpenUI.Published var baseProp = "base"
    }

    class DerivedModel: BaseModel {
        @SwiftOpenUI.Published var derivedProp = "derived"
    }

    func testWirePublishedWalksSuperclass() {
        let model = DerivedModel()
        var notifications = 0

        class MockHost: AnyViewHost {
            var onRebuild: (() -> Void)?
            func scheduleRebuild() { onRebuild?() }
            func suppressNextFocusRestore() {}
        }

        let host = MockHost()
        host.onRebuild = { notifications += 1 }

        let observed = ObservedObject<DerivedModel>(wrappedValue: model)
        observed.storage.host = host

        model.derivedProp = "changed"
        XCTAssertEqual(notifications, 1, "Derived @Published should trigger rebuild")

        model.baseProp = "changed"
        XCTAssertEqual(notifications, 2, "Inherited @Published should also trigger rebuild")
    }

    // MARK: - @StateObject

    func testStateObjectLazyCreation() {
        var created = false
        let stateObj = StateObject<Counter>(wrappedValue: {
            created = true
            return Counter()
        }())
        XCTAssertFalse(created == false && stateObj.wrappedValue.count == 0 ? false : true)
        // Access forces creation
        _ = stateObj.wrappedValue
        XCTAssertEqual(stateObj.wrappedValue.count, 0)
    }

    func testStateObjectReturnsSameInstance() {
        let stateObj = StateObject<Counter>(wrappedValue: Counter())
        let first = stateObj.wrappedValue
        let second = stateObj.wrappedValue
        XCTAssertTrue(first === second)
    }

    // MARK: - @FocusState

    func testFocusStateBoolDefault() {
        let focus = FocusState<Bool>()
        XCTAssertEqual(focus.wrappedValue, false)
    }

    func testFocusStateOptionalDefault() {
        enum Field { case name, email }
        let focus = FocusState<Field?>()
        XCTAssertNil(focus.storage.value as Any?)
    }

    func testFocusStateStorageForwardsStaleMutations() {
        let stale = FocusStateStorage(false, default: false)
        let current = FocusStateStorage(false, default: false)

        stale.forwardMutations(to: current)
        stale.setProgrammatic(true)

        XCTAssertEqual(current.value, true)
    }
}
