import QuillUI

public typealias QuillGtkRuntimeMode = QuillBackendRuntimeMode
public typealias QuillGtkBackendStatus = QuillBackendRuntimeStatus

public enum QuillGtkBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .gtk
}

public typealias QuillGtkApp = QuillBackendApp<QuillGtkBackend>
