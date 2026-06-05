import Foundation
import QuillKit
import QuillFoundation  // CGImage (AVAssetImageGenerator.copyCGImage return type)

#if os(Linux)
public protocol AVSpeechSynthesizerDelegate: AnyObject {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didReceiveError error: Error, for utterance: AVSpeechUtterance, at characterIndex: UInt)
}

public extension AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didReceiveError error: Error, for utterance: AVSpeechUtterance, at characterIndex: UInt) {}
}

public final class AVSpeechSynthesizer: @unchecked Sendable {
    public weak var delegate: AVSpeechSynthesizerDelegate?
    public init() {}
    public func speak(_ utterance: AVSpeechUtterance) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "AVFoundation",
            operation: "speechSynthesis",
            severity: .info,
            message: "AVSpeechSynthesizer.speak is emulated on Linux until a native speech backend is attached."
        )
        delegate?.speechSynthesizer(self, didStart: utterance)
        delegate?.speechSynthesizer(self, didFinish: utterance)
    }
    @discardableResult
    public func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { true }
    @discardableResult
    public func continueSpeaking() -> Bool { false }
    @discardableResult
    public func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool { false }
}

public enum AVSpeechBoundary: Int, Sendable {
    case immediate
    case word
}

public final class AVSpeechUtterance: @unchecked Sendable {
    public init(string: String) {}
    public var voice: AVSpeechSynthesisVoice?
    public var rate: Float = 0.5
    public var pitchMultiplier: Float = 1.0
    public var volume: Float = 1.0
}

public final class AVSpeechSynthesisVoice: @unchecked Sendable {
    public let identifier: String
    public let name: String
    public let quality: VoiceQuality
    
    public enum VoiceQuality: Int, Sendable {
        case low, enhanced
    }
    
    public init(identifier: String, name: String, quality: VoiceQuality) {
        self.identifier = identifier
        self.name = name
        self.quality = quality
    }

    /// Apple's real `AVSpeechSynthesisVoice` has a failable
    /// `init?(identifier:)` that returns the matching system
    /// voice or nil. Enchanted uses this shape for stored voice
    /// IDs. The Linux stub returns a voice with the requested
    /// identifier and empty defaults.
    public convenience init?(identifier: String) {
        self.init(identifier: identifier, name: identifier, quality: .low)
    }

    public static func speechVoices() -> [AVSpeechSynthesisVoice] { [] }
    public static func currentLanguageCode() -> String { "en-US" }
}

public final class AVAudioSession: @unchecked Sendable {
    public enum Category: Int, Sendable { case ambient, soloAmbient, playback, record, playAndRecord, multiRoute }
    public enum Mode: Int, Sendable { case videoChat, videoRecording, measurement, moviePlayback, spokenAudio }
    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1 << 0)
        public static let duckOthers = CategoryOptions(rawValue: 1 << 1)
        public static let allowBluetooth = CategoryOptions(rawValue: 1 << 2)
        public static let defaultToSpeaker = CategoryOptions(rawValue: 1 << 3)
    }
    public struct SetActiveOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1 << 0)
    }

    public init() {}
    public static func sharedInstance() -> AVAudioSession { AVAudioSession() }
    public func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {}
    public func setActive(_ active: Bool, options: SetActiveOptions = []) throws {}
}

public final class AVPlayer: @unchecked Sendable {
    public init() {}
    public init(url: URL) {}
}

// Real AVAudioEngine drives the macOS/iOS CoreAudio graph (input
// node, output node, mixers, effects). The Linux stub stands in
// just enough surface for source-compat: callers can build the
// graph, install taps, start/stop, prepare — all no-ops backed
// by a diagnostic record. Real audio I/O comes when a Linux
// audio backend (PipeWire, ALSA, JACK) is wired up.
public final class AVAudioEngine: @unchecked Sendable {
    public init() {}
    public lazy var inputNode: AVAudioInputNode = AVAudioInputNode()
    public lazy var outputNode: AVAudioOutputNode = AVAudioOutputNode()
    public lazy var mainMixerNode: AVAudioMixerNode = AVAudioMixerNode()

