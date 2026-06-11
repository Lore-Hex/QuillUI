import Foundation
import AppKit
import CoreVideo

public final class CallAudioTone: NSObject {
    public let samples: Data
    public let sampleRate: Int
    public let loopCount: Int

    public init(samples: Data, sampleRate: Int, loopCount: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.loopCount = loopCount
        super.init()
    }
}

public final class SharedCallAudioDevice: NSObject {
    public init(disableRecording: Bool, enableSystemMute: Bool) {
        _ = (disableRecording, enableSystemMute)
        super.init()
    }

    public static func setupAudioSession() {}
    public func setManualAudioSessionIsActive(_ isAudioSessionActive: Bool) { _ = isAudioSessionActive }
    public func setTone(_ tone: CallAudioTone?) { _ = tone }
}

public final class OngoingCallConnectionDescriptionWebrtc: NSObject {
    public let reflectorId: UInt8
    public let hasStun: Bool
    public let hasTurn: Bool
    public let hasTcp: Bool
    public let ip: String
    public let port: Int32
    public let username: String
    public let password: String

    public init(reflectorId: UInt8, hasStun: Bool, hasTurn: Bool, hasTcp: Bool, ip: String, port: Int32, username: String, password: String) {
        self.reflectorId = reflectorId
        self.hasStun = hasStun
        self.hasTurn = hasTurn
        self.hasTcp = hasTcp
        self.ip = ip
        self.port = port
        self.username = username
        self.password = password
        super.init()
    }
}

public enum OngoingCallStateWebrtc: Int32 {
    case initializing
    case connected
    case failed
    case reconnecting
}

public enum OngoingCallVideoStateWebrtc: Int32 {
    case inactive
    case active
    case paused
}

public enum OngoingCallRemoteVideoStateWebrtc: Int32 {
    case inactive
    case active
    case paused
}

public enum OngoingCallRemoteAudioStateWebrtc: Int32 {
    case muted
    case active
}

public enum OngoingCallRemoteBatteryLevelWebrtc: Int32 {
    case normal
    case low
}

public enum OngoingCallVideoOrientationWebrtc: Int32 {
    case orientation0
    case orientation90
    case orientation180
    case orientation270
}

public enum OngoingCallNetworkTypeWebrtc: Int32 {
    case wifi
    case cellularGprs
    case cellularEdge
    case cellular3g
    case cellularLte
}

public enum OngoingCallDataSavingWebrtc: Int32 {
    case never
    case cellular
    case always
}

public final class GroupCallDisposable: NSObject {
    private var block: (() -> Void)?

    public init(block: @escaping () -> Void) {
        self.block = block
        super.init()
    }

    public func dispose() {
        let current = block
        block = nil
        current?()
    }
}

public protocol OngoingCallThreadLocalContextQueueWebrtc: AnyObject {
    func dispatch(_ f: @escaping () -> Void)
    func isCurrent() -> Bool
    func scheduleBlock(_ f: @escaping () -> Void, after timeout: Double) -> GroupCallDisposable
}

public final class VoipProxyServerWebrtc: NSObject {
    public let host: String
    public let port: Int32
    public let username: String?
    public let password: String?

    public init(host: String, port: Int32, username: String?, password: String?) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        super.init()
    }
}

public protocol OngoingCallThreadLocalContextWebrtcVideoView: AnyObject {
    var orientation: OngoingCallVideoOrientationWebrtc { get }
    var aspect: CGFloat { get }
    func setOnFirstFrameReceived(_ onFirstFrameReceived: ((Float) -> Void)?)
    func setOnOrientationUpdated(_ onOrientationUpdated: ((OngoingCallVideoOrientationWebrtc, CGFloat) -> Void)?)
    func setOnIsMirroredUpdated(_ onIsMirroredUpdated: ((Bool) -> Void)?)
    func updateIsEnabled(_ isEnabled: Bool)
    func setVideoContentMode(_ mode: CALayerContentsGravity)
    func setForceMirrored(_ forceMirrored: Bool)
    func setIsPaused(_ paused: Bool)
    func render(to size: NSSize, animated: Bool)
}

public final class QuillTgVoipVideoView: NSView, OngoingCallThreadLocalContextWebrtcVideoView {
    public var orientation: OngoingCallVideoOrientationWebrtc = .orientation0
    public var aspect: CGFloat = 0
    private var onFirstFrameReceived: ((Float) -> Void)?
    private var onOrientationUpdated: ((OngoingCallVideoOrientationWebrtc, CGFloat) -> Void)?
    private var onIsMirroredUpdated: ((Bool) -> Void)?

