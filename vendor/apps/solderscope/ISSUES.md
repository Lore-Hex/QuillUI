# GitHub Issues to Create

This file contains pre-formatted issues ready for GitHub. Create these issues to populate your project board.

---

## Milestone 0: Project Scaffolding

### Issue: Create Xcode project and configure build settings
**Labels:** `milestone:0-scaffolding`, `type:feature`, `priority:high`

Create new macOS app project with SwiftUI lifecycle.

**Tasks:**
- [ ] Create new macOS app project (SwiftUI lifecycle)
- [ ] Configure deployment target (macOS 13.0+)
- [ ] Set up code signing and entitlements
- [ ] Add camera usage description to Info.plist
- [ ] Configure sandbox entitlements for camera access

---

### Issue: Set up project folder structure
**Labels:** `milestone:0-scaffolding`, `type:feature`

Organize codebase into logical modules.

**Tasks:**
- [ ] Create folder structure (Capture, Renderer, Calibration, Recording, Persistence, Utilities)
- [ ] Add placeholder files for core modules
- [ ] Set up basic logging utility (os.log)
- [ ] Create Constants.swift with app-wide values

---

### Issue: Implement basic app shell with menus and shortcuts
**Labels:** `milestone:0-scaffolding`, `type:feature`

Wire up the basic app structure.

**Tasks:**
- [ ] Implement main window with placeholder view
- [ ] Add menu bar items (File, Edit, View, Window, Help)
- [ ] Wire up keyboard shortcuts (Space, S, R, I, B, 0, Esc)
- [ ] Create basic SettingsStore for UserDefaults

---

## Milestone 1: Camera Capture + Live Preview

### Issue: Implement camera enumeration and selection
**Labels:** `milestone:1-capture`, `type:feature`, `priority:high`

Enumerate available cameras and allow user selection.

**Tasks:**
- [ ] Implement CameraDevice model (id, name, formats)
- [ ] Create CaptureManager class with AVCaptureSession
- [ ] Enumerate available video devices (AVCaptureDevice.DiscoverySession)
- [ ] Filter to external cameras (exclude FaceTime, etc.)
- [ ] Handle camera permission request flow

---

### Issue: Configure capture session for optimal quality
**Labels:** `milestone:1-capture`, `type:feature`, `priority:high`

Set up AVCaptureSession with best format and frame handling.

**Tasks:**
- [ ] Select best format (highest resolution, highest fps)
- [ ] Configure pixel format (BGRA preferred)
- [ ] Create dedicated capture queue (background)
- [ ] Implement AVCaptureVideoDataOutputSampleBufferDelegate
- [ ] Handle CMSampleBuffer → CVPixelBuffer conversion

---

### Issue: Create MicroscopeView for frame display
**Labels:** `milestone:1-capture`, `type:feature`, `priority:high`

Implement the main rendering view using Core Image.

**Tasks:**
- [ ] Create MicroscopeView (NSViewRepresentable wrapping CIImage rendering)
- [ ] Implement CIContext for GPU-backed rendering
- [ ] Display frames with minimal latency
- [ ] Implement frame dropping under load (prefer latest frame)

---

### Issue: Add camera selection UI
**Labels:** `milestone:1-capture`, `type:feature`

Allow user to select and switch cameras.

**Tasks:**
- [ ] Add camera selector dropdown to toolbar
- [ ] Show current camera name in window title or HUD
- [ ] Handle camera connect/disconnect events gracefully
- [ ] Show error state when no camera available

---

### Issue: Implement FPS monitoring and overlay
**Labels:** `milestone:1-capture`, `type:feature`

Track and display frame rate for performance monitoring.

**Tasks:**
- [ ] Implement FPS counter
- [ ] Add optional FPS overlay (HUD)
- [ ] Log frame timing for performance analysis
- [ ] Verify 30+ minute stability

---

## Milestone 2: Zoom/Pan Controls

### Issue: Implement ViewTransform for zoom and pan state
**Labels:** `milestone:2-zoom-pan`, `type:feature`, `priority:high`

Create the transform model that manages view state.