    public var isRunning: Bool = false

    public func prepare() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "AVFoundation",
            operation: "AVAudioEngine.prepare",
            message: "AVAudioEngine.prepare is a no-op on Linux until a real audio backend lands."
        )
    }

    public func start() throws {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "AVFoundation",
            operation: "AVAudioEngine.start",
            message: "AVAudioEngine.start is a no-op on Linux until a real audio backend lands."
        )
        isRunning = true
    }

    public func stop() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "AVFoundation",
            operation: "AVAudioEngine.stop",
            message: "AVAudioEngine.stop is a no-op on Linux until a real audio backend lands."
        )
        isRunning = false
    }

    public func reset() {
        isRunning = false
    }

    public func attach(_ node: AVAudioNode) {}

    public func connect(
        _ source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat?
    ) {}
}

public class AVAudioNode: @unchecked Sendable {
    public init() {}

    public func installTap(
        onBus bus: Int,
        bufferSize: UInt32,
        format: AVAudioFormat?,
        block tapBlock: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "AVFoundation",
            operation: "AVAudioNode.installTap",
            message: "AVAudioNode.installTap is a no-op on Linux until a real audio backend lands."
        )
    }

    public func removeTap(onBus bus: Int) {}

    public func outputFormat(forBus bus: Int) -> AVAudioFormat {
        AVAudioFormat()
    }
}

public final class AVAudioInputNode: AVAudioNode, @unchecked Sendable {
    public override init() { super.init() }
}

public final class AVAudioOutputNode: AVAudioNode, @unchecked Sendable {
    public override init() { super.init() }
}

public final class AVAudioMixerNode: AVAudioNode, @unchecked Sendable {
    public override init() { super.init() }
    public var outputVolume: Float = 1.0
}

public final class AVAudioFormat: @unchecked Sendable {
    public var sampleRate: Double = 0
    public var channelCount: UInt32 = 0
    public init() {}
    public init(commonFormat: Int = 0, sampleRate: Double = 0, channels: UInt32 = 0, interleaved: Bool = false) {
        self.sampleRate = sampleRate
        self.channelCount = channels
    }
}

// Bare-bones audio buffer type referenced by the Speech shim's
// `SFSpeechAudioBufferRecognitionRequest.append(_:)`. Real Apple
// `AVAudioPCMBuffer` exposes frame counts, channel formats, and
// raw sample pointers — the Linux stub only needs to exist as a
// type so callers can compile. Add real fields when a native
// Linux audio backend lands.
public final class AVAudioPCMBuffer: @unchecked Sendable {
    public var frameLength: UInt32 = 0
    public init() {}
}

// `AVAudioTime` carries audio timestamps in real AVFoundation.
// The Linux stub stores a Foundation `Date` so callers can
// compile and round-trip "when did this audio frame arrive"
// without a CoreAudio backend.
public final class AVAudioTime: @unchecked Sendable {
    public var hostTime: UInt64
    public var sampleTime: Int64
    public var sampleRate: Double
    public init(hostTime: UInt64 = 0, sampleTime: Int64 = 0, sampleRate: Double = 0) {
        self.hostTime = hostTime
        self.sampleTime = sampleTime
        self.sampleRate = sampleRate
    }
}

// MARK: - Asset reading / media inspection (Linux placeholders)
//
// SignalServiceKit inspects video/audio attachments (dimensions, duration,
// waveform samples) and exports them. CoreMedia / asset reading is unavailable
// on Linux, so these are INERT: assets report not-readable, zero tracks, zero
// duration; the reader produces no sample buffers; the image generator and the
// exporter fail. Real media handling needs a Linux AV backend (GStreamer /
// FFmpeg) -- deferred. HONEST STATUS: video thumbnails, durations and audio
// waveforms are unavailable on Linux; callers already degrade to placeholders.