    public func setOnFirstFrameReceived(_ onFirstFrameReceived: ((Float) -> Void)?) {
        self.onFirstFrameReceived = onFirstFrameReceived
    }

    public func setOnOrientationUpdated(_ onOrientationUpdated: ((OngoingCallVideoOrientationWebrtc, CGFloat) -> Void)?) {
        self.onOrientationUpdated = onOrientationUpdated
    }

    public func setOnIsMirroredUpdated(_ onIsMirroredUpdated: ((Bool) -> Void)?) {
        self.onIsMirroredUpdated = onIsMirroredUpdated
    }

    public func updateIsEnabled(_ isEnabled: Bool) { _ = isEnabled }
    public func setVideoContentMode(_ mode: CALayerContentsGravity) { _ = mode }
    public func setForceMirrored(_ forceMirrored: Bool) { _ = forceMirrored }
    public func setIsPaused(_ paused: Bool) { _ = paused }
    public func render(to size: NSSize, animated: Bool) { _ = (size, animated) }
}

public protocol CallVideoFrameBuffer: AnyObject {}

public final class CallVideoFrameNativePixelBuffer: NSObject, CallVideoFrameBuffer {
    public let pixelBuffer: CVPixelBuffer

    public init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
        super.init()
    }
}

public final class CallVideoFrameNV12Buffer: NSObject, CallVideoFrameBuffer {
    public let width: Int32
    public let height: Int32
    public let y: Data
    public let strideY: Int32
    public let uv: Data
    public let strideUV: Int32

    public init(width: Int32, height: Int32, y: Data = Data(), strideY: Int32 = 0, uv: Data = Data(), strideUV: Int32 = 0) {
        self.width = width
        self.height = height
        self.y = y
        self.strideY = strideY
        self.uv = uv
        self.strideUV = strideUV
        super.init()
    }
}

public final class CallVideoFrameI420Buffer: NSObject, CallVideoFrameBuffer {
    public let width: Int32
    public let height: Int32
    public let y: Data
    public let strideY: Int32
    public let u: Data
    public let strideU: Int32
    public let v: Data
    public let strideV: Int32

    public init(width: Int32, height: Int32, y: Data = Data(), strideY: Int32 = 0, u: Data = Data(), strideU: Int32 = 0, v: Data = Data(), strideV: Int32 = 0) {
        self.width = width
        self.height = height
        self.y = y
        self.strideY = strideY
        self.u = u
        self.strideU = strideU
        self.v = v
        self.strideV = strideV
        super.init()
    }
}

public final class CallVideoFrameData: NSObject {
    public let buffer: CallVideoFrameBuffer
    public let width: Int32
    public let height: Int32
    public let orientation: OngoingCallVideoOrientationWebrtc
    public let hasDeviceRelativeOrientation: Bool
    public let deviceRelativeOrientation: OngoingCallVideoOrientationWebrtc
    public let mirrorHorizontally: Bool
    public let mirrorVertically: Bool

    public init(
        buffer: CallVideoFrameBuffer = CallVideoFrameNV12Buffer(width: 0, height: 0),
        width: Int32 = 0,
        height: Int32 = 0,
        orientation: OngoingCallVideoOrientationWebrtc = .orientation0,
        hasDeviceRelativeOrientation: Bool = false,
        deviceRelativeOrientation: OngoingCallVideoOrientationWebrtc = .orientation0,
        mirrorHorizontally: Bool = false,
        mirrorVertically: Bool = false
    ) {
        self.buffer = buffer
        self.width = width
        self.height = height
        self.orientation = orientation
        self.hasDeviceRelativeOrientation = hasDeviceRelativeOrientation
        self.deviceRelativeOrientation = deviceRelativeOrientation
        self.mirrorHorizontally = mirrorHorizontally
        self.mirrorVertically = mirrorVertically
        super.init()
    }
}

public final class OngoingCallThreadLocalContextVideoCapturer: NSObject {
    private var onIsActiveUpdated: ((Bool) -> Void)?

    public init(deviceId: String, keepLandscape: Bool) {
        _ = (deviceId, keepLandscape)
        super.init()
    }

