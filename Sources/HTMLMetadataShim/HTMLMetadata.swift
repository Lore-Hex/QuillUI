import Foundation
import QuillRSCoreShim

public final actor HTMLMetadataDatabase {
    @MainActor public static let shared = HTMLMetadataDatabase(
        databasePath: AppConfig.dataFolder.appendingPathComponent("HTMLMetadata.db").path
    )

    public nonisolated let databasePath: String
    private var vacuumCount = 0

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    public func vacuum() {
        vacuumCount += 1
    }

    public func quillVacuumCount() -> Int {
        vacuumCount
    }
}
