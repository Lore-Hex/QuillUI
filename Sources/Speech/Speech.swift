import Foundation
@_exported import AVFoundation
import QuillKit

public enum SFSpeechRecognizerAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

public final class SFSpeechRecognizer: @unchecked Sendable {
    public var isAvailable: Bool = false

    public init?() {}

    public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        .denied
    }

    public static func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "Speech",
            operation: "requestAuthorization",
            message: "Speech recognition is unavailable until a native Linux backend is attached."
        )
        handler(.denied)
    }

    public func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "Speech",
            operation: "recognitionTask",
            message: "Speech recognition requests are not executed by the compatibility shim."
        )
        return SFSpeechRecognitionTask()
    }
}

public final class SFSpeechAudioBufferRecognitionRequest: @unchecked Sendable {
    public var shouldReportPartialResults = false

    public init() {}

    public func append(_ audioPCMBuffer: AVAudioPCMBuffer) {}
}

public final class SFSpeechRecognitionTask: @unchecked Sendable {
    public init() {}
    public func cancel() {}
}

public final class SFSpeechRecognitionResult: @unchecked Sendable {
    public var isFinal: Bool
    public var bestTranscription: SFTranscription

    public init(isFinal: Bool = true, formattedString: String = "") {
        self.isFinal = isFinal
        self.bestTranscription = SFTranscription(formattedString: formattedString)
    }
}

public struct SFTranscription: Sendable {
    public var formattedString: String

    public init(formattedString: String) {
        self.formattedString = formattedString
    }
}
