import Foundation
import CoreGraphics

@MainActor
final class CalibrationManager: ObservableObject {
    @Published private(set) var calibrations: [String: Calibration] = [:]

    private let settingsStore: SettingsStore
    private let storageKey = "calibrations"

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        loadCalibrations()
    }

    // MARK: - Public API

    func getCalibration(for cameraID: String, resolution: CGSize) -> Calibration? {
        let key = makeKey(cameraID: cameraID, resolution: resolution)
        return calibrations[key]
    }

    func saveCalibration(_ calibration: Calibration) {
        calibrations[calibration.id] = calibration
        persistCalibrations()
        Logger.calibration.info("Saved calibration: \(calibration.id) = \(calibration.micronsPerPixel) µm/px")
    }

    func deleteCalibration(for cameraID: String, resolution: CGSize) {
        let key = makeKey(cameraID: cameraID, resolution: resolution)
        calibrations.removeValue(forKey: key)
        persistCalibrations()
        Logger.calibration.info("Deleted calibration: \(key)")
    }

    func deleteAllCalibrations(for cameraID: String) {
        calibrations = calibrations.filter { !$0.key.hasPrefix(cameraID) }
        persistCalibrations()
        Logger.calibration.info("Deleted all calibrations for camera: \(cameraID)")
    }

    func hasCalibration(for cameraID: String, resolution: CGSize) -> Bool {
        getCalibration(for: cameraID, resolution: resolution) != nil
    }

    // MARK: - Calibration Calculation

    func calculateMicronsPerPixel(lineLength pixels: Double, knownLength microns: Double) -> Double {
        guard pixels > 0 else { return 0 }
        return microns / pixels
    }

    // MARK: - Private

    private func makeKey(cameraID: String, resolution: CGSize) -> String {
        "\(cameraID)_\(Int(resolution.width))x\(Int(resolution.height))"
    }

    private func loadCalibrations() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            Logger.calibration.debug("No saved calibrations found")
            return
        }

        do {
            let decoded = try JSONDecoder().decode([String: Calibration].self, from: data)
            calibrations = decoded
            Logger.calibration.info("Loaded \(decoded.count) calibrations")
        } catch {
            Logger.calibration.error("Failed to decode calibrations: \(error)")
        }
    }

    private func persistCalibrations() {
        do {
            let data = try JSONEncoder().encode(calibrations)
            UserDefaults.standard.set(data, forKey: storageKey)
            Logger.calibration.debug("Persisted \(self.calibrations.count) calibrations")
        } catch {
            Logger.calibration.error("Failed to encode calibrations: \(error)")
        }
    }
}
