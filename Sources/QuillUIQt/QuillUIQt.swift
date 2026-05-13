import QuillUI

public typealias QuillQtRuntimeMode = QuillBackendRuntimeMode
public typealias QuillQtBackendStatus = QuillBackendRuntimeStatus

public enum QuillQtBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .qt
}

public typealias QuillQtApp = QuillBackendApp<QuillQtBackend>
