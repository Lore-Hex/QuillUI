import Foundation
import QuillKit
import QuillFoundation  // CGImage (AVAssetImageGenerator.copyCGImage return type)
import QuartzCore
@_exported import AudioToolbox
@_exported import CoreMedia
@_exported import CoreVideo

#if os(Linux)
public let AVAssetExportPreset1280x720 = "AVAssetExportPreset1280x720"
public let AVAssetExportPreset1920x1080 = "AVAssetExportPreset1920x1080"

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
    private let backend: QuillSpeechBackend

    public init() {
        backend = .shared
    }

    public var isSpeaking: Bool { backend.isSpeaking }

    public var isPaused: Bool {
        backend.isPaused
    }

    public func speak(_ utterance: AVSpeechUtterance) {
        backend.speak(utterance.speechString) { [weak self] in
            guard let self else { return }
            delegate?.speechSynthesizer(self, didStart: utterance)
        } onFinish: { [weak self] in
            guard let self else { return }
            delegate?.speechSynthesizer(self, didFinish: utterance)
        }
    }
    @discardableResult
    public func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        return backend.stop()
    }
    @discardableResult
    public func continueSpeaking() -> Bool {
        backend.continueSpeaking()
    }
    @discardableResult
    public func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        backend.pause()
    }
}

public enum AVSpeechBoundary: Int, Sendable {
    case immediate
    case word
}

public final class AVSpeechUtterance: @unchecked Sendable {
    public let speechString: String
    public init(string: String) {
        speechString = string
    }
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
        if let voice = QuillSpeechBackend.shared.voices().first(where: { $0.identifier == identifier }) {
            self.init(
                identifier: voice.identifier,
                name: voice.name,
                quality: VoiceQuality(rawValue: voice.quality) ?? .low
            )
        } else {
            self.init(identifier: identifier, name: identifier, quality: .low)
        }
    }

    public static func speechVoices() -> [AVSpeechSynthesisVoice] {
        QuillSpeechBackend.shared.voices().map { voice in
            AVSpeechSynthesisVoice(
                identifier: voice.identifier,
                name: voice.name,
                quality: VoiceQuality(rawValue: voice.quality) ?? .low
            )
        }
    }
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

    private static let shared = AVAudioSession()
    private let service: QuillAudioSessionService

    public init() {
        service = .shared
    }

    private init(service: QuillAudioSessionService = .shared) {
        self.service = service
    }

    public static func sharedInstance() -> AVAudioSession { shared }

    public var category: Category {
        Category(rawValue: service.category.rawValue) ?? .ambient
    }

    public var mode: Mode {
        Mode(rawValue: service.mode.rawValue) ?? .spokenAudio
    }

    public var categoryOptions: CategoryOptions {
        CategoryOptions(rawValue: service.categoryOptionsRawValue)
    }

    public var isActive: Bool {
        service.isActive
    }

    public func setCategory(_ category: Category) throws {
        try setCategory(category, mode: mode, options: categoryOptions)
    }

    public func setCategory(_ category: Category, mode: Mode) throws {
        try setCategory(category, mode: mode, options: [])
    }

    public func setCategory(_ category: Category, options: CategoryOptions = []) throws {
        try setCategory(category, mode: mode, options: options)
    }

    public func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {
        service.setCategory(
            QuillAudioSessionCategory(rawValue: category.rawValue) ?? .ambient,
            mode: QuillAudioSessionMode(rawValue: mode.rawValue) ?? .spokenAudio,
            optionsRawValue: options.rawValue
        )
    }

    public func setMode(_ mode: Mode) throws {
        try setCategory(category, mode: mode, options: categoryOptions)
    }

    public func setActive(_ active: Bool, options: SetActiveOptions = []) throws {
        service.setActive(active, optionsRawValue: options.rawValue)
    }
}

public final class AVPlayer: @unchecked Sendable {
    public var currentItem: AVPlayerItem?
    public var audiovisualBackgroundPlaybackPolicy: AVPlayerAudiovisualBackgroundPlaybackPolicy = .automatic
    public var preventsDisplaySleepDuringVideoPlayback: Bool = false
    public var isMuted: Bool = false

