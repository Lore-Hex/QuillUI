import Testing

#if os(Linux)
import Observation
import SwiftOpenUI
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

    @Test("@State observes macro @Observable object mutations")
    func stateStorageObservesMacroObservableObjectMutations() {
        let model = MacroObservableProbe()
        let storage = StateStorage(model)
        let host = RebuildProbeHost()

        storage.host = host
        model.title = "selected"

        #expect(host.rebuilds == 1)
    }

    @Test("@Environment observes macro @Observable object mutations")
    func environmentObjectReadObservesMacroObservableObjectMutations() {
        let model = MacroObservableProbe()
        let host = RebuildProbeHost()
        var env = EnvironmentValues()
        env.setObject(model)
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        beginEnvironmentReadTracking()
        beginDependencyTracking(host: host)
        let reader = Environment(MacroObservableProbe.self)
        #expect(reader.wrappedValue === model)
        let tracking = endDependencyTracking()
        _ = endEnvironmentReadTracking()

        #expect(tracking?.snapshots.isEmpty == false)

        model.title = "selected"

        #expect(host.rebuilds == 1)
    }

    @Test("@Environment wrapper wires macro @Observable mutations before explicit reads")
    func environmentWrapperWiresInjectedObservableObjectMutations() {
        let model = MacroObservableProbe()
        let host = RebuildProbeHost()
        var env = EnvironmentValues()
        env.setObject(model)
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        let reader = Environment(MacroObservableProbe.self)
        reader.wireInjectedObject(to: host)
        model.title = "wired"

        #expect(host.rebuilds == 1)
    }

    @Test("@Bindable environment-object writes invalidate didSet-only observable properties")
    func bindableEnvironmentObjectWritesInvalidateDidSetOnlyObservableProperties() {
        let model = DidSetObservableProbe()
        let host = RebuildProbeHost()
        var env = EnvironmentValues()
        env.setObject(model)
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        beginEnvironmentReadTracking()
        beginDependencyTracking(host: host)
        let reader = Environment(DidSetObservableProbe.self)
        #expect(reader.wrappedValue === model)
        let tracking = endDependencyTracking()
        _ = endEnvironmentReadTracking()

        host.rebuilds = 0
        Bindable(wrappedValue: reader.wrappedValue).followSystemColorScheme.wrappedValue = false

        #expect(model.followSystemColorScheme == false)
        #expect(model.didSetCount == 1)
        #expect(host.rebuilds == 1)
        #expect(!inputsUnchanged(snapshot: tracking?.snapshots ?? []))
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

    @Test("Binding dynamic-member projections preserve parent identity")
    func bindingDynamicMemberProjectionPreservesParentIdentity() {
        let owner = BindingIdentityOwner()
        var model = BindingIdentityModel(title: "idle")
        let parentIdentity = BindingIdentity(objectIdentifier: ObjectIdentifier(owner))
        let binding = Binding<BindingIdentityModel>(
            get: { model },
            set: { model = $0 },
            quillUIIdentity: parentIdentity
        )

        let title = binding.title

        #expect(title.quillUIIdentity != nil)
        #expect(title.quillUIIdentity != parentIdentity)

        title.wrappedValue = "selected"

        #expect(model.title == "selected")
    }

    @Test("containerRelativeFrame maps axes to fill frame constraints")
    func containerRelativeFrameMapsAxesToFillFrameConstraints() {
        let bothAxes = Text("media").containerRelativeFrame([.horizontal, .vertical])

        #expect(bothAxes.maxWidth == Double.infinity)
        #expect(bothAxes.maxHeight == Double.infinity)

        let horizontal = Text("media").containerRelativeFrame([.horizontal])

        #expect(horizontal.maxWidth == Double.infinity)
        #expect(horizontal.maxHeight == nil)

        let countedHorizontal = Text("media").containerRelativeFrame(
            .horizontal,
            count: 4,
            span: 1,
            spacing: 8
        )

        #expect(countedHorizontal.maxWidth == Double.infinity)
        #expect(countedHorizontal.maxHeight == nil)
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

    @Test("SwiftUI redacted writes redactionReasons environment")
    func swiftUIRedactedWritesRedactionEnvironment() {
        var observed = RedactionReasons()
        let view = RedactionProbe { reasons in
            observed = reasons
        }.redacted(reason: .placeholder)

        #expect(view.value.contains(.placeholder))

        var env = EnvironmentValues()
        env[keyPath: view.keyPath] = view.value
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        _ = view.content.body

        #expect(observed.contains(.placeholder))
    }

    @Test("SwiftUI unredacted clears inherited redactionReasons environment")
    func swiftUIUnredactedClearsInheritedRedactionEnvironment() {
        var observed = RedactionReasons.placeholder
        let view = RedactionProbe { reasons in
            observed = reasons
        }.unredacted()

        #expect(!view.value.contains(.placeholder))

        var env = EnvironmentValues()
        env.redactionReasons = .placeholder
        env[keyPath: view.keyPath] = view.value
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(nil) }

        _ = view.content.body

        #expect(!observed.contains(.placeholder))
    }

    @Test("NavigationStack typed path binding exposes type-erased elements")
    func navigationStackTypedPathBindingExposesTypeErasedElements() {
        enum Route: Hashable {
            case detail(String)
        }

        var path: [Route] = []
        let binding = Binding<[Route]>(
            get: { path },
            set: { path = $0 }
        )

        let stack = NavigationStack(path: binding) {
            Text("Root")
        }

        #expect(stack.pathBinding == nil)
        #expect(stack.typedPathBinding?.elements().isEmpty == true)

        stack.typedPathBinding?.append(AnyHashable(Route.detail("1003")))

        #expect(path == [.detail("1003")])
        #expect(stack.typedPathBinding?.elements() == [AnyHashable(Route.detail("1003"))])

        stack.typedPathBinding?.removeLast(1)

        #expect(path.isEmpty)
    }
}

private struct RedactionProbe: View {
    @Environment(\.redactionReasons) private var redactionReasons

    let observe: (RedactionReasons) -> Void

    var body: some View {
        observe(redactionReasons)
        return Text("redaction-probe")
    }
}

private final class StateObservableProbe: ObservableObject {
    @Published var title = "idle"
}

private final class DidSetObservableProbe: ObservableObject {
    var followSystemColorScheme = true {
        didSet { didSetCount += 1 }
    }
    var didSetCount = 0
}

private final class BindingIdentityOwner {}

private struct BindingIdentityModel {
    var title: String
}

@Observable
private final class MacroObservableProbe {
    var title = "idle"
}

private final class RebuildProbeHost: AnyViewHost {
    var rebuilds = 0

    func scheduleRebuild() {
        rebuilds += 1
    }

    func suppressNextFocusRestore() {}
}
#endif
