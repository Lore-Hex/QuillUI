import AVFoundation
import CoreImage
import Combine

@MainActor
final class CaptureManager: NSObject, ObservableObject {
    // MARK: - Published State
    @Published private(set) var availableCameras: [CameraDevice] = []
    @Published private(set) var currentCamera: CameraDevice?
    @Published private(set) var currentFormat: CameraFormat?
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var latestFrame: CIImage?

    // MARK: - Capture Session
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentInput: AVCaptureDeviceInput?

    private let captureQueue = DispatchQueue(label: "com.solderscope.capture", qos: .userInteractive)
    private let processingQueue = DispatchQueue(label: "com.solderscope.processing", qos: .userInitiated)

    // MARK: - Frame Processing
    private nonisolated(unsafe) var frameProcessor: FrameProcessor?
    private var integrationLevel: IntegrationLevel = .one

    // MARK: - FPS Tracking
    private var frameTimestamps: [CFAbsoluteTime] = []
    private let fpsWindowSize = 30

    // MARK: - Device Observation
    private var deviceObserver: Any?

    override init() {
        super.init()
        setupDeviceNotifications()
    }

    deinit {
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Camera Enumeration

    func enumerateCameras() async {
        // Request camera permission if needed
        let authorized = await requestCameraAccess()
        guard authorized else {
            Logger.capture.warning("Camera access not authorized")
            return
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        let allDevices = discoverySession.devices
        let hasExternalCamera = allDevices.contains { $0.deviceType == .external }

        let devices = allDevices
            .filter { device in
                // Prefer external cameras (USB microscopes)
                // Include built-in only as fallback
                device.deviceType == .external || !hasExternalCamera
            }
            .map { CameraDevice(device: $0) }

        await MainActor.run {
            self.availableCameras = devices
            Logger.capture.info("Found \(devices.count) cameras")
        }
    }

    private func requestCameraAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Camera Selection

    func selectCamera(_ camera: CameraDevice) async {
        Logger.capture.info("Selecting camera: \(camera.name)")

        // Stop existing session
        await stopCapture()

        currentCamera = camera

        // Use best format
        guard let format = camera.bestFormat else {
            Logger.capture.error("No suitable format found for camera")
            return
        }

        currentFormat = format
        await startCapture(camera: camera, format: format)
    }

    // MARK: - Capture Session Management

    private func startCapture(camera: CameraDevice, format: CameraFormat) async {
        let session = AVCaptureSession()
        session.beginConfiguration()

        // Set session preset based on resolution
        if format.width >= 3840 {
            session.sessionPreset = .hd4K3840x2160
        } else if format.width >= 1920 {
            session.sessionPreset = .hd1920x1080
        } else if format.width >= 1280 {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        // Add input
        do {
            let input = try AVCaptureDeviceInput(device: camera.device)

            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            } else {
                Logger.capture.error("Cannot add camera input")
                return
            }
        } catch {
            Logger.capture.error("Failed to create camera input: \(error)")
            return
        }

        // Configure device
        do {
            try camera.device.lockForConfiguration()

            // Set format
            camera.device.activeFormat = format.format

            // Set frame rate
            let frameRateRange = format.format.videoSupportedFrameRateRanges
                .max(by: { $0.maxFrameRate < $1.maxFrameRate })

            if let range = frameRateRange {
                camera.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(range.maxFrameRate))
                camera.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(range.maxFrameRate))
            }

            camera.device.unlockForConfiguration()
        } catch {
            Logger.capture.error("Failed to configure camera: \(error)")
        }

        // Add output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output
        } else {
            Logger.capture.error("Cannot add video output")
            return
        }

        session.commitConfiguration()

        // Initialize frame processor
        frameProcessor = FrameProcessor(
            width: format.width,
            height: format.height,
            integrationLevel: integrationLevel
        )

        // Start session on background queue
        captureQueue.async {
            session.startRunning()
        }

        captureSession = session
        isConnected = true

        Logger.capture.info("Capture started: \(format.description)")
    }

    func stopCapture() async {
        guard let session = captureSession else { return }

        captureQueue.async {
            session.stopRunning()
        }

        if let input = currentInput {
            session.removeInput(input)
        }

        if let output = videoOutput {
            session.removeOutput(output)
        }

        captureSession = nil
        currentInput = nil
        videoOutput = nil
        isConnected = false

        Logger.capture.info("Capture stopped")
    }

    // MARK: - Frame Integration

    func setIntegrationLevel(_ level: IntegrationLevel) {
        integrationLevel = level
        frameProcessor?.setIntegrationLevel(level)
    }

    // MARK: - Device Notifications

    private func setupDeviceNotifications() {
        deviceObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.enumerateCameras()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            Task { @MainActor in
                if self?.currentCamera?.id == device.uniqueID {
                    self?.isConnected = false
                    Logger.capture.warning("Camera disconnected: \(device.localizedName)")
                }
                await self?.enumerateCameras()
            }
        }
    }

    // MARK: - FPS Calculation

    private func updateFPS() {
        let now = CFAbsoluteTimeGetCurrent()
        frameTimestamps.append(now)

        // Keep only recent timestamps
        let windowStart = now - 1.0
        frameTimestamps = frameTimestamps.filter { $0 > windowStart }

        if frameTimestamps.count >= 2 {
            let fps = Double(frameTimestamps.count - 1)
            Task { @MainActor in
                self.currentFPS = fps
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Process frame (integration, filters)
        let processedImage: CIImage
        if let processor = frameProcessor {
            processedImage = processor.process(pixelBuffer: pixelBuffer)
        } else {
            processedImage = CIImage(cvPixelBuffer: pixelBuffer)
        }

        // Update on main thread
        Task { @MainActor in
            self.latestFrame = processedImage
            self.updateFPS()
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frame dropped - this is expected behavior under load
        Logger.capture.debug("Frame dropped")
    }
}