    public static func withExternalSampleBufferProvider() -> OngoingCallThreadLocalContextVideoCapturer {
        OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: true)
    }

    public func switchVideoInput(_ deviceId: String) { _ = deviceId }
    public func setIsVideoEnabled(_ isVideoEnabled: Bool) { _ = isVideoEnabled }

    public func makeOutgoingVideoView(_ requestClone: Bool, completion: @escaping (QuillTgVoipVideoView?, QuillTgVoipVideoView?) -> Void) {
        completion(QuillTgVoipVideoView(frame: .zero), requestClone ? QuillTgVoipVideoView(frame: .zero) : nil)
    }

    public func setOnFatalError(_ onError: (() -> Void)?) { _ = onError }
    public func setOnPause(_ onPause: ((Bool) -> Void)?) { _ = onPause }
    public func setOnIsActiveUpdated(_ onIsActiveUpdated: @escaping (Bool) -> Void) {
        self.onIsActiveUpdated = onIsActiveUpdated
        onIsActiveUpdated(true)
    }

    public func submitPixelBuffer(_ pixelBuffer: CVPixelBuffer, rotation: OngoingCallVideoOrientationWebrtc) {
        _ = (pixelBuffer, rotation)
    }

    public func submitSampleBuffer<SampleBuffer>(_ sampleBuffer: SampleBuffer, rotation: OngoingCallVideoOrientationWebrtc, completion: @escaping () -> Void) {
        _ = (sampleBuffer, rotation)
        completion()
    }

    public func addVideoOutput(_ sink: @escaping (CallVideoFrameData) -> Void) -> GroupCallDisposable {
        _ = sink
        return GroupCallDisposable(block: {})
    }
}

public protocol OngoingCallDirectConnection: AnyObject {
    func addOnIncomingPacket(_ addOnIncomingPacket: @escaping (Data) -> Void) -> Data
    func removeOnIncomingPacket(_ token: Data)
    func sendPacket(_ packet: Data)
}

public final class OngoingCallThreadLocalContextWebrtc: NSObject {
    private static var loggingFunction: ((String?) -> Void)?

    public static func setupLoggingFunction(_ loggingFunction: ((String?) -> Void)?) {
        self.loggingFunction = loggingFunction
    }

    public static func applyServerConfig(_ data: String?) { _ = data }
    public static func setupAudioSession() {}
    public static func maxLayer() -> Int32 { 92 }
    public static func versions(withIncludeReference includeReference: Bool) -> [String] {
        _ = includeReference
        return ["12.0.0"]
    }
    public static func logMessage(_ message: String) {
        loggingFunction?(message)
    }

    public var stateChanged: ((OngoingCallStateWebrtc, OngoingCallVideoStateWebrtc, OngoingCallRemoteVideoStateWebrtc, OngoingCallRemoteAudioStateWebrtc, OngoingCallRemoteBatteryLevelWebrtc, Float) -> Void)?
    public var signalBarsChanged: ((Int32) -> Void)?
    public var audioLevelUpdated: ((Float) -> Void)?
    private let derivedState: Data
    private let callVersion: String

    public init(
        version: String,
        customParameters: String? = nil,
        queue: OngoingCallThreadLocalContextQueueWebrtc,
        proxy: VoipProxyServerWebrtc?,
        networkType: OngoingCallNetworkTypeWebrtc,
        dataSaving: OngoingCallDataSavingWebrtc,
        derivedState: Data,
        key: Data,
        isOutgoing: Bool,
        connections: [OngoingCallConnectionDescriptionWebrtc],
        maxLayer: Int32,
        allowP2P: Bool,
        allowTCP: Bool,
        enableStunMarking: Bool,
        logPath: String,
        statsLogPath: String,
        sendSignalingData: @escaping (Data) -> Void,
        videoCapturer: OngoingCallThreadLocalContextVideoCapturer?,
        preferredVideoCodec: String?,
        audioInputDeviceId: String = "",
        audioDevice: SharedCallAudioDevice? = nil,
        directConnection: OngoingCallDirectConnection? = nil,
        inputDeviceId: String = "",
        outputDeviceId: String = ""
    ) {
        _ = (customParameters, queue, proxy, networkType, dataSaving, key, isOutgoing, connections, maxLayer, allowP2P, allowTCP, enableStunMarking, logPath, statsLogPath, sendSignalingData, videoCapturer, preferredVideoCodec, audioInputDeviceId, audioDevice, directConnection, inputDeviceId, outputDeviceId)
        self.derivedState = derivedState
        self.callVersion = version
        super.init()
    }

