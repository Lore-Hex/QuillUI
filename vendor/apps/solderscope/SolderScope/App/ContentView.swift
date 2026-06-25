import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // Main microscope view
            MicroscopeView(
                captureManager: appState.captureManager,
                transform: $appState.viewTransform,
                isFrozen: appState.isFrozen
            )
            .ignoresSafeArea()

            // Overlays
            VStack {
                // Top toolbar
                ToolbarView()
                    .padding(.top, 8)

                Spacer()

                // Bottom HUD and scale bar
                HStack(alignment: .bottom) {
                    if appState.isScaleBarVisible {
                        ScaleBarView(
                            calibrationManager: appState.calibrationManager,
                            cameraID: appState.selectedCamera?.id ?? "",
                            resolution: appState.currentResolution,
                            zoomFactor: appState.viewTransform.zoomFactor,
                            onDelete: { appState.deleteCurrentCalibration() }
                        )
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                    }

                    Spacer()

                    HUDView()
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                }
            }

            // Calibration overlay
            if appState.isCalibrating {
                CalibrationOverlay()
            }

            // Recording indicator
            if appState.isRecording {
                RecordingIndicator(duration: appState.recordingDuration)
            }

            // Frozen indicator
            if appState.isFrozen {
                FrozenIndicator()
            }

            // No camera message
            if !appState.isCameraConnected && appState.availableCameras.isEmpty {
                NoCameraView()
            }
        }
        .background(Color.black)
        .onAppear {
            Task {
                await appState.captureManager.enumerateCameras()
                if appState.selectedCamera == nil,
                   let firstCamera = appState.availableCameras.first {
                    appState.selectCamera(firstCamera)
                }
            }
        }
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Camera selector
            CameraPicker(
                cameras: appState.availableCameras,
                selection: Binding(
                    get: { appState.selectedCamera },
                    set: { if let camera = $0 { appState.selectCamera(camera) } }
                )
            )

            Divider()
                .frame(height: 24)

            // Integration level
            Button(action: { appState.cycleIntegration() }) {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                    Text("\(appState.integrationLevel.rawValue)x")
                        .monospacedDigit()
                }
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Frame integration (I)")

            // Scale bar toggle
            Button(action: { appState.toggleScaleBar() }) {
                Image(systemName: appState.isScaleBarVisible ? "ruler.fill" : "ruler")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: appState.isScaleBarVisible))
            .help("Toggle scale bar (B)")

            Divider()
                .frame(height: 24)

            // Flip horizontal
            Button(action: { appState.flipHorizontal() }) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: appState.viewTransform.isFlippedHorizontally))
            .help("Flip horizontal (H)")

            // Flip vertical
            Button(action: { appState.flipVertical() }) {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: appState.viewTransform.isFlippedVertically))
            .help("Flip vertical (V)")

            // Rotate clockwise
            Button(action: { appState.rotateClockwise() }) {
                HStack(spacing: 2) {
                    Image(systemName: "rotate.right")
                    Text("\(appState.viewTransform.rotation.rawValue)°")
                        .font(.system(size: 10))
                        .monospacedDigit()
                }
            }
            .buttonStyle(ToolbarButtonStyle(isActive: appState.viewTransform.rotation != .none))
            .help("Rotate 90° clockwise (])")

            Divider()
                .frame(height: 24)

            // Freeze
            Button(action: { appState.toggleFreeze() }) {
                Image(systemName: appState.isFrozen ? "pause.fill" : "pause")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: appState.isFrozen))
            .help("Freeze frame (Space)")

            // Snapshot
            Button(action: { appState.takeSnapshot() }) {
                Image(systemName: "camera")
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Take snapshot (S)")

            // Record
            Button(action: { appState.toggleRecording() }) {
                Image(systemName: appState.isRecording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: appState.isRecording, activeColor: .red))
            .help("Toggle recording (R)")

            Spacer()

            // Reset view
            Button(action: { appState.resetView() }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Reset view (0)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }
}

// MARK: - Camera Picker

struct CameraPicker: View {
    let cameras: [CameraDevice]
    @Binding var selection: CameraDevice?

    var body: some View {
        Menu {
            ForEach(cameras) { camera in
                Button(action: { selection = camera }) {
                    HStack {
                        Text(camera.name)
                        if camera.id == selection?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if cameras.isEmpty {
                Text("No cameras found")
                    .foregroundColor(.secondary)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "camera.fill")
                Text(selection?.name ?? "No Camera")
                    .lineLimit(1)
                    .frame(maxWidth: 150)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - HUD View

struct HUDView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(String(format: "%.1f FPS", appState.currentFPS))
            Text("\(Int(appState.currentResolution.width))×\(Int(appState.currentResolution.height))")
            Text(String(format: "%.1fx", appState.viewTransform.zoomFactor))
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Indicators

struct FrozenIndicator: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("FROZEN")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
            Spacer()
        }
    }
}

struct RecordingIndicator: View {
    let duration: TimeInterval
    @State private var isBlinking = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(isBlinking ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isBlinking)

                    Text("REC")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))

                    Text(formatDuration(duration))
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 16)
                .padding(.bottom, 16)

                Spacer()
            }
        }
        .onAppear { isBlinking = true }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct NoCameraView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Camera Connected")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Connect a USB microscope to begin")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Button Style

struct ToolbarButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var activeColor: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundColor(isActive ? activeColor : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.3) : Color.clear)
            )
    }
}
