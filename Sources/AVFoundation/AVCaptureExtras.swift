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

public enum AVAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
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

    // DiscoverySession (with init(deviceTypes:mediaType:position:)) is declared
    // in AVFoundation.swift — one owner. A duplicate here caused "invalid
    // redeclaration of 'DiscoverySession'".

    /// `AVCaptureDevice.DeviceType` on the (nonexistent) Linux device.
    public var deviceType: DeviceType { .builtInWideAngleCamera }

    /// Locking always succeeds — there is no capture pipeline to contend with.
    public func lockForConfiguration() throws {}
    public func unlockForConfiguration() {}

    public func isFocusModeSupported(_ focusMode: FocusMode) -> Bool { false }
    public func isExposureModeSupported(_ exposureMode: ExposureMode) -> Bool { false }

    /// Virtual multi-camera zoom switch-over points — none on Linux.
    public var virtualDeviceSwitchOverVideoZoomFactors: [NSNumber] { [] }

    /// Camera permission on Linux: there is no camera, so report `.denied`
    /// (upstream shows its "camera unavailable / open settings" sheet) and
    /// `requestAccess` resolves `false` without prompting.
    public static func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        _ = mediaType
        return .denied
    }

    public static func requestAccess(
        for mediaType: AVMediaType,
        completionHandler handler: @escaping (Bool) -> Void
    ) {
        _ = mediaType
        handler(false)
    }
}

extension AVCaptureDevice.DeviceType {
    public static let builtInTripleCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTripleCamera")
    public static let builtInDualWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualWideCamera")
    public static let builtInDualCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInDualCamera")
    public static let builtInUltraWideCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInUltraWideCamera")
    public static let builtInTelephotoCamera = AVCaptureDevice.DeviceType(rawValue: "AVCaptureDeviceTypeBuiltInTelephotoCamera")
}

// MARK: - AVCaptureSession

/// Config-storing no-op: preset/inputs/outputs are recorded faithfully and
/// start/stopRunning flip `isRunning`, but no frames are ever produced.
public final class AVCaptureSession: @unchecked Sendable {
    public struct Preset: RawRepresentable, Equatable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let high = Preset(rawValue: "AVCaptureSessionPresetHigh")
        public static let medium = Preset(rawValue: "AVCaptureSessionPresetMedium")
        public static let low = Preset(rawValue: "AVCaptureSessionPresetLow")
        public static let photo = Preset(rawValue: "AVCaptureSessionPresetPhoto")
        public static let inputPriority = Preset(rawValue: "AVCaptureSessionPresetInputPriority")
        public static let vga640x480 = Preset(rawValue: "AVCaptureSessionPreset640x480")
        public static let hd1280x720 = Preset(rawValue: "AVCaptureSessionPreset1280x720")
        public static let hd1920x1080 = Preset(rawValue: "AVCaptureSessionPreset1920x1080")
    }

    /// `.AVCaptureSessionWasInterrupted` userInfo reason codes (Apple raw values).
    public enum InterruptionReason: Int, Sendable {
        case videoDeviceNotAvailableInBackground = 1
        case audioDeviceInUseByAnotherClient = 2
        case videoDeviceInUseByAnotherClient = 3
        case videoDeviceNotAvailableWithMultipleForegroundApps = 4
        case videoDeviceNotAvailableDueToSystemPressure = 5
    }

    public var sessionPreset: Preset = .high
    public private(set) var inputs: [AVCaptureInput] = []
    public private(set) var outputs: [AVCaptureOutput] = []
    public private(set) var isRunning = false

    /// iOS 16 multitasking camera access — never supported on Linux; the
    /// enabled flag is stored only so upstream's availability branch compiles.
    public var isMultitaskingCameraAccessSupported: Bool { false }
    public var isMultitaskingCameraAccessEnabled = false

    public init() {}

    public func canAddInput(_ input: AVCaptureInput) -> Bool { true }
    public func addInput(_ input: AVCaptureInput) { inputs.append(input) }
    public func removeInput(_ input: AVCaptureInput) { inputs.removeAll { $0 === input } }

    public func canAddOutput(_ output: AVCaptureOutput) -> Bool { true }
    public func addOutput(_ output: AVCaptureOutput) { outputs.append(output) }
    public func removeOutput(_ output: AVCaptureOutput) { outputs.removeAll { $0 === output } }

    public func beginConfiguration() {}
    public func commitConfiguration() {}

    public func startRunning() { isRunning = true }
    public func stopRunning() { isRunning = false }
}

// MARK: - Inputs / outputs

/// Abstract base; like Apple, not directly constructible (internal init).
open class AVCaptureInput: @unchecked Sendable {
    internal init() {}
}

public final class AVCaptureDeviceInput: AVCaptureInput, @unchecked Sendable {
    public let device: AVCaptureDevice

    public init(device: AVCaptureDevice) throws {
        self.device = device
        super.init()
    }
}

/// Abstract base; like Apple, not directly constructible (internal init).
open class AVCaptureOutput: @unchecked Sendable {
    internal init() {}

    /// No live capture connections on Linux.
    open func connection(with mediaType: AVMediaType) -> AVCaptureConnection? {
        _ = mediaType
        return nil
    }
}

public final class AVCaptureVideoDataOutput: AVCaptureOutput, @unchecked Sendable {
    /// `[String: Any]!` on Apple (pixel-format dictionary). Stored verbatim.
    public var videoSettings: [String: Any]! = [:]
    public var alwaysDiscardsLateVideoFrames = true

    public private(set) weak var sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    public private(set) var sampleBufferCallbackQueue: DispatchQueue?

    public override init() { super.init() }

    /// The delegate is recorded but never invoked — no frames on Linux.
    public func setSampleBufferDelegate(
        _ sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?,
        queue sampleBufferCallbackQueue: DispatchQueue?
    ) {
        self.sampleBufferDelegate = sampleBufferDelegate
        self.sampleBufferCallbackQueue = sampleBufferCallbackQueue
    }
}

/// Optional `@objc` requirements on Apple; defaulted no-ops here so conformers
/// may implement either method. Never called on Linux (no capture pipeline).
public protocol AVCaptureVideoDataOutputSampleBufferDelegate: AnyObject {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
}

public extension AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
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

public final class AVCaptureConnection: @unchecked Sendable {
    public var isEnabled = true

    /// Orientation/stabilization are stored for shape fidelity; nothing
    /// consumes them (and `isVideoOrientationSupported` is honestly false).
    public var videoOrientation: AVCaptureVideoOrientation = .portrait
    public var isVideoOrientationSupported: Bool { false }

    public var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off
    public var isVideoStabilizationSupported: Bool { false }

    internal init() {}
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