    public func beginTermination() {}
    public func stop(_ completion: ((String?, Int64, Int64, Int64, Int64) -> Void)?) {
        completion?(nil, 0, 0, 0, 0)
    }
    public func needRate() -> Bool { false }
    public func debugInfo() -> String? { "" }
    public func version() -> String? { callVersion }
    public func getDerivedState() -> Data { derivedState }
    public func setIsMuted(_ isMuted: Bool) { _ = isMuted }
    public func setIsLowBatteryLevel(_ isLowBatteryLevel: Bool) { _ = isLowBatteryLevel }
    public func setNetworkType(_ networkType: OngoingCallNetworkTypeWebrtc) { _ = networkType }
    public func makeIncomingVideoView(_ completion: @escaping (QuillTgVoipVideoView?) -> Void) {
        completion(QuillTgVoipVideoView(frame: .zero))
    }
    public func requestVideo(_ videoCapturer: OngoingCallThreadLocalContextVideoCapturer?) { _ = videoCapturer }
    public func setRequestedVideoAspect(_ aspect: Float) { _ = aspect }
    public func disableVideo() {}
    public func addSignalingData(_ data: Data) { _ = data }
    public func addSignaling(_ data: Data) { addSignalingData(data) }
    public func switchAudioOutput(_ deviceId: String) { _ = deviceId }
    public func switchAudioInput(_ deviceId: String) { _ = deviceId }
    public func addExternalAudioData(_ data: Data) { _ = data }
    public func deactivateIncomingAudio() {}
    public func setManualAudioSessionIsActive(_ isAudioSessionActive: Bool) { _ = isAudioSessionActive }
    public func addVideoOutput(withIsIncoming isIncoming: Bool, sink: @escaping (CallVideoFrameData) -> Void) -> GroupCallDisposable {
        _ = (isIncoming, sink)
        return GroupCallDisposable(block: {})
    }
}

public struct GroupCallNetworkState {
    public var isConnected: Bool
    public var isTransitioningFromBroadcastToRtc: Bool

    public init(isConnected: Bool = false, isTransitioningFromBroadcastToRtc: Bool = false) {
        self.isConnected = isConnected
        self.isTransitioningFromBroadcastToRtc = isTransitioningFromBroadcastToRtc
    }
}

public enum OngoingGroupCallMediaChannelType: Int32 {
    case audio
    case video
}

public final class OngoingGroupCallMediaChannelDescription: NSObject {
    public let type: OngoingGroupCallMediaChannelType
    public let peerId: Int64
    public let audioSsrc: UInt32
    public let videoDescription: String?

    public init(type: OngoingGroupCallMediaChannelType, peerId: Int64, audioSsrc: UInt32, videoDescription: String?) {
        self.type = type
        self.peerId = peerId
        self.audioSsrc = audioSsrc
        self.videoDescription = videoDescription
        super.init()
    }
}

public protocol OngoingGroupCallBroadcastPartTask: AnyObject {
    func cancel()
}

public protocol OngoingGroupCallMediaChannelDescriptionTask: AnyObject {
    func cancel()
}

public enum OngoingCallConnectionMode: Int32 {
    case none
    case rtc
    case broadcast
}

public enum OngoingGroupCallBroadcastPartStatus: Int32 {
    case success
    case notReady
    case resyncNeeded
}

public enum OngoingGroupCallVideoContentType: Int32 {
    case none
    case generic
    case screencast
}

public final class OngoingGroupCallBroadcastPart: NSObject {
    public let timestampMilliseconds: Int64
    public let responseTimestamp: Double
    public let status: OngoingGroupCallBroadcastPartStatus
    public let oggData: Data

    public init(timestampMilliseconds: Int64, responseTimestamp: Double, status: OngoingGroupCallBroadcastPartStatus, oggData: Data) {
        self.timestampMilliseconds = timestampMilliseconds
        self.responseTimestamp = responseTimestamp
        self.status = status
        self.oggData = oggData
        super.init()
    }
}

public enum OngoingGroupCallRequestedVideoQuality: Int32 {
    case thumbnail
    case medium
    case full
}

public final class OngoingGroupCallSsrcGroup: NSObject {
    public let semantics: String
    public let ssrcs: [NSNumber]

    public init(semantics: String, ssrcs: [NSNumber]) {
        self.semantics = semantics
        self.ssrcs = ssrcs
        super.init()
    }
}

