import Foundation
import os.log

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.solderscope"

    static let app = os.Logger(subsystem: subsystem, category: "App")
    static let capture = os.Logger(subsystem: subsystem, category: "Capture")
    static let calibration = os.Logger(subsystem: subsystem, category: "Calibration")
    static let recording = os.Logger(subsystem: subsystem, category: "Recording")
    static let snapshot = os.Logger(subsystem: subsystem, category: "Snapshot")
    static let settings = os.Logger(subsystem: subsystem, category: "Settings")
    static let render = os.Logger(subsystem: subsystem, category: "Render")
}
