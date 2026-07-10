import AppKit
import CoreImage
import UniformTypeIdentifiers

@MainActor
final class SnapshotManager: ObservableObject {
    @Published private(set) var lastSnapshotURL: URL?

    // MARK: - Configuration

    struct Configuration {
        var format: ImageFormat = .png
        var outputDirectory: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        var includeOverlays: Bool = true
    }

    enum ImageFormat: String, CaseIterable {
        case png = "png"
        case tiff = "tiff"
        case jpeg = "jpeg"

        var utType: UTType {
            switch self {
            case .png: return .png
            case .tiff: return .tiff
            case .jpeg: return .jpeg
            }
        }

        var fileExtension: String { rawValue }
    }

    private var configuration = Configuration()
    private let ciContext = CIContext()

    // MARK: - Public API

    func captureSnapshot(
        from captureManager: CaptureManager,
        transform: ViewTransform,
        includeOverlays: Bool
    ) async {
        guard let frame = captureManager.latestFrame else {
            Logger.snapshot.warning("No frame available for snapshot")
            return
        }

        let filename = generateFilename()
        let outputURL = configuration.outputDirectory.appendingPathComponent(filename)

        do {
            try await saveImage(frame, to: outputURL)
            lastSnapshotURL = outputURL
            Logger.snapshot.info("Snapshot saved: \(filename)")

            // Show notification
            showSaveNotification(url: outputURL)
        } catch {
            Logger.snapshot.error("Failed to save snapshot: \(error)")
        }
    }

    func copyToClipboard(from captureManager: CaptureManager) async {
        guard let frame = captureManager.latestFrame else {
            Logger.snapshot.warning("No frame available for clipboard")
            return
        }

        guard let cgImage = ciContext.createCGImage(frame, from: frame.extent) else {
            Logger.snapshot.error("Failed to create CGImage")
            return
        }

        let image = NSImage(cgImage: cgImage, size: frame.extent.size)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        Logger.snapshot.info("Snapshot copied to clipboard")
    }

    func setFormat(_ format: ImageFormat) {
        configuration.format = format
    }

    func setOutputDirectory(_ url: URL) {
        configuration.outputDirectory = url
    }

    // MARK: - Private

    private func saveImage(_ image: CIImage, to url: URL) async throws {
        let format = configuration.format

        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw SnapshotError.cannotCreateCGImage
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        let data: Data?
        switch format {
        case .png:
            data = bitmapRep.representation(using: .png, properties: [:])
        case .tiff:
            data = bitmapRep.representation(using: .tiff, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw])
        case .jpeg:
            data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }

        guard let imageData = data else {
            throw SnapshotError.cannotEncodeImage
        }

        try imageData.write(to: url)
    }

    private func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "SolderScope_\(timestamp).\(configuration.format.fileExtension)"
    }

    private func showSaveNotification(url: URL) {
        // Play camera shutter sound
        NSSound(named: "Grab")?.play()

        // Show in Finder (optional - could be a setting)
        // NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Errors

enum SnapshotError: LocalizedError {
    case cannotCreateCGImage
    case cannotEncodeImage

    var errorDescription: String? {
        switch self {
        case .cannotCreateCGImage:
            return "Cannot create image from frame"
        case .cannotEncodeImage:
            return "Cannot encode image to file format"
        }
    }
}
