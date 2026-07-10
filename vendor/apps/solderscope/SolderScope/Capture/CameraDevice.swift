import AVFoundation

struct CameraDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let device: AVCaptureDevice
    let formats: [CameraFormat]

    var bestFormat: CameraFormat? {
        // Prefer highest resolution, then highest frame rate
        formats.sorted { a, b in
            if a.width != b.width { return a.width > b.width }
            if a.height != b.height { return a.height > b.height }
            return a.maxFrameRate > b.maxFrameRate
        }.first
    }

    init(device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.device = device
        self.formats = device.formats.compactMap { CameraFormat(format: $0) }
    }

    static func == (lhs: CameraDevice, rhs: CameraDevice) -> Bool {
        lhs.id == rhs.id
    }
}

struct CameraFormat: Identifiable {
    let id: String
    let format: AVCaptureDevice.Format
    let width: Int
    let height: Int
    let maxFrameRate: Double
    let pixelFormat: OSType

    init?(format: AVCaptureDevice.Format) {
        let description = format.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)

        // Filter out formats we don't want
        guard dimensions.width >= 640,
              dimensions.height >= 480 else {
            return nil
        }

        self.format = format
        self.width = Int(dimensions.width)
        self.height = Int(dimensions.height)
        self.pixelFormat = CMFormatDescriptionGetMediaSubType(description)

        // Get max frame rate
        let frameRateRanges = format.videoSupportedFrameRateRanges
        self.maxFrameRate = frameRateRanges.map(\.maxFrameRate).max() ?? 30.0

        self.id = "\(width)x\(height)@\(Int(maxFrameRate))"
    }

    var description: String {
        "\(width)×\(height) @ \(Int(maxFrameRate)) fps"
    }
}
