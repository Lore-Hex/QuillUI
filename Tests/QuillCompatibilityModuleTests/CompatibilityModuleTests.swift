import Foundation
import Testing
import SwiftUI
import SwiftData
import Combine
import QuillKit
import ActivityIndicatorView
import WrappingHStack
import Vortex
import KeyboardShortcuts

@Suite("Linux compatibility import modules", .serialized)
struct CompatibilityModuleTests {
    @Test("SwiftUI and SwiftData module aliases expose Quill APIs")
    func swiftUIAndSwiftDataAliasesExposeQuillAPIs() throws {
        _ = Text("Quill")
            .foregroundStyle(Color("label"))
            .matchedGeometryEffect(id: "title", in: Namespace().wrappedValue)
        _ = ModelConfiguration(isStoredInMemoryOnly: true)
        _ = FetchDescriptor<CompatibilityModel>()
    }

    @Test("QuillUI fallback modifiers record diagnostics")
    func quillUIFallbackModifiersRecordDiagnostics() {
        QuillCompatibilityDiagnostics.shared.clear()

        _ = Text("Fallback")
            .symbolEffect(.variableColor, value: true)
            .matchedGeometryEffect(id: "title", in: Namespace().wrappedValue)
            .mask(Rectangle())
            .contentShape(Rectangle())
            .keyboardType(.URL)
            .autocapitalization(.never)
            .disableAutocorrection(true)
            .textContentType(.URL)

        _ = Image(systemName: "photo").renderingMode(.template)
        _ = Form { Text("Field") }.formStyle(.grouped)

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.isSuperset(of: Set([
            "symbolEffect",
            "matchedGeometryEffect",
            "mask",
            "contentShape",
            "keyboardType",
            "autocapitalization",
            "disableAutocorrection",
            "textContentType",
            "renderingMode",
            "formStyle"
        ])))
    }

    @Test("third-party UI packages compile to visible SwiftUI-shaped views")
    func thirdPartyUIShimsCompile() {
        _ = ActivityIndicatorView(isVisible: .constant(true), type: .rotatingDots(count: 5))
        _ = ActivityIndicatorView(isVisible: .constant(true), type: .growingCircle)
        _ = WrappingHStack(alignment: .leading) {
            Text("One")
            Text("Two")
        }
        _ = VortexView(.splash.makeUniqueCopy()) {
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
        }
        _ = KeyboardShortcuts.Recorder("Keyboard shortcut", name: "togglePanelMode")
        _ = Text("Shortcut").onKeyboardShortcut("togglePanelMode", type: .keyDown) {}
    }

    @Test("Apple service modules provide diagnostic Linux fallbacks")
    func appleServiceModulesCompile() throws {
        #expect(QuillKitPlatform.current == .linux)
        #expect(QuillKitCapabilities.status(for: .clipboard) == .emulated)
        let result = try AppleCompatibilitySmoke.runAppleServiceSmoke()
        #expect(result.pasteboardString == "hello")
        #expect(result.uiPasteboardString == "hello")
        #expect(result.imagesRoundTrip)
        #expect(result.speechStopSucceeded)
        #expect(result.speechRecognitionUnavailable)
        #expect(result.launchServiceEnabled)
        #expect(result.launchServiceDisabled)
        #expect(result.updaterUnavailable)
    }

    @Test("Security CoreGraphics Accessibility and Alamofire adapters compile")
    func lowerLevelServiceModulesCompile() throws {
        #expect(try AppleCompatibilitySmoke.runLowerLevelServiceSmoke())
    }

    @Test("Combine compatibility publishers support cancellation and timer sinks")
    func combineNoOpPublishersCompile() {
        let cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in }
        cancellable.cancel()

        let publisher = AnyPublisher<Int, Never>()
            .map { $0 > 0 }
            .eraseToAnyPublisher()
        let mappedCancellable = publisher.sink { _ in }
        mappedCancellable.cancel()

        var stored = Set<AnyCancellable>()
        Just(1)
            .eraseToAnyPublisher()
            .sink { _ in }
            .store(in: &stored)
        #expect(stored.count == 1)
    }

    @Test("Combine compatibility publishers deliver completion edge cases")
    func combineCompletionEdgeCases() {
        var justEvents: [String] = []
        let justCancellable = Just("value")
            .eraseToAnyPublisher()
            .sink { completion in
                if case .finished = completion {
                    justEvents.append("finished")
                }
            } receiveValue: { value in
                justEvents.append(value)
            }
        justCancellable.cancel()
        #expect(justEvents == ["value", "finished"])

        var emptyCompleted = false
        _ = Empty<Int, Never>()
            .eraseToAnyPublisher()
            .sink { completion in
                if case .finished = completion {
                    emptyCompleted = true
                }
            } receiveValue: { _ in }
        #expect(emptyCompleted)

        var lazyEmptyCompleted = false
        _ = Empty<Int, Never>(completeImmediately: false)
            .eraseToAnyPublisher()
            .sink { _ in lazyEmptyCompleted = true } receiveValue: { _ in }
        #expect(lazyEmptyCompleted == false)

        var failedWithBoom = false
        _ = Fail<Int, CombineTestError>(error: .boom)
            .eraseToAnyPublisher()
            .sink { completion in
                if case .failure(.boom) = completion {
                    failedWithBoom = true
                }
            } receiveValue: { _ in
                Issue.record("Fail publisher should not emit values")
            }
        #expect(failedWithBoom)
    }

    @Test("Combine subjects and merge deliver values from both inputs")
    func combineSubjectsAndMergeDeliverValues() {
        let first = PassthroughSubject<Int, Never>()
        let second = PassthroughSubject<Int, Never>()
        var values: [Int] = []

        let cancellable = Publishers.Merge(first, second)
            .eraseToAnyPublisher()
            .sink { values.append($0) }

        first.send(1)
        second.send(2)
        cancellable.cancel()
        first.send(3)

        #expect(values == [1, 2])
    }

    @Test("Combine merge buffers values beyond current downstream demand")
    func combineMergeBuffersBeyondCurrentDemand() {
        let first = PassthroughSubject<Int, Never>()
        let second = PassthroughSubject<Int, Never>()
        let subscriber = DemandRecordingSubscriber<Int, Never>()

        Publishers.Merge(first, second).subscribe(subscriber)
        subscriber.subscription?.request(.max(1))

        first.send(1)
        second.send(2)
        #expect(subscriber.values == [1])
        #expect(subscriber.completions == 0)

        subscriber.subscription?.request(.max(1))
        #expect(subscriber.values == [1, 2])

        first.send(completion: .finished)
        #expect(subscriber.completions == 0)
        second.send(completion: .finished)
        #expect(subscriber.completions == 1)
    }

    @Test("Combine subject completion is terminal")
    func combineSubjectCompletionIsTerminal() {
        let subject = PassthroughSubject<Int, Never>()
        var values: [Int] = []
        var completions = 0

        let cancellable = subject.eraseToAnyPublisher().sink { completion in
            if case .finished = completion {
                completions += 1
            }
        } receiveValue: { value in
            values.append(value)
        }

        subject.send(1)
        subject.send(completion: .finished)
        subject.send(2)
        cancellable.cancel()

        var lateSubscriberCompleted = false
        _ = subject.eraseToAnyPublisher().sink { completion in
            if case .finished = completion {
                lateSubscriberCompleted = true
            }
        } receiveValue: { _ in
            Issue.record("Completed subjects should not emit values to late subscribers")
        }

        #expect(values == [1])
        #expect(completions == 1)
        #expect(lateSubscriberCompleted)
    }

    @Test("Combine timer and notification publishers emit values")
    func combineTimerAndNotificationPublishersEmitValues() throws {
        var timerEvents = 0
        let runLoop = RunLoop.current
        let timer = Timer.publish(every: 0.01, on: runLoop, in: .default)
            .autoconnect()
            .sink { _ in
                timerEvents += 1
            }

        let deadline = Date().addingTimeInterval(1)
        while timerEvents == 0, Date() < deadline {
            _ = runLoop.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        timer.cancel()
        #expect(timerEvents >= 1)

        let name = Notification.Name("quill.combine.notification.\(UUID().uuidString)")
        var notifications: [Notification] = []
        let notificationCancellable = NotificationCenter.default.publisher(for: name)
            .sink { notification in
                notifications.append(notification)
            }

        NotificationCenter.default.post(name: name, object: "payload")
        notificationCancellable.cancel()
        NotificationCenter.default.post(name: name, object: "ignored")

        #expect(notifications.count == 1)
        #expect(notifications.first?.object as? String == "payload")
    }

    @Test("Combine subject cancellation is scoped to the cancelled subscriber")
    func combineSubjectCancellationIsScoped() {
        let subject = PassthroughSubject<Int, Never>()
        var firstValues: [Int] = []
        var secondValues: [Int] = []

        let first = subject.eraseToAnyPublisher().sink { firstValues.append($0) }
        let second = subject.eraseToAnyPublisher().sink { secondValues.append($0) }

        subject.send(1)
        first.cancel()
        first.cancel()
        subject.send(2)
        second.cancel()
        subject.send(3)

        #expect(firstValues == [1])
        #expect(secondValues == [1, 2])
    }

    @Test("AnyCancellable cancellation is idempotent")
    func anyCancellableCancellationIsIdempotent() {
        var cancelCount = 0
        let cancellable = AnyCancellable {
            cancelCount += 1
        }

        cancellable.cancel()
        cancellable.cancel()

        #expect(cancelCount == 1)
    }

    @Test("platform fallback shims record diagnostics")
    func platformFallbacksRecordDiagnostics() throws {
        let result = try AppleCompatibilitySmoke.runDiagnosticFallbackSmoke()
        #expect(result.speechAuthorizationDenied)
        #expect(result.operations.isSuperset(of: Set([
            "impactOccurred",
            "notificationOccurred",
            "speechSynthesis",
            "requestAuthorization",
            "recognitionTask",
            "keyState",
            "postEvent",
            "trustEvaluation",
            "launchAtLogin"
        ])))
    }
}

private struct CompatibilityModel: PersistentModel, Codable, Equatable {
    var id: String = UUID().uuidString
}

private enum CombineTestError: Error {
    case boom
}

private final class DemandRecordingSubscriber<Input, Failure: Error>: Subscriber {
    var subscription: Subscription?
    var values: [Input] = []
    var completions = 0

    func receive(subscription: Subscription) {
        self.subscription = subscription
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        values.append(input)
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        completions += 1
    }
}
