#if canImport(CQuillQt6WidgetsShim)
import CQuillQt6WidgetsShim
import Glibc
#else
import QuillInteractionSmokeSupport
import QuillUIQt

private typealias QuillQtInteractionSmokeApp = QuillBackendInteractionSmokeApp<QuillQtBackend>

QuillQtApp.run(QuillQtInteractionSmokeApp.self)
#endif

#if canImport(CQuillQt6WidgetsShim)
exit(Int32(quill_qt_run_interaction_smoke(CommandLine.argc, CommandLine.unsafeArgv)))
#endif
