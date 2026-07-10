import Foundation
import Combine

final class SettingsStore: ObservableObject {
    // MARK: - Keys

    private enum Keys {
        static let selectedCameraID = "selectedCameraID"
        static let isScaleBarVisible = "isScaleBarVisible"
        static let integrationLevel = "integrationLevel"
        static let snapshotFormat = "snapshotFormat"
        static let snapshotDirectory = "snapshotDirectory"
        static let recordingDirectory = "recordingDirectory"
        static let showFPSOverlay = "showFPSOverlay"
        static let recordingCodec = "recordingCodec"
    }

    // MARK: - Published Properties

    @Published var selectedCameraID: String? {
        didSet { save(selectedCameraID, forKey: Keys.selectedCameraID) }
    }

    @Published var isScaleBarVisible: Bool {
        didSet { save(isScaleBarVisible, forKey: Keys.isScaleBarVisible) }
    }

    @Published var integrationLevel: IntegrationLevel {
        didSet { save(integrationLevel.rawValue, forKey: Keys.integrationLevel) }
    }

    @Published var showFPSOverlay: Bool {
        didSet { save(showFPSOverlay, forKey: Keys.showFPSOverlay) }
    }

    @Published var snapshotFormat: String {
        didSet { save(snapshotFormat, forKey: Keys.snapshotFormat) }
    }

    @Published var snapshotDirectory: URL? {
        didSet {
            if let url = snapshotDirectory {
                save(url.path, forKey: Keys.snapshotDirectory)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.snapshotDirectory)
            }
        }
    }

    @Published var recordingDirectory: URL? {
        didSet {
            if let url = recordingDirectory {
                save(url.path, forKey: Keys.recordingDirectory)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.recordingDirectory)
            }
        }
    }

    // MARK: - Initialization

    init() {
        self.selectedCameraID = UserDefaults.standard.string(forKey: Keys.selectedCameraID)
        self.isScaleBarVisible = UserDefaults.standard.bool(forKey: Keys.isScaleBarVisible)
        self.showFPSOverlay = UserDefaults.standard.object(forKey: Keys.showFPSOverlay) as? Bool ?? true

        if let rawValue = UserDefaults.standard.object(forKey: Keys.integrationLevel) as? Int,
           let level = IntegrationLevel(rawValue: rawValue) {
            self.integrationLevel = level
        } else {
            self.integrationLevel = .one
        }

        self.snapshotFormat = UserDefaults.standard.string(forKey: Keys.snapshotFormat) ?? "png"

        if let path = UserDefaults.standard.string(forKey: Keys.snapshotDirectory) {
            self.snapshotDirectory = URL(fileURLWithPath: path)
        } else {
            self.snapshotDirectory = nil
        }

        if let path = UserDefaults.standard.string(forKey: Keys.recordingDirectory) {
            self.recordingDirectory = URL(fileURLWithPath: path)
        } else {
            self.recordingDirectory = nil
        }
    }

    // MARK: - Private Helpers

    private func save<T>(_ value: T?, forKey key: String) {
        if let value = value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        selectedCameraID = nil
        isScaleBarVisible = false
        integrationLevel = .one
        showFPSOverlay = true
        snapshotFormat = "png"
        snapshotDirectory = nil
        recordingDirectory = nil

        Logger.settings.info("Settings reset to defaults")
    }
}
