import Testing

#if os(Linux)
import SwiftUI

// `@MainActor`: the text-input/submitLabel cases build MainActor-isolated
// SwiftUI views (TextField/SecureField/Text + @ViewBuilder prompts) whose
// initializers run a Swift-6 isolation check that SIGTRAPs off the main
// actor. Swift Testing runs @Test cases off-main, so pin the suite.
@Suite("SwiftOpenUI state compatibility")
@MainActor
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

    @Test("SwiftUI text-input prompt overloads are visible through the shim")
    func swiftUITextInputPromptOverloadsCompileThroughSwiftUIShim() {
        var draft = ""
        let binding = Binding<String>(
            get: { draft },
            set: { draft = $0 }
        )

        let promptedField = TextField("Message", text: binding, prompt: Text("Ask anything"))
        let labeledField = TextField(text: binding, prompt: nil) {
            Text("Composer")
        }
        let promptedSecureField = SecureField("Token", text: binding, prompt: Text("API token"))
        let labeledSecureField = SecureField(text: binding, prompt: nil) {
            Text("Password")
        }

        #expect(promptedField.title == "Ask anything")
        #expect(labeledField.title == "Composer")
        #expect(promptedSecureField.placeholder == "API token")
        #expect(labeledSecureField.placeholder == "Password")
    }

    @Test("SwiftUI submitLabel metadata is visible through the shim")
    func swiftUISubmitLabelCompilesThroughSwiftUIShim() {
        let submitted = Text("Send").submitLabel(.send)

        #expect(submitted.submitLabel == .send)
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
