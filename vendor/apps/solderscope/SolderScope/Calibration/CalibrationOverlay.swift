import SwiftUI
import AppKit

struct CalibrationOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var calibrationLine = CalibrationLine()
    @State private var isDrawing = false
    @State private var selectedPreset: CalibrationPreset?
    @State private var customLengthText = ""

    var body: some View {
        ZStack {
            // Semi-transparent background that captures escape key
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onExitCommand {
                    appState.cancelCalibration()
                }

            // Drawing canvas
            CalibrationCanvas(
                line: $calibrationLine,
                isDrawing: $isDrawing,
                transform: appState.viewTransform,
                imageSize: appState.currentResolution
            )

            // Instructions / Input
            VStack {
                // Header
                HStack {
                    Text("Calibration Mode")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Button("Cancel") {
                        appState.cancelCalibration()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding()
                .background(Color.black.opacity(0.7))

                Spacer()

                // Instructions or length presets
                if !calibrationLine.isComplete {
                    InstructionsView()
                } else {
                    LengthPresetView(
                        lineLength: calibrationLine.lengthPixels ?? 0,
                        onPresetSelected: { preset in
                            selectedPreset = preset
                            if preset == .custom {
                                // Show alert asynchronously to avoid SwiftUI update issues
                                DispatchQueue.main.async {
                                    showCustomLengthAlert()
                                }
                            } else if let microns = preset.lengthMicrons {
                                completeCalibration(microns: microns)
                            }
                        },
                        onReset: {
                            calibrationLine.reset()
                        }
                    )
                }
            }
        }
    }

    private func showCustomLengthAlert() {
        let alert = NSAlert()
        alert.messageText = "Enter Known Length"
        alert.informativeText = "Supports: mm, µm, cm, in (default: mm)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "e.g., 2.54 mm"
        textField.stringValue = customLengthText
        alert.accessoryView = textField

        // Make text field first responder after alert is shown
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            customLengthText = textField.stringValue
            if let microns = parseLength(customLengthText) {
                completeCalibration(microns: microns)
            }
        }

        selectedPreset = nil
    }

    private func completeCalibration(microns: Double) {
        guard let pixels = calibrationLine.lengthPixels else { return }

        let micronsPerPixel = appState.calibrationManager.calculateMicronsPerPixel(
            lineLength: pixels,
            knownLength: microns
        )

        appState.completeCalibration(micronsPerPixel: micronsPerPixel)
    }

    private func parseLength(_ text: String) -> Double? {
        // Try to parse number with optional unit
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()

        // Extract number and unit
        let pattern = #"^([\d.]+)\s*(mm|µm|um|cm|in|inch)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return Double(trimmed).map { $0 * 1000 } // Assume mm if no unit
        }

        guard let numberRange = Range(match.range(at: 1), in: trimmed),
              let number = Double(trimmed[numberRange]) else {
            return nil
        }

        let unitRange = match.range(at: 2)
        let unit: String
        if unitRange.location != NSNotFound, let range = Range(unitRange, in: trimmed) {
            unit = String(trimmed[range])
        } else {
            unit = "mm" // Default
        }

        // Convert to microns
        switch unit {
        case "µm", "um":
            return number
        case "mm":
            return number * 1000
        case "cm":
            return number * 10000
        case "in", "inch":
            return number * 25400
        default:
            return number * 1000 // Assume mm
        }
    }
}

// MARK: - Calibration Canvas

struct CalibrationCanvas: NSViewRepresentable {
    @Binding var line: CalibrationLine
    @Binding var isDrawing: Bool
    let transform: ViewTransform
    let imageSize: CGSize

    func makeNSView(context: Context) -> CalibrationCanvasNSView {
        let view = CalibrationCanvasNSView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CalibrationCanvasNSView, context: Context) {
        nsView.line = line
        nsView.viewTransform = transform
        nsView.imageSize = imageSize
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: CalibrationCanvasDelegate {
        let parent: CalibrationCanvas

        init(_ parent: CalibrationCanvas) {
            self.parent = parent
        }

        func canvasDidStartLine(at point: CGPoint) {
            parent.line.startPoint = point
            parent.line.endPoint = nil
            parent.isDrawing = true
        }

        func canvasDidUpdateLine(to point: CGPoint) {
            parent.line.endPoint = point
        }

        func canvasDidFinishLine() {
            parent.isDrawing = false
        }
    }
}

protocol CalibrationCanvasDelegate: AnyObject {
    func canvasDidStartLine(at point: CGPoint)
    func canvasDidUpdateLine(to point: CGPoint)
    func canvasDidFinishLine()
}

class CalibrationCanvasNSView: NSView {
    weak var delegate: CalibrationCanvasDelegate?
    var line = CalibrationLine()
    var viewTransform = ViewTransform()
    var imageSize: CGSize = .zero

    private var isDragging = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw line if we have points
        guard let start = line.startPoint, let current = line.endPoint ?? line.startPoint else { return }

        // Convert image points to view points
        let viewStart = viewTransform.imageToView(point: start, imageSize: imageSize, viewSize: bounds.size)
        let viewEnd = viewTransform.imageToView(point: current, imageSize: imageSize, viewSize: bounds.size)

        // Draw line with outline
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(4)
        context.move(to: viewStart)
        context.addLine(to: viewEnd)
        context.strokePath()

        context.setStrokeColor(NSColor.yellow.cgColor)
        context.setLineWidth(2)
        context.move(to: viewStart)
        context.addLine(to: viewEnd)
        context.strokePath()

        // Draw endpoints
        let pointRadius: CGFloat = 6

        for point in [viewStart, viewEnd] {
            context.setFillColor(NSColor.yellow.cgColor)
            context.fillEllipse(in: CGRect(
                x: point.x - pointRadius,
                y: point.y - pointRadius,
                width: pointRadius * 2,
                height: pointRadius * 2
            ))
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: CGRect(
                x: point.x - pointRadius,
                y: point.y - pointRadius,
                width: pointRadius * 2,
                height: pointRadius * 2
            ))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewTransform.viewToImage(point: viewPoint, imageSize: imageSize, viewSize: bounds.size)

        delegate?.canvasDidStartLine(at: imagePoint)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewTransform.viewToImage(point: viewPoint, imageSize: imageSize, viewSize: bounds.size)

        delegate?.canvasDidUpdateLine(to: imagePoint)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }

        isDragging = false
        delegate?.canvasDidFinishLine()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

// MARK: - Supporting Views

struct InstructionsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.diagonal")
                .font(.system(size: 32))
                .foregroundColor(.yellow)

            Text("Draw a line across a known distance")
                .font(.headline)

            Text("Click and drag to draw a calibration line across a feature with known size (e.g., 0402 component, header pitch)")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

struct LengthPresetView: View {
    let lineLength: Double
    let onPresetSelected: (CalibrationPreset) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Line drawn: \(Int(lineLength)) pixels")
                .font(.headline)

            Text("Select the known length:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(CalibrationPreset.allCases) { preset in
                    Button(action: { onPresetSelected(preset) }) {
                        HStack {
                            Text(preset.description)
                            Spacer()
                            if preset != .custom {
                                Image(systemName: "arrow.right")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 280)

            Button("Redraw Line", action: onReset)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}


