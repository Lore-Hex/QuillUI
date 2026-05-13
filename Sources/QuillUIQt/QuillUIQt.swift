import QuillUI

public typealias QuillQtRuntimeMode = QuillBackendRuntimeMode
public typealias QuillQtBackendStatus = QuillBackendRuntimeStatus

public enum QuillQtBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .qt

    public static var status: QuillQtBackendStatus {
        runtimeStatus
    }
}

public enum QuillQtApp {
    public static func run<A: App>(_ appType: A.Type) {
        QuillApp.run(appType, preferredBackend: QuillQtBackend.identifier)
    }
}