    public init() {}
    public init(url: URL) {
        self.currentItem = AVPlayerItem(url: url)
    }

    public func play() {}
    public func pause() {}
    public func seek(to time: CMTime) {
        _ = time
    }
}

public final class AVPlayerItem: @unchecked Sendable {
    public let url: URL?

    public init(url: URL? = nil) {
        self.url = url
    }
}

public enum AVPlayerAudiovisualBackgroundPlaybackPolicy: Sendable {
    case automatic
    case pauses
    case continuesIfPossible
}

public extension Notification.Name {
    static let AVPlayerItemDidPlayToEndTime = Notification.Name("AVPlayerItemDidPlayToEndTimeNotification")
}

public final class AVCaptureDevice: @unchecked Sendable {
    public final class Format: @unchecked Sendable {
        public let formatDescription: CMFormatDescription
        public init(formatDescription: CMFormatDescription = CMFormatDescription()) {
            self.formatDescription = formatDescription
        }
    }

    public struct DeviceType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let builtInWideAngleCamera = DeviceType(rawValue: "wide")
    }

    public enum Position: Int, Sendable { case unspecified, back, front }
    public var activeFormat: Format = Format()

    public static func `default`(for mediaType: AVMediaType) -> AVCaptureDevice? {
        _ = mediaType
        return nil
    }

    public static func `default`(_ deviceType: DeviceType, for mediaType: AVMediaType?, position: Position) -> AVCaptureDevice? {
        _ = (deviceType, mediaType, position)
        return nil
    }
}

// Real AVAudioEngine drives the macOS/iOS CoreAudio graph (input
// node, output node, mixers, effects). The Linux stub stands in
// just enough surface for source-compat: callers can build the
// graph, install taps, start/stop, prepare — all no-ops backed
// by a diagnostic record. Real audio I/O comes when a Linux
// audio backend (PipeWire, ALSA, JACK) is wired up.
public final class AVAudioEngine: @unchecked Sendable {
    private let engineID = UUID()
    private let service = QuillAudioEngineService.shared

    public init() {
        service.registerEngine(engineID)
    }

    public lazy var inputNode: AVAudioInputNode = {
        let node = AVAudioInputNode()
        node.quillEngineID = engineID
        return node
    }()
    public lazy var outputNode: AVAudioOutputNode = {
        let node = AVAudioOutputNode()
        node.quillEngineID = engineID
        return node
    }()
    public lazy var mainMixerNode: AVAudioMixerNode = {
        let node = AVAudioMixerNode()
        node.quillEngineID = engineID
        return node
    }()

    public var isRunning: Bool {
        service.state(for: engineID).isRunning
    }

    public func prepare() {
        service.prepare(engineID: engineID)
    }

    public func start() throws {
        service.start(engineID: engineID)
    }

    public func stop() {
        service.stop(engineID: engineID)
    }

    public func reset() {
        service.reset(engineID: engineID)
    }

    public func attach(_ node: AVAudioNode) {
        node.quillEngineID = engineID
        service.attachNode(engineID: engineID)
    }

    public func connect(
        _ source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat?
    ) {
        source.quillEngineID = engineID
        destination.quillEngineID = engineID
        service.connect(engineID: engineID)
    }
}

public class AVAudioNode: @unchecked Sendable {
    fileprivate let quillNodeID = UUID()
    fileprivate var quillEngineID: UUID?

    public init() {}

    public func installTap(
        onBus bus: Int,
        bufferSize: UInt32,
        format: AVAudioFormat?,
        block tapBlock: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        QuillAudioEngineService.shared.installTap(
            engineID: quillEngineID,
            nodeID: quillNodeID,
            bus: bus
        )
    }

