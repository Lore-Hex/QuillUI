import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Camera State
    @Published var selectedCamera: CameraDevice?
    @Published var availableCameras: [CameraDevice] = []
    @Published var isCameraConnected: Bool = false

    // MARK: - View State
    @Published var isFrozen: Bool = false
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0

    // MARK: - Scale Bar
    @Published var isScaleBarVisible: Bool = false
    @Published var isCalibrating: Bool = false

    // MARK: - Frame Integration
    @Published var integrationLevel: IntegrationLevel = .one

    // MARK: - Performance
    @Published var currentFPS: Double = 0
    @Published var currentResolution: CGSize = .zero

    // MARK: - Managers
    let captureManager: CaptureManager
    let calibrationManager: CalibrationManager
    let recordingManager: RecordingManager
    let snapshotManager: SnapshotManager
    let settingsStore: SettingsStore

    // MARK: - View Transform
    @Published var viewTransform: ViewTransform = ViewTransform()

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.settingsStore = SettingsStore()
        self.calibrationManager = CalibrationManager(settingsStore: settingsStore)
        self.captureManager = CaptureManager()
        self.recordingManager = RecordingManager()
        self.snapshotManager = SnapshotManager()

        setupBindings()
        loadSettings()
    }

    private func setupBindings() {
        // Bind capture manager state to app state
        captureManager.$availableCameras
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableCameras)

        captureManager.$currentFPS
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentFPS)

        captureManager.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCameraConnected)

        // Update recording duration
        recordingManager.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)

        recordingManager.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
    }

    private func loadSettings() {
        isScaleBarVisible = settingsStore.isScaleBarVisible
        integrationLevel = settingsStore.integrationLevel

        if let cameraID = settingsStore.selectedCameraID {
            // Will select camera after enumeration completes
            Task {
                await captureManager.enumerateCameras()
                if let camera = availableCameras.first(where: { $0.id == cameraID }) {
                    selectCamera(camera)
                }
            }
        }
    }

    // MARK: - Actions

    func selectCamera(_ camera: CameraDevice) {
        selectedCamera = camera
        settingsStore.selectedCameraID = camera.id
        Task {
            await captureManager.selectCamera(camera)
            if let format = camera.bestFormat {
                currentResolution = CGSize(width: format.width, height: format.height)
            }
        }
    }

    func toggleFreeze() {
        isFrozen.toggle()
        Logger.app.debug("Freeze toggled: \(self.isFrozen)")
    }

    func toggleScaleBar() {
        if !isScaleBarVisible {
            // Turning on - check if calibration exists
            if let camera = selectedCamera,
               calibrationManager.getCalibration(for: camera.id, resolution: currentResolution) == nil {
                // Need to calibrate first
                isCalibrating = true
            }
        }
        isScaleBarVisible.toggle()
        settingsStore.isScaleBarVisible = isScaleBarVisible
        Logger.app.debug("Scale bar toggled: \(self.isScaleBarVisible)")
    }

    func cycleIntegration() {
        integrationLevel = integrationLevel.next
        settingsStore.integrationLevel = integrationLevel
        captureManager.setIntegrationLevel(integrationLevel)
        Logger.app.debug("Integration level: \(self.integrationLevel.rawValue)")
    }

    func takeSnapshot() {
        Task {
            await snapshotManager.captureSnapshot(
                from: captureManager,
                transform: viewTransform,
                includeOverlays: true
            )
        }
        Logger.app.info("Snapshot captured")
    }

    func toggleRecording() {
        if isRecording {
            recordingManager.stopRecording()
        } else {
            Task {
                await recordingManager.startRecording(
                    from: captureManager,
                    resolution: currentResolution
                )
            }
        }
    }

    func resetView() {
        viewTransform.reset()
        Logger.app.debug("View reset")
    }

    func flipHorizontal() {
        viewTransform.toggleHorizontalFlip()
        Logger.app.debug("Horizontal flip: \(self.viewTransform.isFlippedHorizontally)")
    }

    func flipVertical() {
        viewTransform.toggleVerticalFlip()
        Logger.app.debug("Vertical flip: \(self.viewTransform.isFlippedVertically)")
    }

    func rotateClockwise() {
        viewTransform.rotateClockwise()
        Logger.app.debug("Rotation: \(self.viewTransform.rotation.rawValue)°")
    }

    func cancelCalibration() {
        isCalibrating = false
        if calibrationManager.getCalibration(for: selectedCamera?.id ?? "", resolution: currentResolution) == nil {
            // No calibration exists, turn off scale bar
            isScaleBarVisible = false
            settingsStore.isScaleBarVisible = false
        }
    }

    func completeCalibration(micronsPerPixel: Double) {
        guard let camera = selectedCamera else { return }

        let calibration = Calibration(
            cameraID: camera.id,
            width: Int(currentResolution.width),
            height: Int(currentResolution.height),
            micronsPerPixel: micronsPerPixel
        )

        calibrationManager.saveCalibration(calibration)
        isCalibrating = false
        Logger.app.info("Calibration saved: \(micronsPerPixel) µm/px")
    }

    func deleteCurrentCalibration() {
        guard let camera = selectedCamera else { return }
        calibrationManager.deleteCalibration(for: camera.id, resolution: currentResolution)
        isScaleBarVisible = false
        settingsStore.isScaleBarVisible = false
        Logger.app.info("Calibration deleted")
    }
}

// MARK: - Integration Level

enum IntegrationLevel: Int, CaseIterable, Codable {
    case one = 1
    case two = 2
    case four = 4
    case eight = 8
    case sixteen = 16

    var next: IntegrationLevel {
        switch self {
        case .one: return .two
        case .two: return .four
        case .four: return .eight
        case .eight: return .sixteen
        case .sixteen: return .one
        }
    }
}