**Tasks:**
- [ ] Create ViewTransform model (zoomFactor, panOffset)
- [ ] Implement base fit-to-window transform (letterboxing)
- [ ] Combine transforms: fit → zoom → pan
- [ ] Add rotation/flip state (for future use)

---

### Issue: Implement scroll wheel zoom around cursor
**Labels:** `milestone:2-zoom-pan`, `type:feature`, `priority:high`

Zoom in/out centered on mouse position.

**Tasks:**
- [ ] Handle scroll wheel events
- [ ] Implement zoom around cursor position
- [ ] Set min/max zoom limits (0.1x to 20x suggested)
- [ ] Smooth zoom animation (optional)

---

### Issue: Implement click-drag panning
**Labels:** `milestone:2-zoom-pan`, `type:feature`, `priority:high`

Pan the view by clicking and dragging.

**Tasks:**
- [ ] Handle mouse drag events
- [ ] Update panOffset during drag
- [ ] Constrain pan to keep image partially visible
- [ ] Change cursor to grabbing hand during drag

---

### Issue: Implement view reset (double-click and keyboard)
**Labels:** `milestone:2-zoom-pan`, `type:feature`

Reset zoom and pan to default view.

**Tasks:**
- [ ] Implement double-click to reset view
- [ ] Wire `0` key to reset
- [ ] Animate reset transition (optional)

---

### Issue: Handle window resize correctly
**Labels:** `milestone:2-zoom-pan`, `type:feature`

Maintain proper view when window is resized.

**Tasks:**
- [ ] Recalculate fit transform on resize
- [ ] Maintain view center (or cursor position) during resize
- [ ] Handle aspect ratio changes correctly

---

### Issue: Create coordinate transform utilities
**Labels:** `milestone:2-zoom-pan`, `type:feature`

Utility functions for coordinate space conversion.

**Tasks:**
- [ ] Implement CoordinateTransform utility
- [ ] Add viewToImage() function
- [ ] Add imageToView() function
- [ ] Unit tests for coordinate transforms

---

## Milestone 3: Scale Bar + Calibration

### Issue: Implement calibration data model and storage
**Labels:** `milestone:3-scale-bar`, `type:feature`, `priority:high`

Store and retrieve calibration data per camera/resolution.

**Tasks:**
- [ ] Define Calibration struct (cameraID, width, height, micronsPerPixel)
- [ ] Implement CalibrationManager for storage/retrieval
- [ ] Store calibrations in UserDefaults or JSON file
- [ ] Key calibrations by camera+resolution

---

### Issue: Add scale bar toggle
**Labels:** `milestone:3-scale-bar`, `type:feature`

Toggle scale bar visibility.

**Tasks:**
- [ ] Add scale bar toggle button to toolbar
- [ ] Wire `B` key shortcut
- [ ] Store toggle state in SettingsStore
- [ ] Default to OFF

---

### Issue: Implement calibration mode UI
**Labels:** `milestone:3-scale-bar`, `type:feature`, `priority:high`

Allow user to draw calibration line.

**Tasks:**
- [ ] Detect missing calibration when scale bar enabled
- [ ] Show calibration mode overlay/prompt
- [ ] Implement line drawing tool (start point, end point)
- [ ] Show line preview during drawing
- [ ] Display line length in pixels

---

### Issue: Implement calibration input dialog
**Labels:** `milestone:3-scale-bar`, `type:feature`

Let user enter known length for calibration.

**Tasks:**
- [ ] Show length input dialog after line drawn
- [ ] Add preset buttons (0402=1.0mm, 0603=1.6mm, header=2.54mm, custom)
- [ ] Compute micronsPerPixel from line length and user input
- [ ] Save calibration to CalibrationManager
- [ ] Handle cancel (Esc key)

---

### Issue: Implement scale bar calculation
**Labels:** `milestone:3-scale-bar`, `type:feature`

Calculate appropriate scale bar length for display.

**Tasks:**
- [ ] Create ScaleBarCalculator utility
- [ ] Calculate effective µm per screen pixel (accounting for zoom)
- [ ] Select "nice" bar length from set [10,20,50,100,200,500,1000,2000,5000] µm
- [ ] Target bar width 120-250 screen pixels
- [ ] Format label (µm, mm, or cm as appropriate)

---

