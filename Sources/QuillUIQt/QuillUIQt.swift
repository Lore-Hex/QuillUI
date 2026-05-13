// Backend facade modules re-export QuillUI so app targets can import one
// backend-specific product without duplicating the core UI import.
@_exported import QuillUI

public typealias QuillQtRuntimeMode = QuillBackendRuntimeMode
public typealias QuillQtRuntimeAvailability = QuillBackendRuntimeAvailability
public typealias QuillQtBackendStatus = QuillBackendRuntimeStatus

public enum QuillQtBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .qt
}

public typealias QuillQtApp = QuillBackendApp<QuillQtBackend>
