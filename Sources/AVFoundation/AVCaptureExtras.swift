// AVCapture* surface — Linux shim for SignalUI's camera flows:
//   • ScanQRCodeViewController.swift (QRCodeScanner / QRCodeScanOutput /
//     QRCodeScanPreviewView / QRCodeSampleBufferScanner): AVCaptureSession,
//     AVCaptureDevice configuration + DiscoverySession, AVCaptureDeviceInput,
//     AVCaptureVideoDataOutput + its sample-buffer delegate,
//     AVCaptureVideoPreviewLayer, AVCaptureConnection,
//     AVCaptureVideoOrientation, and the session notifications/userInfo keys.
//   • UIViewController+Permissions.swift: AVCaptureDevice.authorizationStatus /
//     requestAccess (AVAuthorizationStatus).
//   • Attachments/PreviewableAttachment.swift: AVMetadataItemFilter.forSharing()
//     + AVAssetExportPreset640x480 (exportAsync is upstream's own extension over
//     the inert export surface in AVFoundation.swift).
//
// HONEST STATUS: there is no camera (or capture backend) on Linux, so this is
// config-storing and INERT: sessions record inputs/outputs/preset and flip
// `isRunning`, but no frames ever flow; the sample-buffer delegate is never
// called; discovery sessions find no devices (so upstream's
// selectCaptureDevice() throws and scanning reports failure); authorization is
// `.denied` so permission prompts resolve to "unavailable" without lying about
// a camera that does not exist.
//
// Apple re-exports CoreImage through AVFoundation (ScanQRCodeViewController
// casts Vision's barcodeDescriptor to CIQRCodeDescriptor with only
// `import AVFoundation` in scope); mirror that so the upstream file resolves.

import Foundation
import QuillFoundation
import QuartzCore
import CoreMedia
import CoreVideo
@_exported import CoreImage

#if os(Linux)

// MARK: - Orientation + authorization

/// Apple raw values (AVCaptureVideoOrientationPortrait = 1, …). Upstream
/// SignalUI adds `init?(deviceOrientation:)` / `init?(interfaceOrientation:)`
/// in its own extension.
public enum AVCaptureVideoOrientation: Int, Sendable {
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeRight = 3
    case landscapeLeft = 4
}

// MARK: - AVCaptureDevice capture configuration

extension AVCaptureDevice {
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

    public func isFocusModeSupported(_ focusMode: FocusMode) -> Bool { false }
    public func isExposureModeSupported(_ exposureMode: ExposureMode) -> Bool { false }

    /// Virtual multi-camera zoom switch-over points — none on Linux.
    public var virtualDeviceSwitchOverVideoZoomFactors: [NSNumber] { [] }
}

extension AVCaptureDevice.DeviceType {
    public static let builtInTripleCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTripleCamera")
    public static let builtInDualWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualWideCamera")
    public static let builtInDualCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualCamera")
    public static let builtInUltraWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInUltraWideCamera")
    public static let builtInTelephotoCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTelephotoCamera")
}

// MARK: - AVCaptureSession extras

extension AVCaptureSession.Preset {
    public static let inputPriority = AVCaptureSession.Preset(rawValue: "AVCaptureSessionPresetInputPriority")
}

extension AVCaptureSession {
    /// `.AVCaptureSessionWasInterrupted` userInfo reason codes (Apple raw values).
    public enum InterruptionReason: Int, Sendable {
        case videoDeviceNotAvailableInBackground = 1
        case audioDeviceInUseByAnotherClient = 2
        case videoDeviceInUseByAnotherClient = 3
        case videoDeviceNotAvailableWithMultipleForegroundApps = 4
        case videoDeviceNotAvailableDueToSystemPressure = 5
    }

    /// iOS 16 multitasking camera access — never supported on Linux; the
    /// enabled flag is accepted only so upstream's availability branch compiles.
    public var isMultitaskingCameraAccessSupported: Bool { false }
    public var isMultitaskingCameraAccessEnabled: Bool {
        get { false }
        set { _ = newValue }
    }
}

// MARK: - Connections + video stabilization

public enum AVCaptureVideoStabilizationMode: Int, Sendable {
    case off = 0
    case standard = 1
    case cinematic = 2
    case cinematicExtended = 3
    case previewOptimized = 4
    case auto = -1
}

extension AVCaptureConnection {
    /// Orientation/stabilization are stored for shape fidelity; nothing
    /// consumes them (and `isVideoOrientationSupported` is honestly false).
    public var videoOrientation: AVCaptureVideoOrientation {
        get { .portrait }
        set { _ = newValue }
    }
    public var isVideoOrientationSupported: Bool { false }

    public var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode {
        get { .off }
        set { _ = newValue }
    }
    public var isVideoStabilizationSupported: Bool { false }
}

// MARK: - Preview layer

open class AVCaptureVideoPreviewLayer: CALayer {
    public var session: AVCaptureSession?
    public var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Nil until a capture pipeline exists — i.e. always, on Linux; upstream
    /// treats that as "preview hasn't completed setup".
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

// MARK: - Export extras (PreviewableAttachment)

public let AVAssetExportPreset640x480 = "AVAssetExportPreset640x480"

/// `AVMetadataItemFilter.forSharing()` strips privacy-sensitive metadata on
/// export. The Linux exporter never runs (AVAssetExportSession is inert in
/// AVFoundation.swift), so the filter is a pure token object.
public final class AVMetadataItemFilter: @unchecked Sendable {
    private init() {}

    public static func forSharing() -> AVMetadataItemFilter { AVMetadataItemFilter() }
}

#endif
