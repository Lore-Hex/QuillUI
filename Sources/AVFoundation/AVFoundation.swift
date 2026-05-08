import Foundation
import QuillKit

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
        QuillSpeechBackend.shared.speak(utterance.string) {
            self.delegate?.speechSynthesizer(self, didStart: utterance)
        } onFinish: {
            self.delegate?.speechSynthesizer(self, didFinish: utterance)
        }
    }

    public func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        QuillSpeechBackend.shared.stop()
    }
}

public enum AVSpeechBoundary: Sendable {
    case immediate
}

public final class AVSpeechUtterance: @unchecked Sendable {
    public var string: String
    public var voice: AVSpeechSynthesisVoice?
    public var rate: Float = 0.5

    public init(string: String) {
        self.string = string
    }
}

public struct AVSpeechSynthesisVoice: Hashable, Sendable {
    public struct VoiceQuality: RawRepresentable, Comparable, Hashable, Sendable {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let `default` = VoiceQuality(rawValue: 0)
        public static let enhanced = VoiceQuality(rawValue: 1)
        public static let premium = VoiceQuality(rawValue: 2)

        public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var identifier: String
    public var name: String
    public var quality: VoiceQuality

    public init(identifier: String) {
        self.identifier = identifier
        self.name = identifier
        self.quality = .default
    }

    public init(identifier: String, name: String, quality: VoiceQuality = .default) {
        self.identifier = identifier
        self.name = name
        self.quality = quality
    }

    public static func speechVoices() -> [AVSpeechSynthesisVoice] {
        QuillSpeechBackend.shared.voices().map {
            AVSpeechSynthesisVoice(identifier: $0.identifier, name: $0.name, quality: VoiceQuality(rawValue: $0.quality))
        }
    }
}

public final class AVAudioEngine: @unchecked Sendable {
    public let inputNode = AVAudioInputNode()

    public init() {}

    public func prepare() {}
    public func start() throws {}
    public func stop() {}
}

public final class AVAudioInputNode: @unchecked Sendable {
    public init() {}

    public func outputFormat(forBus bus: Int) -> AVAudioFormat {
        AVAudioFormat()
    }

    public func installTap(
        onBus bus: Int,
        bufferSize: UInt32,
        format: AVAudioFormat?,
        block: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {}

    public func removeTap(onBus bus: Int) {}
}

public final class AVAudioFormat: @unchecked Sendable {
    public init() {}
}

public final class AVAudioPCMBuffer: @unchecked Sendable {
    public init() {}
}

public final class AVAudioTime: @unchecked Sendable {
    public init() {}
}

public final class AVAudioSession: @unchecked Sendable {
    public enum Category: Sendable {
        case playback
        case playAndRecord
    }

    public enum Mode: Sendable {
        case `default`
        case measurement
    }

    public struct CategoryOptions: OptionSet, Sendable {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let duckOthers = CategoryOptions(rawValue: 1 << 0)
    }

    public struct SetActiveOptions: OptionSet, Sendable {
        public var rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1 << 0)
    }

    public init() {}

    public static func sharedInstance() -> AVAudioSession {
        AVAudioSession()
    }

    public func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {}
    public func setActive(_ active: Bool, options: SetActiveOptions = []) throws {}
    public func requestRecordPermission(_ response: @escaping (Bool) -> Void) { response(false) }
}