fileprivate struct AVMediaUnavailableOnLinux: Error, CustomStringConvertible {
    var description: String { "AVFoundation media operations are unavailable on Linux (no AV backend)." }
}

public struct AVMediaType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
    public static let audio = AVMediaType(rawValue: "soun")
    public static let text = AVMediaType(rawValue: "text")
    public static let muxed = AVMediaType(rawValue: "muxx")
    public static let timecode = AVMediaType(rawValue: "tmcd")
}

public struct AVFileType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let mp4 = AVFileType(rawValue: "public.mpeg-4")
    public static let mov = AVFileType(rawValue: "com.apple.quicktime-movie")
    public static let m4a = AVFileType(rawValue: "com.apple.m4a-audio")
    public static let m4v = AVFileType(rawValue: "public.m4v")
}

// MARK: CoreMedia time

public struct CMTime: Sendable, Equatable {
    public var value: Int64
    public var timescale: Int32
    public var flags: UInt32
    public var epoch: Int64
    public init(value: Int64 = 0, timescale: Int32 = 0, flags: UInt32 = 0, epoch: Int64 = 0) {
        self.value = value; self.timescale = timescale; self.flags = flags; self.epoch = epoch
    }
    public init(seconds: Double, preferredTimescale: Int32) {
        self.timescale = preferredTimescale
        self.value = Int64(seconds * Double(preferredTimescale))
        self.flags = 0; self.epoch = 0
    }
    public var seconds: Double { timescale == 0 ? 0 : Double(value) / Double(timescale) }
    public static let zero = CMTime(value: 0, timescale: 1)
    public static let invalid = CMTime(value: 0, timescale: 0)
}

public func CMTimeMake(value: Int64, timescale: Int32) -> CMTime { CMTime(value: value, timescale: timescale) }
public func CMTimeMakeWithSeconds(_ seconds: Double, preferredTimescale: Int32) -> CMTime { CMTime(seconds: seconds, preferredTimescale: preferredTimescale) }
public func CMTimeGetSeconds(_ time: CMTime) -> Float64 { time.seconds }

// MARK: CoreMedia sample / block buffers (opaque, inert)

public final class CMSampleBuffer: @unchecked Sendable { public init() {} }
public final class CMBlockBuffer: @unchecked Sendable { public init() {} }
public final class CMFormatDescription: @unchecked Sendable { public init() {} }

public let kCMBlockBufferNoErr: Int32 = 0

public func CMSampleBufferGetDataBuffer(_ sbuf: CMSampleBuffer) -> CMBlockBuffer? { nil }
public func CMSampleBufferInvalidate(_ sbuf: CMSampleBuffer) {}
public func CMSampleBufferGetNumSamples(_ sbuf: CMSampleBuffer) -> Int { 0 }

public func CMBlockBufferGetDataPointer(
    _ buffer: CMBlockBuffer,
    atOffset offset: Int,
    lengthAtOffsetOut: UnsafeMutablePointer<Int>?,
    totalLengthOut: UnsafeMutablePointer<Int>?,
    dataPointerOut: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?
) -> Int32 {
    -1  // never kCMBlockBufferNoErr: no data is ever produced on Linux
}

// CoreAudio stream format (minimal; SSK reads only mChannelsPerFrame).
public struct AudioStreamBasicDescription: Sendable {
    public var mSampleRate: Float64 = 0
    public var mFormatID: UInt32 = 0
    public var mFormatFlags: UInt32 = 0
    public var mBytesPerPacket: UInt32 = 0
    public var mFramesPerPacket: UInt32 = 0
    public var mBytesPerFrame: UInt32 = 0
    public var mChannelsPerFrame: UInt32 = 0
    public var mBitsPerChannel: UInt32 = 0
    public var mReserved: UInt32 = 0
    public init() {}
}

