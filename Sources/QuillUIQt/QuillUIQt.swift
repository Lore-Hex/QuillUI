// Backend facade modules re-export QuillUI so app targets can import one
// backend-specific product without duplicating the core UI import.
@_exported import QuillUI

#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI
#if canImport(BackendQt)
import BackendQt
#endif
#endif

public typealias QuillQtRuntimeMode = QuillBackendRuntimeMode
public typealias QuillQtRuntimeAvailability = QuillBackendRuntimeAvailability
public typealias QuillQtBackendStatus = QuillBackendRuntimeStatus

public enum QuillQtBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .qt
}

public enum QuillQtApp {
    public static func run<A: App>(_ appType: A.Type) {
        QuillQtBackend.initialize()

        #if os(Linux) && canImport(BackendQt)
        let launchPlan = QuillBackendLaunchPlan(
            requested: nil,
            preferred: .qt,
            selected: .qt,
            runtime: .qt
        )
        QuillBackendRuntimeContext.install(launchPlan)
        QtBackend().run(appType)
        #else
        QuillApp.run(appType, preferredBackend: .qt)
        #endif
    }
}