    public func removeTap(onBus bus: Int) {
        QuillAudioEngineService.shared.removeTap(
            engineID: quillEngineID,
            nodeID: quillNodeID,
            bus: bus
        )
    }

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

// MARK: Sample-buffer display

public struct AVLayerVideoGravity: RawRepresentable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let resize = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResize")
    public static let resizeAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspect")
    public static let resizeAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspectFill")
}

public enum AVQueuedSampleBufferRenderingStatus: Int, Sendable {
    case unknown
    case rendering
    case failed
}

public protocol AVQueuedSampleBufferRendering: AnyObject {
    var isReadyForMoreMediaData: Bool { get }
    var status: AVQueuedSampleBufferRenderingStatus { get }
    func enqueue(_ sampleBuffer: CMSampleBuffer)
    func flush()
    func requestMediaDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void)
    func stopRequestingMediaData()
}

open class AVSampleBufferDisplayLayer: CALayer, AVQueuedSampleBufferRendering {
    public var controlTimebase: CMTimebase?
    public var videoGravity: AVLayerVideoGravity = .resizeAspect
    public var preventsCapture: Bool = false
    public var isReadyForMoreMediaData: Bool = true
    public var status: AVQueuedSampleBufferRenderingStatus = .unknown
    public var sampleBufferRenderer: AVQueuedSampleBufferRendering { self }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {}
    public func flush() {}
    public func flushAndRemoveImage() {}
    public func requestMediaDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void) {
        _ = queue
        block()
    }
    public func stopRequestingMediaData() {}
}

public final class AVSampleBufferAudioRenderer: AVQueuedSampleBufferRendering, @unchecked Sendable {
    public var volume: Float = 1
    public var isMuted: Bool = false
    public var isReadyForMoreMediaData: Bool = true
    public var status: AVQueuedSampleBufferRenderingStatus = .unknown

    public init() {}
    public func enqueue(_ sampleBuffer: CMSampleBuffer) {}
    public func flush() {}
    public func requestMediaDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void) {
        _ = queue
        block()
    }
    public func stopRequestingMediaData() {}
}

public final class AVSampleBufferRenderSynchronizer: @unchecked Sendable {
    public let timebase: CMTimebase
    private var renderers: [AVQueuedSampleBufferRendering] = []

    public init() {
        self.timebase = CMTimebase()
    }

    public func addRenderer(_ renderer: AVQueuedSampleBufferRendering) {
        renderers.append(renderer)
    }

    public func removeRenderer(_ renderer: AVQueuedSampleBufferRendering, at time: CMTime) {
        _ = time
        renderers.removeAll { $0 === renderer }
    }

    public func setRate(_ rate: Float, time: CMTime) {
        CMTimebaseSetTime(timebase, time: time)
        CMTimebaseSetRate(timebase, rate: Double(rate))
    }

    public func setRate(_ rate: Double, time: CMTime) {
        CMTimebaseSetTime(timebase, time: time)
        CMTimebaseSetRate(timebase, rate: rate)
    }

    public func currentTime() -> CMTime {
        CMTimebaseGetTime(timebase)
    }
}

// MARK: Assets

public class AVAsset: @unchecked Sendable {
    public init() {}
    /// AVAsset(url:) -- Apple's URL initializer (superseded by AVURLAsset but
    /// still used directly by AttachmentContentValidatorImpl). Inert on Linux (no
    /// media decode); delegates to the no-arg init so the call site compiles.
    public convenience init(url: URL) { self.init() }
    public var isReadable: Bool { false }
    public var isPlayable: Bool { false }
    public var duration: CMTime { .zero }
    public var tracks: [AVAssetTrack] { [] }
    public func tracks(withMediaType mediaType: AVMediaType) -> [AVAssetTrack] { [] }
}

public final class AVURLAsset: AVAsset, @unchecked Sendable {
    public let url: URL
    public let resourceLoader = AVAssetResourceLoader()
    public init(url: URL, options: [AnyHashable: Any]? = nil) {
        self.url = url
        super.init()
    }
}

