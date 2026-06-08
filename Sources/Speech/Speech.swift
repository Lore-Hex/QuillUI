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
    public var isAvailable: Bool {
        get { QuillSpeechBackend.shared.isSpeechRecognitionAvailable }
        set { QuillSpeechBackend.shared.isSpeechRecognitionAvailable = newValue }
    }

    public init?() {}
    public init?(locale: Locale) {}

    public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        QuillSpeechBackend.shared.speechRecognitionAuthorizationStatus.speechAuthorizationStatus
    }

    public static func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "Speech",
            operation: "requestAuthorization",
            severity: .info,
            message: "Speech authorization is routed through the QuillKit compatibility backend."
        )
        QuillSpeechBackend.shared.requestSpeechRecognitionAuthorization { status in
            handler(status.speechAuthorizationStatus)
        }
    }

    public func recognitionTask(
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "Speech",
            operation: "recognitionTask",
            severity: .info,
            message: "Speech recognition is routed through the QuillKit compatibility backend."
        )
        let task = QuillSpeechBackend.shared.recognitionTask(
            shouldReportPartialResults: request.shouldReportPartialResults
        ) { result, error in
            let speechResult = result.map {
                SFSpeechRecognitionResult(isFinal: $0.isFinal, formattedString: $0.formattedString)
            }
            resultHandler(speechResult, error)
        }
        return SFSpeechRecognitionTask(task: task)
    }
}

public final class SFSpeechAudioBufferRecognitionRequest: @unchecked Sendable {
    public var shouldReportPartialResults = false
    public private(set) var appendedBufferCount = 0

    public init() {}

    public func append(_ audioPCMBuffer: AVAudioPCMBuffer) {
        appendedBufferCount += 1
    }
}

public final class SFSpeechRecognitionTask: @unchecked Sendable {
    private let task: QuillSpeechRecognitionTask

    public init() {
        self.task = QuillSpeechRecognitionTask()
    }

    init(task: QuillSpeechRecognitionTask) {
        self.task = task
    }

    public var isCancelled: Bool { task.isCancelled }

    public func cancel() {
        task.cancel()
    }
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

private extension QuillSpeechRecognitionAuthorizationStatus {
    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        switch self {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        }
    }
}
