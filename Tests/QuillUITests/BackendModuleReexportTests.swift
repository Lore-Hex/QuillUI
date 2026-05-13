import QuillUIGtk
import QuillUIQt
import Testing

@Suite("Backend module re-exports")
struct BackendModuleReexportTests {
    @Test("GTK and Qt facades expose the shared QuillUI surface")
    func backendModulesExposeCoreQuillUISurface() {
        let gtkAppType: QuillBackendApp<QuillGtkBackend>.Type = QuillGtkApp.self
        let qtAppType: QuillBackendApp<QuillQtBackend>.Type = QuillQtApp.self
        let runtimeStatusType: QuillBackendRuntimeStatus.Type = QuillGtkBackendStatus.self
        let runtimeModeType: QuillBackendRuntimeMode.Type = QuillQtRuntimeMode.self

        #expect(gtkAppType == QuillBackendApp<QuillGtkBackend>.self)
        #expect(qtAppType == QuillBackendApp<QuillQtBackend>.self)
        #expect(runtimeStatusType == QuillBackendRuntimeStatus.self)
        #expect(runtimeModeType == QuillBackendRuntimeMode.self)
        #expect(QuillGtkBackend.identifier == .gtk)
        #expect(QuillQtBackend.identifier == .qt)
    }
}