public final class AVAssetTrack: @unchecked Sendable {
    public var naturalSize: CGSize { .zero }
    public var mediaType: AVMediaType { .video }
    public var preferredTransform: CGAffineTransform { .identity }
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
    public func generateCGImageAsynchronously(
        for requestedTime: CMTime,
        completionHandler handler: @escaping (CGImage?, CMTime, (any Error)?) -> Void
    ) {
        handler(nil, requestedTime, AVMediaUnavailableOnLinux())
    }
}

// MARK: Reader

public class AVAssetReaderOutput: @unchecked Sendable {
    public init() {}
    public func copyNextSampleBuffer() -> CMSampleBuffer? { nil }
}

public final class AVAssetReaderTrackOutput: AVAssetReaderOutput, @unchecked Sendable {
    public let track: AVAssetTrack
    public var alwaysCopiesSampleData: Bool = true
    public init(track: AVAssetTrack, outputSettings: [String: Any]?) {
        self.track = track
        super.init()
    }
}

public final class AVAssetReader: @unchecked Sendable {
    public enum Status: Int, Sendable { case unknown, reading, completed, failed, cancelled }
    public let asset: AVAsset
    public private(set) var outputs: [AVAssetReaderOutput] = []
    public var timeRange: CMTimeRange = CMTimeRange(start: .zero, duration: .zero)
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

// MARK: - Resource loader (custom URL scheme, used for encrypted-attachment playback)
//
// SSK installs a custom AVAssetResourceLoaderDelegate so AVAsset can stream
// decrypted bytes for a private URL scheme. None of the asset machinery does
// anything on Linux, so the delegate is simply never invoked; these types exist
// only so the delegate class and its request-handling code compile.

public final class AVAssetResourceLoader: @unchecked Sendable {
    public var preloadsEligibleContentKeys: Bool = false
    public init() {}
    public func setDelegate(_ delegate: AVAssetResourceLoaderDelegate?, queue: DispatchQueue?) {}
}

public protocol AVAssetResourceLoaderDelegate: AnyObject {
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool
}
public extension AVAssetResourceLoaderDelegate {
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool { false }
}

public final class AVAssetResourceLoadingContentInformationRequest: @unchecked Sendable {
    public var contentType: String?
    public var contentLength: Int64 = 0
    public var isByteRangeAccessSupported: Bool = false
    public var isEntireLengthAvailableOnDemand: Bool = false
    public init() {}
}

public final class AVAssetResourceLoadingDataRequest: @unchecked Sendable {
    public var requestedOffset: Int64 = 0
    public var requestedLength: Int = 0
    public var currentOffset: Int64 = 0
    public var requestsAllDataToEndOfResource: Bool = false
    public init() {}
    public func respond(with data: Data) {}
}

public final class AVAssetResourceLoadingRequest: @unchecked Sendable {
    public var contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?
    public var dataRequest: AVAssetResourceLoadingDataRequest?
    public init() {}
    public func finishLoading() {}
    public func finishLoading(with error: Error?) {}
}

// MARK: - AVAudioPlayer + audio-settings keys

public final class AVAudioPlayer: @unchecked Sendable {
    private let playerID = UUID()
    private let service = QuillAudioPlayerService.shared

    public var duration: TimeInterval {
        service.state(for: playerID)?.duration ?? 0
    }

    public var numberOfChannels: Int {
        service.state(for: playerID)?.numberOfChannels ?? 0
    }

    public var isPlaying: Bool {
        service.state(for: playerID)?.isPlaying ?? false
    }

    public var currentTime: TimeInterval {
        get { service.state(for: playerID)?.currentTime ?? 0 }
        set { service.setCurrentTime(newValue, playerID: playerID) }
    }

    public var deviceCurrentTime: TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    public var volume: Float {
        get { service.state(for: playerID)?.volume ?? 1 }
        set { service.setVolume(newValue, playerID: playerID) }
    }

    public var numberOfLoops: Int {
        get { service.state(for: playerID)?.numberOfLoops ?? 0 }
        set { service.setNumberOfLoops(newValue, playerID: playerID) }
    }

