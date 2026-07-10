import QuillUIGtk
import QuillUIQt
import Testing

@Suite("Backend module re-exports")
struct BackendModuleReexportTests {
    @Test("GTK and Qt facades expose the shared QuillUI surface")
    func backendModulesExposeCoreQuillUISurface() {
        let gtkAppType: QuillBackendApp<QuillGtkBackend>.Type = QuillGtkApp.self
        let qtAppType: QuillQtApp.Type = QuillQtApp.self
        let runtimeStatusType: QuillBackendRuntimeStatus.Type = QuillGtkBackendStatus.self
        let runtimeModeType: QuillBackendRuntimeMode.Type = QuillQtRuntimeMode.self
        let gtkRuntimeAvailabilityType: QuillBackendRuntimeAvailability.Type = QuillGtkRuntimeAvailability.self
        let qtRuntimeAvailabilityType: QuillBackendRuntimeAvailability.Type = QuillQtRuntimeAvailability.self

        #expect(gtkAppType == QuillBackendApp<QuillGtkBackend>.self)
        #expect(qtAppType == QuillQtApp.self)
        #expect(runtimeStatusType == QuillBackendRuntimeStatus.self)
        #expect(runtimeModeType == QuillBackendRuntimeMode.self)
        #expect(gtkRuntimeAvailabilityType == QuillBackendRuntimeAvailability.self)
        #expect(qtRuntimeAvailabilityType == QuillBackendRuntimeAvailability.self)
        #expect(QuillGtkBackend.identifier == .gtk)
        #expect(QuillQtBackend.identifier == .qt)
        #expect(QuillGtkBackend.status.selected == QuillGtkBackend.launchPlan.selected)
        #expect(QuillGtkBackend.status.runtime == QuillGtkBackend.launchPlan.runtime)
        #expect(QuillGtkBackend.status.runtimeAvailability == QuillGtkBackend.launchPlan.runtimeAvailability)
        #expect(QuillGtkBackend.status.usesRuntimeFallback == QuillGtkBackend.launchPlan.usesRuntimeFallback)
        #expect(QuillGtkBackend.runtimeAvailability == QuillGtkBackend.status.runtimeAvailability)
        #expect(QuillGtkBackend.runtimeBackend == QuillGtkBackend.status.runtime)
        #expect(QuillGtkBackend.runtimeMode == QuillGtkBackend.status.mode)
        #expect(QuillGtkBackend.hasNativeRuntime == QuillGtkBackend.status.hasNativeRuntime)
        #expect(QuillGtkBackend.usesRuntimeFallback == QuillGtkBackend.status.usesRuntimeFallback)
        #expect(QuillGtkBackend.runtimeMessage == QuillGtkBackend.status.runtimeMessage)
        #expect(QuillQtBackend.status.selected == QuillQtBackend.launchPlan.selected)
        #expect(QuillQtBackend.status.runtime == QuillQtBackend.launchPlan.runtime)
        #expect(QuillQtBackend.status.runtimeAvailability == QuillQtBackend.launchPlan.runtimeAvailability)
        #expect(QuillQtBackend.status.usesRuntimeFallback == QuillQtBackend.launchPlan.usesRuntimeFallback)
        #expect(QuillQtBackend.runtimeAvailability == QuillQtBackend.status.runtimeAvailability)
        #expect(QuillQtBackend.runtimeBackend == QuillQtBackend.status.runtime)
        #expect(QuillQtBackend.runtimeMode == QuillQtBackend.status.mode)
        #expect(QuillQtBackend.hasNativeRuntime == QuillQtBackend.status.hasNativeRuntime)
        #expect(QuillQtBackend.usesRuntimeFallback == QuillQtBackend.status.usesRuntimeFallback)
        #expect(QuillQtBackend.runtimeMessage == QuillQtBackend.status.runtimeMessage)
    }
}
