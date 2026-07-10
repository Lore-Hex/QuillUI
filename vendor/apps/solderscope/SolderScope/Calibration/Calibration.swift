import Foundation
import CoreGraphics

struct Calibration: Codable, Identifiable {
    let id: String
    let cameraID: String
    let width: Int
    let height: Int
    let micronsPerPixel: Double
    let createdAt: Date

    init(cameraID: String, width: Int, height: Int, micronsPerPixel: Double) {
        self.id = "\(cameraID)_\(width)x\(height)"
        self.cameraID = cameraID
        self.width = width
        self.height = height
        self.micronsPerPixel = micronsPerPixel
        self.createdAt = Date()
    }

    var resolution: CGSize {
        CGSize(width: width, height: height)
    }

    var resolutionString: String {
        "\(width)×\(height)"
    }
}

// MARK: - Calibration Presets

enum CalibrationPreset: String, CaseIterable, Identifiable {
    case smd0402 = "0402"
    case smd0603 = "0603"
    case smd0805 = "0805"
    case headerPitch = "Header (2.54mm)"
    case custom = "Custom"

    var id: String { rawValue }

    var lengthMicrons: Double? {
        switch self {
        case .smd0402: return 1000      // 1.0mm
        case .smd0603: return 1600      // 1.6mm
        case .smd0805: return 2000      // 2.0mm
        case .headerPitch: return 2540  // 2.54mm
        case .custom: return nil
        }
    }

    var description: String {
        switch self {
        case .smd0402: return "0402 component (1.0 mm)"
        case .smd0603: return "0603 component (1.6 mm)"
        case .smd0805: return "0805 component (2.0 mm)"
        case .headerPitch: return "Header pitch (2.54 mm)"
        case .custom: return "Enter custom length"
        }
    }
}

// MARK: - Calibration Line

struct CalibrationLine {
    var startPoint: CGPoint?
    var endPoint: CGPoint?

    var isComplete: Bool {
        startPoint != nil && endPoint != nil
    }

    var lengthPixels: Double? {
        guard let start = startPoint, let end = endPoint else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }

    mutating func reset() {
        startPoint = nil
        endPoint = nil
    }
}
