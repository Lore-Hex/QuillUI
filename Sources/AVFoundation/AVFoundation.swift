import Foundation
import QuillKit

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
    public func speak(_ utterance: AVSpeechUtterance) {}
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
#endif