    public init(data: Data) throws {
        let metadata = Self.audioMetadata(from: data)
        service.registerPlayer(
            playerID,
            source: .data(byteCount: data.count),
            duration: metadata.duration,
            numberOfChannels: metadata.channels
        )
    }

    public convenience init(data: Data, fileTypeHint utiString: String?) throws {
        try self.init(data: data)
    }

    public init(contentsOf url: URL) throws {
        let metadata: (duration: TimeInterval, channels: Int)
        if url.isFileURL, let data = try? Data(contentsOf: url) {
            metadata = Self.audioMetadata(from: data)
        } else {
            metadata = (0, 0)
        }
        service.registerPlayer(
            playerID,
            source: .url(url),
            duration: metadata.duration,
            numberOfChannels: metadata.channels
        )
    }

    public convenience init(contentsOf url: URL, fileTypeHint utiString: String?) throws {
        try self.init(contentsOf: url)
    }

    @discardableResult
    public func prepareToPlay() -> Bool {
        service.prepareToPlay(playerID: playerID)
    }

    @discardableResult
    public func play() -> Bool {
        service.play(playerID: playerID)
    }

    @discardableResult
    public func play(atTime time: TimeInterval) -> Bool {
        service.play(playerID: playerID, atTime: time)
    }

    public func pause() {
        service.pause(playerID: playerID)
    }

    public func stop() {
        _ = service.stop(playerID: playerID)
    }

    private static func audioMetadata(from data: Data) -> (duration: TimeInterval, channels: Int) {
        let bytes = Array(data)
        guard bytes.count >= 44,
              bytes[0..<4].elementsEqual([0x52, 0x49, 0x46, 0x46]),
              bytes[8..<12].elementsEqual([0x57, 0x41, 0x56, 0x45])
        else {
            return (0, 0)
        }

        var offset = 12
        var channelCount = 0
        var sampleRate: UInt32 = 0
        var blockAlign: UInt16 = 0
        var dataByteCount: UInt32 = 0

        while offset + 8 <= bytes.count {
            let chunkID = Array(bytes[offset..<(offset + 4)])
            let chunkSize = Int(littleEndianUInt32(bytes, offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, bytes.count)

            if chunkID == [0x66, 0x6d, 0x74, 0x20], chunkStart + 16 <= chunkEnd {
                channelCount = Int(littleEndianUInt16(bytes, chunkStart + 2))
                sampleRate = littleEndianUInt32(bytes, chunkStart + 4)
                blockAlign = littleEndianUInt16(bytes, chunkStart + 12)
            } else if chunkID == [0x64, 0x61, 0x74, 0x61] {
                dataByteCount = UInt32(max(0, chunkEnd - chunkStart))
            }

            offset = chunkStart + chunkSize + (chunkSize % 2)
        }

        guard sampleRate > 0, blockAlign > 0, dataByteCount > 0 else {
            return (0, channelCount)
        }

        let duration = Double(dataByteCount) / Double(sampleRate) / Double(blockAlign)
        return (duration, channelCount)
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

// AVAudioRecorder/AVAssetReaderTrackOutput settings dictionary keys (String on
// Apple). Values are placed into a `[String: Any]` so the concrete value types
// (UInt32 / Int / Bool) don't matter.
public let AVFormatIDKey = "AVFormatIDKey"
public let AVSampleRateKey = "AVSampleRateKey"
public let AVNumberOfChannelsKey = "AVNumberOfChannelsKey"
public let AVLinearPCMBitDepthKey = "AVLinearPCMBitDepthKey"
public let AVLinearPCMIsBigEndianKey = "AVLinearPCMIsBigEndianKey"
public let AVLinearPCMIsFloatKey = "AVLinearPCMIsFloatKey"
public let AVLinearPCMIsNonInterleaved = "AVLinearPCMIsNonInterleaved"
public let AVEncoderAudioQualityKey = "AVEncoderAudioQualityKey"
public let AVEncoderBitRateKey = "AVEncoderBitRateKey"

#endif
