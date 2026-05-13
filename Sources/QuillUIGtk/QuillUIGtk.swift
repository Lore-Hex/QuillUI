import QuillUI

public typealias QuillGtkRuntimeMode = QuillBackendRuntimeMode
public typealias QuillGtkBackendStatus = QuillBackendRuntimeStatus

public enum QuillGtkBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .gtk
}

public enum QuillGtkApp {
    public static func run<A: App>(_ appType: A.Type) {
        QuillBackendApp<QuillGtkBackend>.run(appType)
    }
}
