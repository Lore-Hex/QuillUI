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
    public func stopSpeaking(at boundary: Any) {}
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

public final class AVAudioEngine: @unchecked Sendable {
    public init() {}
}
#endif
