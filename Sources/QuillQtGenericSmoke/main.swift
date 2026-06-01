// quill-qt-generic-smoke — entry point for the GENERIC SwiftUI→Qt backend.
//
// Unlike quill-qt-interaction-smoke (which calls the hand-built C++
// quill_qt_run_interaction_smoke), this routes a REAL SwiftOpenUI App through
// the generic QtBackend. It is a SIBLING executable so the existing Qt smoke
// and its CI gate are completely untouched by this spike.
//
// The whole target is behind `canImport(BackendQt)` — which only resolves when
// the manifest is compiled with QUILLUI_LINUX_BACKEND=qt AND QUILLUI_QT_GENERIC=1
// (see Package.swift). In any other configuration this file is an inert stub.

#if canImport(BackendQt)
import BackendQt

QtBackend().run(QtSmokeApp.self)
#endif