public final class OngoingGroupCallRequestedVideoChannel: NSObject {
    public let audioSsrc: UInt32
    public let userId: Int64
    public let endpointId: String
    public let ssrcGroups: [OngoingGroupCallSsrcGroup]
    public let minQuality: OngoingGroupCallRequestedVideoQuality
    public let maxQuality: OngoingGroupCallRequestedVideoQuality

    public init(audioSsrc: UInt32, userId: Int64, endpointId: String, ssrcGroups: [OngoingGroupCallSsrcGroup], minQuality: OngoingGroupCallRequestedVideoQuality, maxQuality: OngoingGroupCallRequestedVideoQuality) {
        self.audioSsrc = audioSsrc
        self.userId = userId
        self.endpointId = endpointId
        self.ssrcGroups = ssrcGroups
        self.minQuality = minQuality
        self.maxQuality = maxQuality
        super.init()
    }
}

public final class OngoingGroupCallIncomingVideoStats: NSObject {
    public let receivingQuality: Int32
    public let availableQuality: Int32

    public init(receivingQuality: Int32, availableQuality: Int32) {
        self.receivingQuality = receivingQuality
        self.availableQuality = availableQuality
        super.init()
    }
}

public final class OngoingGroupCallStats: NSObject {
    public let incomingVideoStats: [String: OngoingGroupCallIncomingVideoStats]

    public init(incomingVideoStats: [String: OngoingGroupCallIncomingVideoStats]) {
        self.incomingVideoStats = incomingVideoStats
        super.init()
    }
}

public final class GroupCallThreadLocalContext: NSObject {
    public var signalBarsChanged: ((Int32) -> Void)?

    public init(
        queue: OngoingCallThreadLocalContextQueueWebrtc,
        networkStateUpdated: @escaping (GroupCallNetworkState) -> Void,
        audioLevelsUpdated: @escaping ([NSNumber]) -> Void,
        activityUpdated: @escaping ([NSNumber]) -> Void,
        inputDeviceId: String,
        outputDeviceId: String,
        videoCapturer: OngoingCallThreadLocalContextVideoCapturer?,
        requestMediaChannelDescriptions: @escaping ([NSNumber], @escaping ([OngoingGroupCallMediaChannelDescription]) -> Void) -> OngoingGroupCallMediaChannelDescriptionTask,
        requestCurrentTime: @escaping (@escaping (Int64) -> Void) -> OngoingGroupCallBroadcastPartTask,
        requestAudioBroadcastPart: @escaping (Int64, Int64, @escaping (OngoingGroupCallBroadcastPart?) -> Void) -> OngoingGroupCallBroadcastPartTask,
        requestVideoBroadcastPart: @escaping (Int64, Int64, Int32, OngoingGroupCallRequestedVideoQuality, @escaping (OngoingGroupCallBroadcastPart?) -> Void) -> OngoingGroupCallBroadcastPartTask,
        outgoingAudioBitrateKbit: Int32,
        videoContentType: OngoingGroupCallVideoContentType,
        enableNoiseSuppression: Bool,
        disableAudioInput: Bool,
        enableSystemMute: Bool = false,
        prioritizeVP8: Bool,
        logPath: String,
        statsLogPath: String,
        onMutedSpeechActivityDetected: ((Bool) -> Void)? = nil,
        audioDevice: SharedCallAudioDevice?,
        isConference: Bool,
        isActiveByDefault: Bool,
        encryptDecrypt: ((Data, Int64, Bool, Int32) -> Data?)?
    ) {
        _ = (queue, networkStateUpdated, audioLevelsUpdated, activityUpdated, inputDeviceId, outputDeviceId, videoCapturer, requestMediaChannelDescriptions, requestCurrentTime, requestAudioBroadcastPart, requestVideoBroadcastPart, outgoingAudioBitrateKbit, videoContentType, enableNoiseSuppression, disableAudioInput, enableSystemMute, prioritizeVP8, logPath, statsLogPath, onMutedSpeechActivityDetected, audioDevice, isConference, isActiveByDefault, encryptDecrypt)
        super.init()
    }

