import XCTest
@testable import SwiftOpenUI

// MARK: - Mock ViewHost

private class MockViewHost: AnyViewHost, DependencyTrackingHost {
    var lastReadSet: Set<ObjectIdentifier>?
    var lastInputSnapshot: [StorageSnapshot]?
    var rebuildCount = 0

    func scheduleRebuild() { rebuildCount += 1 }
    func suppressNextFocusRestore() {}
}

private final class TrackingCounter: SwiftOpenUI.ObservableObject {
    @SwiftOpenUI.Published var count = 0
}

private final class TrackingObserverCounter: SwiftOpenUI.ObservableObject {
    var count = 0 {
        didSet { didSetCount += 1 }
    }
    var didSetCount = 0
}

final class DependencyTrackingTests: XCTestCase {

    // MARK: - Tracking context

    func testBeginEndTracking() {
        let obj = NSObject()
        beginDependencyTracking()
        recordDependencyRead(obj)
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.contains(ObjectIdentifier(obj)))
    }

    func testEmptyTrackingReturnsEmptySet() {
        beginDependencyTracking()
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.isEmpty)
    }

    func testNoTrackingReturnsNil() {
        let tracking = endDependencyTracking()
        XCTAssertNil(tracking)
    }

    func testTrackingRemembersCurrentHost() {
        let host = MockViewHost()
        beginDependencyTracking(host: host)
        XCTAssertTrue(currentDependencyTrackingHost() === host)
        _ = endDependencyTracking()
        XCTAssertNil(currentDependencyTrackingHost())
    }

    // MARK: - isDependency

    func testIsDependencyTrue() {
        let obj = NSObject()
        let readSet: Set<ObjectIdentifier> = [ObjectIdentifier(obj)]
        XCTAssertTrue(isDependency(obj, in: readSet))
    }

    func testIsDependencyFalse() {
        let obj = NSObject()
        let other = NSObject()
        let readSet: Set<ObjectIdentifier> = [ObjectIdentifier(other)]
        XCTAssertFalse(isDependency(obj, in: readSet))
    }

    // MARK: - Storage integration

    func testStateStorageRecordsDependency() {
        let storage = StateStorage(42)
        beginDependencyTracking()
        _ = storage.value
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.contains(ObjectIdentifier(storage)))
    }

    func testObservedObjectStorageRecordsDependency() {
        let storage = ObservedObjectStorage(TrackingCounter())
        beginDependencyTracking()
        _ = storage.access()
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.contains(ObjectIdentifier(storage)))
    }

    func testEnvironmentObservableObjectReadSchedulesHostOnPublishedChange() {
        let host = MockViewHost()
        let model = TrackingCounter()
        var env = EnvironmentValues()
        env.setObject(model)
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        beginEnvironmentReadTracking()
        beginDependencyTracking(host: host)
        let reader = Environment(TrackingCounter.self)
        XCTAssertTrue(reader.wrappedValue === model)
        let tracking = endDependencyTracking()
        _ = endEnvironmentReadTracking()

        XCTAssertNotNil(tracking)
        XCTAssertFalse(tracking!.snapshots.isEmpty)
        host.lastInputSnapshot = tracking!.snapshots

        host.rebuildCount = 0
        model.count = 1

        XCTAssertEqual(host.rebuildCount, 1)
        XCTAssertFalse(inputsUnchanged(snapshot: host.lastInputSnapshot ?? []))
    }

    func testBindableEnvironmentObjectMutationSchedulesHostWhenObjectDoesNotPublish() {
        let host = MockViewHost()
        let model = TrackingObserverCounter()
        var env = EnvironmentValues()
        env.setObject(model)
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        beginEnvironmentReadTracking()
        beginDependencyTracking(host: host)
        let reader = Environment(TrackingObserverCounter.self)
        XCTAssertTrue(reader.wrappedValue === model)
        let tracking = endDependencyTracking()
        _ = endEnvironmentReadTracking()
        host.lastInputSnapshot = tracking?.snapshots

        host.rebuildCount = 0
        Bindable(wrappedValue: reader.wrappedValue).count.wrappedValue = 1

        XCTAssertEqual(model.count, 1)
        XCTAssertEqual(model.didSetCount, 1)
        XCTAssertEqual(host.rebuildCount, 1)
        XCTAssertFalse(inputsUnchanged(snapshot: host.lastInputSnapshot ?? []))
    }

    func testBindableEnvironmentObjectMutationDoesNotDoubleScheduleWhenObjectPublishes() {
        let host = MockViewHost()
        let model = TrackingCounter()
        var env = EnvironmentValues()
        env.setObject(model)
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        beginEnvironmentReadTracking()
        beginDependencyTracking(host: host)
        let reader = Environment(TrackingCounter.self)
        XCTAssertTrue(reader.wrappedValue === model)
        let tracking = endDependencyTracking()
        _ = endEnvironmentReadTracking()
        host.lastInputSnapshot = tracking?.snapshots

        host.rebuildCount = 0
        Bindable(wrappedValue: reader.wrappedValue).count.wrappedValue = 1

        XCTAssertEqual(model.count, 1)
        XCTAssertEqual(host.rebuildCount, 1)
        XCTAssertFalse(inputsUnchanged(snapshot: host.lastInputSnapshot ?? []))
    }

    // MARK: - @State always rebuilds (no gating)

    func testStateAlwaysRebuildsEvenWhenUnread() {
        let host = MockViewHost()
        let unreadStorage = StateStorage(1)
        unreadStorage.host = host

        beginDependencyTracking()
        let tracking = endDependencyTracking()
        host.lastReadSet = tracking?.readSet

        host.rebuildCount = 0
        unreadStorage.setValue(99)
        XCTAssertEqual(host.rebuildCount, 1, "@State must always rebuild — may pass value via Binding")
    }

    // MARK: - ObservableObject input gating

    func testObservedObjectInputsRemainUnchangedForUnreadStorageMutation() {
        let host = MockViewHost()
        let readObject = ObservedObjectStorage(TrackingCounter())
        let unreadObject = ObservedObjectStorage(TrackingCounter())
        readObject.host = host
        unreadObject.host = host

        beginDependencyTracking()
        _ = readObject.access()
        let tracking = endDependencyTracking()
        host.lastReadSet = tracking?.readSet
        host.lastInputSnapshot = tracking?.snapshots

        host.rebuildCount = 0
        unreadObject.object.count = 1

        XCTAssertTrue(inputsUnchanged(snapshot: host.lastInputSnapshot ?? []))
    }

    func testObservedObjectInputsChangeForReadStorageMutation() {
        let host = MockViewHost()
        let readObject = ObservedObjectStorage(TrackingCounter())
        readObject.host = host

        beginDependencyTracking()
        _ = readObject.access()
        let tracking = endDependencyTracking()
        host.lastReadSet = tracking?.readSet
        host.lastInputSnapshot = tracking?.snapshots

        host.rebuildCount = 0
        readObject.object.count = 1

        XCTAssertFalse(inputsUnchanged(snapshot: host.lastInputSnapshot ?? []))
    }

    // MARK: - Nested tracking (stack-based)

    func testNestedTrackingPreservesParentSession() {
        let parentObj = NSObject()
        let childObj = NSObject()

        beginDependencyTracking()
        recordDependencyRead(parentObj)

        beginDependencyTracking()
        recordDependencyRead(childObj)
        let childTracking = endDependencyTracking()

        XCTAssertNotNil(childTracking)
        XCTAssertTrue(childTracking!.readSet.contains(ObjectIdentifier(childObj)))
        XCTAssertFalse(childTracking!.readSet.contains(ObjectIdentifier(parentObj)))

        let parentTracking = endDependencyTracking()
        XCTAssertNotNil(parentTracking)
        XCTAssertTrue(parentTracking!.readSet.contains(ObjectIdentifier(parentObj)))
        XCTAssertFalse(parentTracking!.readSet.contains(ObjectIdentifier(childObj)))
    }
}
