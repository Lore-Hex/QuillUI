import SwiftUI

struct ScaleBarView: View {
    let calibrationManager: CalibrationManager
    let cameraID: String
    let resolution: CGSize
    let zoomFactor: CGFloat
    var onDelete: (() -> Void)?

    @State private var showDeleteConfirmation = false

    private var scaleBar: ScaleBar? {
        guard let calibration = calibrationManager.getCalibration(for: cameraID, resolution: resolution) else {
            return nil
        }

        return ScaleBarCalculator.calculate(
            micronsPerPixel: calibration.micronsPerPixel,
            zoomFactor: zoomFactor
        )
    }

    var body: some View {
        if let bar = scaleBar {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: bar.widthPoints, height: 4)
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                Text(bar.label)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 1, x: 0, y: 1)

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(8)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .alert("Delete Calibration", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete?()
                }
            } message: {
                Text("Are you sure you want to delete the calibration for this camera and resolution?")
            }
        } else {
            Text("Not calibrated")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Scale Bar Model

struct ScaleBar {
    let lengthMicrons: Double
    let widthPoints: CGFloat
    let label: String
}

// MARK: - Scale Bar Calculator

enum ScaleBarCalculator {
    // "Nice" lengths in microns
    static let niceLengths: [Double] = [
        10, 20, 50,           // µm
        100, 200, 500,        // µm
        1000, 2000, 5000,     // mm
        10000, 20000, 50000   // cm
    ]

    // Target width range in screen points
    static let minWidth: CGFloat = 100
    static let maxWidth: CGFloat = 250
    static let targetWidth: CGFloat = 150

    static func calculate(micronsPerPixel: Double, zoomFactor: CGFloat) -> ScaleBar {
        // Effective microns per screen point
        // At zoom 1x, 1 image pixel = ~1 screen point (depending on fit)
        // At zoom 2x, 1 image pixel = 2 screen points
        let micronsPerPoint = micronsPerPixel / Double(zoomFactor)

        // Find the "nice" length that gives us a bar closest to target width
        var bestLength = niceLengths[0]
        var bestWidth = niceLengths[0] / micronsPerPoint

        for length in niceLengths {
            let width = length / micronsPerPoint

            if width >= Double(minWidth) && width <= Double(maxWidth) {
                // This length is within range
                if abs(width - Double(targetWidth)) < abs(bestWidth - Double(targetWidth)) {
                    bestLength = length
                    bestWidth = width
                }
            }
        }

        // If we couldn't find a good fit, use the closest
        if bestWidth < Double(minWidth) || bestWidth > Double(maxWidth) {
            for length in niceLengths {
                let width = length / micronsPerPoint
                if width >= Double(minWidth) {
                    bestLength = length
                    bestWidth = width
                    break
                }
            }
        }

        let label = formatLength(bestLength)

        return ScaleBar(
            lengthMicrons: bestLength,
            widthPoints: CGFloat(bestWidth),
            label: label
        )
    }

    private static func formatLength(_ microns: Double) -> String {
        if microns >= 10000 {
            // Show in cm
            let cm = microns / 10000
            if cm == floor(cm) {
                return "\(Int(cm)) cm"
            } else {
                return String(format: "%.1f cm", cm)
            }
        } else if microns >= 1000 {
            // Show in mm
            let mm = microns / 1000
            if mm == floor(mm) {
                return "\(Int(mm)) mm"
            } else {
                return String(format: "%.1f mm", mm)
            }
        } else {
            // Show in µm
            if microns == floor(microns) {
                return "\(Int(microns)) µm"
            } else {
                return String(format: "%.0f µm", microns)
            }
        }
    }
}
