import Foundation
import CoreGraphics

enum Constants {
    // MARK: - App Info

    static let appName = "SolderScope"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    // MARK: - Zoom

    enum Zoom {
        static let minimum: CGFloat = 0.1
        static let maximum: CGFloat = 20.0
        static let defaultValue: CGFloat = 1.0
        static let scrollWheelFactor: CGFloat = 1.1
        static let trackpadFactor: CGFloat = 0.01
    }

    // MARK: - Scale Bar

    enum ScaleBar {
        static let minWidthPoints: CGFloat = 100
        static let maxWidthPoints: CGFloat = 250
        static let targetWidthPoints: CGFloat = 150

        /// Nice lengths in microns for scale bar
        static let niceLengths: [Double] = [
            10, 20, 50,             // µm
            100, 200, 500,          // µm
            1000, 2000, 5000,       // mm
            10000, 20000, 50000     // cm
        ]
    }

    // MARK: - Recording

    enum Recording {
        static let defaultBitrate = 10_000_000  // 10 Mbps
        static let keyFrameInterval = 30
    }

    // MARK: - Frame Integration

    enum Integration {
        static let levels = [1, 2, 4, 8, 16]
        static let defaultLevel = 1
    }

    // MARK: - UI

    enum UI {
        static let toolbarHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 8
        static let overlayOpacity: Double = 0.7
    }

    // MARK: - File Naming

    enum FileNaming {
        static let dateFormat = "yyyyMMdd_HHmmss"
        static let snapshotPrefix = "SolderScope_"
        static let recordingPrefix = "SolderScope_"
    }

    // MARK: - Keyboard Shortcuts

    enum Shortcuts {
        static let freeze = " "           // Space
        static let snapshot = "s"
        static let record = "r"
        static let integration = "i"
        static let scaleBar = "b"
        static let resetView = "0"
    }

    // MARK: - Calibration Presets

    enum CalibrationPresets {
        static let smd0402: Double = 1000       // 1.0 mm
        static let smd0603: Double = 1600       // 1.6 mm
        static let smd0805: Double = 2000       // 2.0 mm
        static let headerPitch: Double = 2540   // 2.54 mm
    }
}