    public func stop() {}
    public func stop(_ completion: (() -> Void)?) { completion?() }
    public func setManualAudioSessionIsActive(_ isAudioSessionActive: Bool) { _ = isAudioSessionActive }
    public func setTone(_ tone: CallAudioTone?) { _ = tone }
    public func setConnectionMode(_ connectionMode: OngoingCallConnectionMode, keepBroadcastConnectedIfWasEnabled: Bool, isUnifiedBroadcast: Bool) {
        _ = (connectionMode, keepBroadcastConnectedIfWasEnabled, isUnifiedBroadcast)
    }
    public func emitJoinPayload(_ completion: @escaping (String, UInt32) -> Void) {
        completion("", 0)
    }
    public func setJoinResponsePayload(_ payload: String) { _ = payload }
    public func removeSsrcs(_ ssrcs: [NSNumber]) { _ = ssrcs }
    public func removeIncomingVideoSource(_ ssrc: UInt32) { _ = ssrc }
    public func setIsMuted(_ isMuted: Bool) { _ = isMuted }
    public func setIsNoiseSuppressionEnabled(_ isNoiseSuppressionEnabled: Bool) { _ = isNoiseSuppressionEnabled }
    public func requestVideo(_ videoCapturer: OngoingCallThreadLocalContextVideoCapturer?, completion: @escaping (String, UInt32) -> Void) {
        _ = videoCapturer
        completion("", 0)
    }
    public func disableVideo(_ completion: @escaping (String, UInt32) -> Void) {
        completion("", 0)
    }
    public func setVolumeForSsrc(_ ssrc: UInt32, volume: Double) { _ = (ssrc, volume) }
    public func setRequestedVideoChannels(_ requestedVideoChannels: [OngoingGroupCallRequestedVideoChannel]) { _ = requestedVideoChannels }
    public func switchAudioOutput(_ deviceId: String) { _ = deviceId }
    public func switchAudioInput(_ deviceId: String) { _ = deviceId }
    public func makeIncomingVideoView(withEndpointId endpointId: String, requestClone: Bool, completion: @escaping (QuillTgVoipVideoView?, QuillTgVoipVideoView?) -> Void) {
        _ = endpointId
        completion(QuillTgVoipVideoView(frame: .zero), requestClone ? QuillTgVoipVideoView(frame: .zero) : nil)
    }
    public func addVideoOutput(withEndpointId endpointId: String, sink: @escaping (CallVideoFrameData) -> Void) -> GroupCallDisposable {
        _ = (endpointId, sink)
        return GroupCallDisposable(block: {})
    }
    public func addExternalAudioData(_ data: Data) { _ = data }
    public func getStats(_ completion: @escaping (OngoingGroupCallStats) -> Void) {
        completion(OngoingGroupCallStats(incomingVideoStats: [:]))
    }
}

public final class MediaStreamingContext: NSObject {
    public init(
        queue: OngoingCallThreadLocalContextQueueWebrtc,
        requestCurrentTime: @escaping (@escaping (Int64) -> Void) -> OngoingGroupCallBroadcastPartTask,
        requestAudioBroadcastPart: @escaping (Int64, Int64, @escaping (OngoingGroupCallBroadcastPart?) -> Void) -> OngoingGroupCallBroadcastPartTask,
        requestVideoBroadcastPart: @escaping (Int64, Int64, Int32, OngoingGroupCallRequestedVideoQuality, @escaping (OngoingGroupCallBroadcastPart?) -> Void) -> OngoingGroupCallBroadcastPartTask
    ) {
        _ = (queue, requestCurrentTime, requestAudioBroadcastPart, requestVideoBroadcastPart)
        super.init()
    }

    public func start() {}
    public func stop() {}
    public func addVideoOutput(_ sink: @escaping (CallVideoFrameData) -> Void) -> GroupCallDisposable {
        _ = sink
        return GroupCallDisposable(block: {})
    }
    public func getAudio(_ audioSamples: UnsafeMutablePointer<Int16>, numSamples: Int, numChannels: Int, samplesPerSecond: Int) {
        _ = (audioSamples, numSamples, numChannels, samplesPerSecond)
    }
}

public final class LibYUVConverter: NSObject {
    public static func i420ToNV12(
        withSrcY srcY: UnsafePointer<UInt8>,
        srcStrideY: Int32,
        srcU: UnsafePointer<UInt8>,
        srcStrideU: Int32,
        srcV: UnsafePointer<UInt8>,
        srcStrideV: Int32,
        dstY: UnsafeMutablePointer<UInt8>,
        dstStrideY: Int32,
        dstUV: UnsafeMutablePointer<UInt8>,
        dstStrideUV: Int32,
        width: Int32,
        height: Int32
    ) -> Bool {
        _ = (srcY, srcStrideY, srcU, srcStrideU, srcV, srcStrideV, dstY, dstStrideY, dstUV, dstStrideUV, width, height)
        return true
    }
}