public func CMAudioFormatDescriptionGetStreamBasicDescription(_ desc: CMFormatDescription) -> UnsafePointer<AudioStreamBasicDescription>? { nil }

// MARK: Assets

public class AVAsset: @unchecked Sendable {
    public init() {}
    public var isReadable: Bool { false }
    public var isPlayable: Bool { false }
    public var duration: CMTime { .zero }
    public var tracks: [AVAssetTrack] { [] }
    public func tracks(withMediaType mediaType: AVMediaType) -> [AVAssetTrack] { [] }
}

public final class AVURLAsset: AVAsset, @unchecked Sendable {
    public let url: URL
    public init(url: URL, options: [AnyHashable: Any]? = nil) {
        self.url = url
        super.init()
    }
}

public final class AVAssetTrack: @unchecked Sendable {
    public var naturalSize: CGSize { .zero }
    public var mediaType: AVMediaType { .video }
    // CGAffineTransform is absent from swift-corelibs -> typed Any (unused on Linux).
    public var preferredTransform: Any { 0 }
    public var nominalFrameRate: Float { 0 }
    public var estimatedDataRate: Float { 0 }
    public var formatDescriptions: [Any]? { [] }
    public init() {}
}

public final class AVAssetImageGenerator: @unchecked Sendable {
    public var maximumSize: CGSize = .zero
    public var appliesPreferredTrackTransform: Bool = false
    public var requestedTimeToleranceBefore: CMTime = .zero
    public var requestedTimeToleranceAfter: CMTime = .zero
    public init(asset: AVAsset) {}
    public func copyCGImage(at requestedTime: CMTime, actualTime: UnsafeMutablePointer<CMTime>?) throws -> CGImage {
        throw AVMediaUnavailableOnLinux()
    }
}

// MARK: Reader

public class AVAssetReaderOutput: @unchecked Sendable {
    public init() {}
    public func copyNextSampleBuffer() -> CMSampleBuffer? { nil }
}

public final class AVAssetReaderTrackOutput: AVAssetReaderOutput, @unchecked Sendable {
    public let track: AVAssetTrack
    public init(track: AVAssetTrack, outputSettings: [String: Any]?) {
        self.track = track
        super.init()
    }
}

public final class AVAssetReader: @unchecked Sendable {
    public enum Status: Int, Sendable { case unknown, reading, completed, failed, cancelled }
    public let asset: AVAsset
    public private(set) var outputs: [AVAssetReaderOutput] = []
    // Nothing to read on Linux -> immediately "completed" so read loops exit at once.
    public var status: Status { .completed }
    public var error: Error?
    public init(asset: AVAsset) throws { self.asset = asset }
    public func canAdd(_ output: AVAssetReaderOutput) -> Bool { true }
    public func add(_ output: AVAssetReaderOutput) { outputs.append(output) }
    @discardableResult public func startReading() -> Bool { true }
    public func cancelReading() {}
}

// MARK: Export

public final class AVAssetExportSession: @unchecked Sendable {
    public enum Status: Int, Sendable { case unknown, waiting, exporting, completed, failed, cancelled }
    public var outputURL: URL?
    public var outputFileType: AVFileType?
    public var shouldOptimizeForNetworkUse: Bool = false
    public var error: Error?
    public var status: Status { .failed }
    public init?(asset: AVAsset, presetName: String) {}
    public func exportAsynchronously(completionHandler handler: @escaping () -> Void) { handler() }
    public func export(to url: URL, as fileType: AVFileType) async throws {
        throw AVMediaUnavailableOnLinux()
    }
}

public let AVAssetExportPresetHighestQuality = "AVAssetExportPresetHighestQuality"
public let AVAssetExportPresetMediumQuality = "AVAssetExportPresetMediumQuality"
public let AVAssetExportPresetPassthrough = "AVAssetExportPresetPassthrough"
#endif