### Issue: Render scale bar overlay
**Labels:** `milestone:3-scale-bar`, `type:feature`

Draw scale bar on the view.

**Tasks:**
- [ ] Create OverlayRenderer for scale bar
- [ ] Position scale bar (bottom-left or bottom-right)
- [ ] Render bar with contrasting outline/shadow for visibility
- [ ] Update bar on zoom changes
- [ ] Add "Recalibrate..." menu item

---

## Milestone 4: Snapshots + Freeze Frame

### Issue: Implement freeze frame functionality
**Labels:** `milestone:4-snapshot`, `type:feature`, `priority:high`

Pause live view for inspection.

**Tasks:**
- [ ] Add freeze state to app model
- [ ] Wire Space key to toggle freeze
- [ ] Add freeze button to toolbar
- [ ] Show visual indicator when frozen (border, icon, or tint)
- [ ] Capture frame continues in background (for buffer)

---

### Issue: Implement snapshot capture
**Labels:** `milestone:4-snapshot`, `type:feature`, `priority:high`

Capture current view as image.

**Tasks:**
- [ ] Implement SnapshotManager
- [ ] Capture current displayed frame (with current transforms)
- [ ] Option: capture with or without overlays
- [ ] Default: include overlays (scale bar is useful)

---

### Issue: Implement snapshot export
**Labels:** `milestone:4-snapshot`, `type:feature`

Save snapshots to disk.

**Tasks:**
- [ ] Generate filename: SolderScope_YYYYMMDD_HHMMSS.png
- [ ] Determine save location (Pictures folder or configurable)
- [ ] Save as PNG (fast, lossless enough)
- [ ] Optional: save as TIFF for truly lossless
- [ ] Wire `S` key shortcut
- [ ] Show save confirmation (subtle HUD or sound)

---

### Issue: Add clipboard support for snapshots
**Labels:** `milestone:4-snapshot`, `type:enhancement`

Copy snapshots to clipboard.

**Tasks:**
- [ ] Add "Copy to Clipboard" option
- [ ] Copy current snapshot to pasteboard
- [ ] Optional keyboard shortcut (Cmd+C when frozen?)

---

## Milestone 5: Video Recording

### Issue: Implement recording setup with AVAssetWriter
**Labels:** `milestone:5-recording`, `type:feature`, `priority:high`

Configure video recording pipeline.

**Tasks:**
- [ ] Implement RecordingManager with AVAssetWriter
- [ ] Configure video codec (H.264 default, HEVC optional)
- [ ] Match input resolution and frame rate
- [ ] Set output location (Movies folder or configurable)
- [ ] Generate filename: SolderScope_YYYYMMDD_HHMMSS.mov

---

### Issue: Implement frame writing pipeline
**Labels:** `milestone:5-recording`, `type:feature`, `priority:high`

Write frames to video file.

