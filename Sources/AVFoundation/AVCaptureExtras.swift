// AVCapture extras that sit on top of the canonical capture graph in
// AVCaptureSurface.swift. Keep that file as the single owner of session/input/
// output/connection types so V4L2-backed capture and inert fallback behavior
// share one ABI surface.

import Foundation
import QuartzCore
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

// MARK: - AVCaptureDevice capture configuration

public extension AVCaptureDevice {
    public enum FocusMode: Int, Sendable {
        case locked = 0
        case autoFocus = 1
        case continuousAutoFocus = 2
    }

    public enum ExposureMode: Int, Sendable {
        case locked = 0
        case autoExpose = 1
        case continuousAutoExposure = 2
        case custom = 3
    }

    // DiscoverySession (with init(deviceTypes:mediaType:position:)) is declared
    // in AVFoundation.swift — one owner. A duplicate here caused "invalid
    // redeclaration of 'DiscoverySession'".
    public func isFocusModeSupported(_ focusMode: FocusMode) -> Bool { false }
    public func isExposureModeSupported(_ exposureMode: ExposureMode) -> Bool { false }

    /// Virtual multi-camera zoom switch-over points — none on Linux.
    public var virtualDeviceSwitchOverVideoZoomFactors: [NSNumber] { [] }
}

public extension AVCaptureDevice.DeviceType {
    static let builtInTripleCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTripleCamera")
    static let builtInDualWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualWideCamera")
    static let builtInDualCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualCamera")
    static let builtInUltraWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInUltraWideCamera")
    static let builtInTelephotoCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTelephotoCamera")
}

// MARK: - Connections + preview layer + video stabilization

public enum AVCaptureVideoStabilizationMode: Int, Sendable {
    case off = 0
    case standard = 1
    case cinematic = 2
    case cinematicExtended = 3
    case previewOptimized = 4
    case auto = -1
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
