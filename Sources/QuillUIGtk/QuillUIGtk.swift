// Backend facade modules re-export QuillUI so app targets can import one
// backend-specific product without duplicating the core UI import.
@_exported import QuillUI

public typealias QuillGtkRuntimeMode = QuillBackendRuntimeMode
public typealias QuillGtkBackendStatus = QuillBackendRuntimeStatus

public enum QuillGtkBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .gtk
}

public typealias QuillGtkApp = QuillBackendApp<QuillGtkBackend>