**Tasks:**
- [ ] Create AVAssetWriterInput for video
- [ ] Create pixel buffer adaptor
- [ ] Handle frame timing (presentation timestamps)
- [ ] Write frames from capture pipeline
- [ ] Handle frame drops gracefully (log, don't crash)

---

### Issue: Add recording UI controls
**Labels:** `milestone:5-recording`, `type:feature`

Recording button and status display.

**Tasks:**
- [ ] Add record button to toolbar
- [ ] Wire `R` key shortcut
- [ ] Show recording indicator (red dot, pulsing)
- [ ] Display elapsed time counter
- [ ] Stop recording on button press or `R` key

---

### Issue: Add recording options
**Labels:** `milestone:5-recording`, `type:enhancement`

Configure recording behavior.

**Tasks:**
- [ ] Choose: record raw feed vs processed (with overlays)
- [ ] Default: processed (what user sees)
- [ ] Settings UI for recording preferences

---

### Issue: Ensure recording reliability
**Labels:** `milestone:5-recording`, `type:feature`

Handle edge cases gracefully.

**Tasks:**
- [ ] Handle disk space warnings
- [ ] Handle camera disconnect during recording
- [ ] Ensure file is properly finalized on stop
- [ ] Test 5+ minute recordings
- [ ] Verify playback in QuickTime

---

## Milestone 6: Frame Integration

### Issue: Implement frame ring buffer
**Labels:** `milestone:6-integration`, `type:feature`, `priority:high`

Buffer for frame averaging.

**Tasks:**
- [ ] Implement ring buffer for N frames
- [ ] Store frames as floating-point accumulators (or 16-bit)
- [ ] Handle buffer initialization and wraparound
- [ ] Clear buffer on integration N change

---

### Issue: Implement frame averaging (CPU)
**Labels:** `milestone:6-integration`, `type:feature`, `priority:high`

Average frames for noise reduction.

**Tasks:**
- [ ] Implement running sum/average
- [ ] Start with CPU implementation (Accelerate/vImage)
- [ ] Convert accumulated result back to display format
- [ ] Profile performance at 1080p and 4K

---

### Issue: Add integration UI controls
**Labels:** `milestone:6-integration`, `type:feature`

Control integration level.

**Tasks:**
- [ ] Add integration cycle button to toolbar
- [ ] Display current N value
- [ ] Wire `I` key shortcut
- [ ] Cycle: 1 → 2 → 4 → 8 → 16 → 1
- [ ] Default: 1 (lowest latency)

---

### Issue: Implement motion-aware integration (optional)
**Labels:** `milestone:6-integration`, `type:enhancement`

Reduce integration during user interaction.

**Tasks:**
- [ ] Detect user interaction (pan/zoom)
- [ ] Temporarily drop to N=1 during motion
- [ ] Return to selected N after interaction ends
- [ ] Make behavior optional in settings

---

### Issue: GPU-accelerate integration if needed
**Labels:** `milestone:6-integration`, `type:enhancement`

Move to GPU if CPU can't keep up.

**Tasks:**
- [ ] Profile CPU implementation at high resolutions
- [ ] If needed: implement Core Image or Metal version
- [ ] Maintain same API for swappable implementations

---

## Milestone 7: Measurement Tools

### Issue: Implement measurement mode
**Labels:** `milestone:7-measurement`, `type:feature`

Enter/exit measurement drawing mode.

**Tasks:**
- [ ] Add measurement tool button
- [ ] Enter/exit measurement mode
- [ ] Show cursor change in measurement mode

---

### Issue: Implement line measurements
**Labels:** `milestone:7-measurement`, `type:feature`

Draw and measure distances.

**Tasks:**
- [ ] Draw measurement lines (separate from calibration)
- [ ] Calculate length using calibration data
- [ ] Display length label on line (µm/mm/in)
- [ ] Support multiple lines

---

### Issue: Add measurement management
**Labels:** `milestone:7-measurement`, `type:feature`

Select and delete measurements.

**Tasks:**
- [ ] Select existing measurements (click)
- [ ] Delete measurements (Delete key or context menu)
- [ ] Clear all measurements option
- [ ] Optional: persist measurements with session

---

## How to Create Issues

### Using GitHub CLI (gh)

```bash
# Create a milestone
gh api repos/{owner}/{repo}/milestones -f title="Milestone 0: Scaffolding" -f description="App runs, shows empty canvas, menus and shortcuts wired."

# Create an issue
gh issue create --title "Create Xcode project and configure build settings" --body "..." --label "milestone:0-scaffolding,type:feature,priority:high"
```

### Bulk Issue Creation Script

Save as `create-issues.sh` and run after creating the repo:

```bash
#!/bin/bash

# Create labels first
gh label create "milestone:0-scaffolding" --color "0E8A16"
gh label create "milestone:1-capture" --color "1D76DB"
gh label create "milestone:2-zoom-pan" --color "5319E7"
gh label create "milestone:3-scale-bar" --color "FBCA04"
gh label create "milestone:4-snapshot" --color "B60205"
gh label create "milestone:5-recording" --color "006B75"
gh label create "milestone:6-integration" --color "D93F0B"
gh label create "milestone:7-measurement" --color "C2E0C6"
gh label create "type:feature" --color "A2EEEF"
gh label create "type:bug" --color "D73A4A"
gh label create "type:enhancement" --color "84B6EB"
gh label create "priority:high" --color "B60205"
gh label create "priority:medium" --color "FBCA04"
gh label create "priority:low" --color "0E8A16"

# Then create issues using the templates above
```
