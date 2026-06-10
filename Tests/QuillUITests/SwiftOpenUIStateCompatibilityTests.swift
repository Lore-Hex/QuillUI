import Testing

#if os(Linux)
import SwiftUI

@Suite("SwiftOpenUI state compatibility")
struct SwiftOpenUIStateCompatibilityTests {
    @Test("@State observes lowered @Observable object mutations")
    func stateStorageObservesLoweredObservableObjectMutations() {
        let model = StateObservableProbe()
        let storage = StateStorage(model)
        let host = RebuildProbeHost()

        storage.host = host
        model.title = "selected"

        #expect(host.rebuilds == 1)
    }

    @Test("@State rewires observable objects restored from previous render storage")
    func stateStorageRewiresRestoredObservableObjectMutations() {
        let originalModel = StateObservableProbe()
        let originalStorage = StateStorage(originalModel)
        let restoredStorage = StateStorage(StateObservableProbe())
        let host = RebuildProbeHost()

        restoredStorage.host = host
        restoredStorage.restoreValue(from: originalStorage)
        originalModel.title = "restored"

        #expect(host.rebuilds == 1)
    }

    @Test("stale @State closures forward writes to the current render storage")
    func staleStateStorageForwardsMutationsToCurrentStorage() {
        let staleStorage = StateStorage("old")
        let currentStorage = StateStorage("current")
        let host = RebuildProbeHost()

        currentStorage.host = host
        staleStorage.forwardMutations(to: currentStorage)
        staleStorage.setValue("new")

        #expect(staleStorage.value == "old")
        #expect(currentStorage.value == "new")
        #expect(host.rebuilds == 1)
    }
}

private final class StateObservableProbe: ObservableObject {
    @Published var title = "idle"
}

private final class RebuildProbeHost: AnyViewHost {
    var rebuilds = 0

    func scheduleRebuild() {
        rebuilds += 1
    }

    func suppressNextFocusRestore() {}
}
#endif
