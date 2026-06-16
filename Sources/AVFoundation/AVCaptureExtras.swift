// Signal-facing AVCapture extras layered on top of the reusable capture surface
// in AVCaptureSurface.swift. Keep this file extension-only so AVFoundation has a
// single owner for session/input/output/connection classes.

import Foundation
import QuillFoundation
import QuartzCore
import CoreMedia
import CoreVideo
@_exported import CoreImage

#if os(Linux)

// MARK: - Orientation + device configuration

/// Apple raw values (AVCaptureVideoOrientationPortrait = 1, ...). Upstream
/// Signal adds conversion initializers in its own extensions.
public enum AVCaptureVideoOrientation: Int, Sendable {
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeRight = 3
    case landscapeLeft = 4
}

public extension AVCaptureDevice {
    enum FocusMode: Int, Sendable {
        case locked = 0
        case autoFocus = 1
        case continuousAutoFocus = 2
    }

    enum ExposureMode: Int, Sendable {
        case locked = 0
        case autoExpose = 1
        case continuousAutoExposure = 2
        case custom = 3
    }

    func isFocusModeSupported(_ focusMode: FocusMode) -> Bool {
        _ = focusMode
        return false
    }

    func isExposureModeSupported(_ exposureMode: ExposureMode) -> Bool {
        _ = exposureMode
        return false
    }

    /// Virtual multi-camera zoom switch-over points - none on Linux.
    var virtualDeviceSwitchOverVideoZoomFactors: [NSNumber] { [] }
}

public extension AVCaptureDevice.DeviceType {
    static let builtInTripleCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTripleCamera")
    static let builtInDualWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualWideCamera")
    static let builtInDualCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualCamera")
    static let builtInUltraWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInUltraWideCamera")
    static let builtInTelephotoCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTelephotoCamera")
}

// MARK: - Session extras

public extension AVCaptureSession.Preset {
    static let inputPriority = AVCaptureSession.Preset(rawValue: "AVCaptureSessionPresetInputPriority")
}

public extension AVCaptureSession {
    /// .AVCaptureSessionWasInterrupted userInfo reason codes (Apple raw values).
    enum InterruptionReason: Int, Sendable {
        case videoDeviceNotAvailableInBackground = 1
        case audioDeviceInUseByAnotherClient = 2
        case videoDeviceInUseByAnotherClient = 3
        case videoDeviceNotAvailableWithMultipleForegroundApps = 4
        case videoDeviceNotAvailableDueToSystemPressure = 5
    }

    /// iOS multitasking camera access is not supported on Linux. The setter is
    /// accepted so upstream configuration code compiles unchanged.
    var isMultitaskingCameraAccessSupported: Bool { false }
    var isMultitaskingCameraAccessEnabled: Bool {
        get { false }
        set { _ = newValue }
    }
}

// MARK: - Connections + preview layer

public enum AVCaptureVideoStabilizationMode: Int, Sendable {
    case off = 0
    case standard = 1
    case cinematic = 2
    case cinematicExtended = 3
    case previewOptimized = 4
    case auto = -1
}

public extension AVCaptureConnection {
    /// Stored for API shape only; no Linux capture backend currently consumes it.
    var videoOrientation: AVCaptureVideoOrientation {
        get { .portrait }
        set { _ = newValue }
    }

    var isVideoOrientationSupported: Bool { false }

    var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode {
        get { .off }
        set { _ = newValue }
    }

    var isVideoStabilizationSupported: Bool { false }
}

open class AVCaptureVideoPreviewLayer: CALayer {
    public var session: AVCaptureSession?
    public var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Nil until a preview pipeline exists; upstream treats that as preview setup
    /// not having completed.
    public var connection: AVCaptureConnection? { nil }

    public init(session: AVCaptureSession) {
        self.session = session
        super.init()
    }

    public override init() {
        super.init()
    }
}

// MARK: - Session notifications + userInfo keys

public extension Notification.Name {
    static let AVCaptureSessionRuntimeError = Notification.Name("AVCaptureSessionRuntimeErrorNotification")
    static let AVCaptureSessionWasInterrupted = Notification.Name("AVCaptureSessionWasInterruptedNotification")
    static let AVCaptureSessionInterruptionEnded = Notification.Name("AVCaptureSessionInterruptionEndedNotification")
    static let AVCaptureSessionDidStartRunning = Notification.Name("AVCaptureSessionDidStartRunningNotification")
    static let AVCaptureSessionDidStopRunning = Notification.Name("AVCaptureSessionDidStopRunningNotification")
}

public let AVCaptureSessionErrorKey = "AVCaptureSessionErrorKey"
public let AVCaptureSessionInterruptionReasonKey = "AVCaptureSessionInterruptionReasonKey"

// MARK: - Export extras

public let AVAssetExportPreset640x480 = "AVAssetExportPreset640x480"

/// `AVMetadataItemFilter.forSharing()` strips privacy-sensitive metadata on
/// Apple platforms. The Linux exporter is inert, so the filter is a token object.
public final class AVMetadataItemFilter: @unchecked Sendable {
    private init() {}

    public static func forSharing() -> AVMetadataItemFilter { AVMetadataItemFilter() }
}

#endif
