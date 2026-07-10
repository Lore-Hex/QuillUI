# SolderScope

A native macOS application for USB microscope viewing, optimized for soldering and electronics inspection.

## Overview

SolderScope provides a low-latency live view with smooth zoom/pan controls, scale bar overlays with one-time calibration, and essential capture features—all designed for bench work with USB microscopes.

![SolderScope Screenshot](SolderScope.png)

## Features

### Core Features
- **Live View** — Low-latency video feed from USB microscopes
- **Zoom/Pan** — Scroll wheel zoom (around cursor), click-drag pan, double-click reset
- **Scale Bar** — Calibrated overlay showing real-world measurements
- **Frame Integration** — Average 1-16 frames for noise reduction on static scenes

### Capture Features
- **Freeze Frame** — Pause live view for inspection
- **Snapshots** — Save current view as PNG with optional overlays
- **Video Recording** — Record sessions with H.264/HEVC encoding

### Quality of Life
- **Auto Camera Selection** — Remembers your microscope
- **Per-Resolution Calibration** — Calibration stored per camera and resolution
- **Keyboard Shortcuts** — Full keyboard control for bench use

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Freeze/unfreeze frame |
| `S` | Take snapshot |
| `R` | Toggle recording |
| `I` | Cycle integration (1→2→4→8→16→1) |
| `B` | Toggle scale bar |
| `0` | Reset zoom/pan |
| `Esc` | Cancel calibration/measurement mode |

## Calibration

SolderScope supports one-time calibration for accurate scale bars:

1. Enable scale bar (`B` key)
2. If uncalibrated, enter calibration mode
3. Draw a line across a known distance (e.g., 0402 component = 1.0mm, header pitch = 2.54mm)
4. Enter the known length
5. Calibration is saved per camera and resolution

## Requirements

- macOS 14.0+ (Sonoma or later)
- USB microscope (UVC-compatible)
- Camera access permission

## Installation

### From DMG (Recommended)

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag SolderScope to Applications
3. **First launch:** Right-click the app and select "Open" (see note below)

### Build from Source

```bash
# Clone and build
git clone https://github.com/rjwalters/SolderScope.git
cd SolderScope
./bundle.sh

# Install
cp -r .build/release/SolderScope.app /Applications/
```

### Code Signing Note

SolderScope is not signed with an Apple Developer ID certificate or notarized. On first launch, macOS Gatekeeper will block the app.

**To open an unsigned app:**
1. Right-click (or Control-click) on SolderScope.app
2. Select "Open" from the context menu
3. Click "Open" in the dialog that appears

You only need to do this once. After the first launch, macOS remembers your choice.

**Why isn't it signed?**
Code signing requires a paid Apple Developer account ($99/year). For an open-source project, we've chosen to keep it free and let users bypass Gatekeeper manually.

## Architecture

```
SolderScope/
├── App/
│   ├── SolderScopeApp.swift      # App entry point
│   └── ContentView.swift          # Main window layout
├── Capture/
│   ├── CaptureManager.swift       # AVCaptureSession management
│   ├── CameraDevice.swift         # Camera enumeration/selection
│   └── FrameProcessor.swift       # Frame pipeline (integration, filters)
├── Renderer/
│   ├── MicroscopeView.swift       # Main rendering view
│   ├── ViewTransform.swift        # Zoom/pan transform state
│   └── OverlayRenderer.swift      # Scale bar, HUD, annotations
├── Calibration/
│   ├── CalibrationManager.swift   # Calibration storage/retrieval
│   ├── CalibrationView.swift      # Calibration wizard UI
│   └── ScaleBarCalculator.swift   # Scale bar sizing logic
├── Recording/
│   ├── RecordingManager.swift     # AVAssetWriter pipeline
│   └── SnapshotManager.swift      # PNG/TIFF export
├── Persistence/
│   └── SettingsStore.swift        # UserDefaults wrapper
└── Utilities/
    ├── CoordinateTransform.swift  # Image ↔ View coordinate mapping
    └── Constants.swift            # App-wide constants
```

### Coordinate Spaces

- **Image Space:** Pixel coordinates in captured frame (origin top-left)
- **View Space:** Points in the window
- Transform `T` maps image → view (scale + translation + letterbox fit)
- Mouse interactions use `T⁻¹` to map view → image coordinates

### Calibration Data Model

```swift
struct Calibration: Codable {
    let cameraID: String        // Unique device identifier
    let width: Int              // Frame width
    let height: Int             // Frame height
    let micronsPerPixel: Double // Calibration value
}
```

## Non-Goals (v1)

- Hardware automation (motorized stages, focus)
- Complex image processing (denoising, registration)
- Cross-platform support
- Audio recording

## Contributing

1. Check the [Issues](../../issues) for open tasks
2. Follow the milestone structure
3. Keep PRs focused on single features/fixes

## License

MIT License - See [LICENSE](LICENSE) for details
