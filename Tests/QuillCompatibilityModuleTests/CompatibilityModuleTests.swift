import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import SwiftUI
import SwiftData
import Combine
import QuillKit
import ActivityIndicatorView
import MarkdownUI
import Splash
import OllamaKit
import AsyncAlgorithms
import Carbon
import IOKit
import IOKit.usb
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
        _ = Window("Compatibility", id: "compatibility") {
            Text("Compatibility")
        }
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
        _ = Markdown("# Heading\n\n```swift\nprint(\"Quill\")\n```")
            .markdownCodeSyntaxHighlighter(PlainTextCodeSyntaxHighlighter())
            .markdownTheme(markdownContractTheme)
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

    @Test("AppKit image and KeyboardShortcuts compatibility cover Enchanted full source")
    func appKitImageAndKeyboardShortcutCompatibility() throws {
        let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift])
        let name = KeyboardShortcuts.Name("togglePanelMode", default: shortcut)
        #expect(name.rawValue == "togglePanelMode")
        #expect(name.defaultShortcut == shortcut)
        #expect(KeyboardShortcuts.Shortcut(.character("p")).key == .character("p"))

        let result = try AppleCompatibilitySmoke.runAppKitImageSmoke()
        #expect(result.sizeRoundTrip)
        #expect(result.namedImagePlaceholder)
        #expect(result.bitmapRepresentationRoundTrip)
        #expect(result.windowTabbingRoundTrip)
        #expect(result.operations.isSuperset(of: Set([
            "NSImage.lockFocus",
            "NSImage.draw",
            "NSImage.unlockFocus",
            "NSImage(named:)"
        ])))
    }

    @Test("MarkdownUI and Splash cover Enchanted markdown theme contracts")
    func markdownAndSplashContractsCompile() {
        let configuration = CodeBlockConfiguration(language: "swift", content: "let answer = 42")
        let highlighted = ContractSplashCodeSyntaxHighlighter(theme: .sunset(withFont: .init(size: 16)))
            .highlightCode(configuration.content, language: configuration.language)

        #expect(Markdown.plainText(from: "**bold** [link](https://example.com)") == "bold link (https://example.com)")
        #expect(configuration.language == "swift")
        #expect(highlighted.content.contains("answer"))
        #expect(Splash.Theme.wwdc17(withFont: .init(size: 16)).tokenColors[.keyword] != nil)

        _ = markdownContractTheme
        _ = Text("one") + Text(" two")
        _ = configuration.label
            .relativeLineSpacing(.em(0.225))
            .markdownTextStyle {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .markdownMargin(top: .zero, bottom: .em(0.8))
    }

    @Test("OllamaKit compatibility covers Enchanted model and chat contracts")
    func ollamaKitContractsCompileAndStream() async throws {
        let transport = FakeOllamaTransport(routes: [
            "/api/version": (200, #"{"version":"0.6.0"}"#),
            "/api/tags": (200, #"{"models":[{"name":"llava:latest","details":{"families":["clip"]}},{"name":"llama3.2:latest"}]}"#),
            "/api/chat": (
                200,
                """
                {"message":{"role":"assistant","content":"Hel"},"done":false}
                {"message":{"role":"assistant","content":"lo"},"done":false}
                {"done":true}
                """
            )
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            bearerToken: "secret",
            transport: transport
        )

        #expect(await kit.reachable())

        let models = try await kit.models()
        #expect(models.models.map(\.name) == ["llava:latest", "llama3.2:latest"])
        #expect(models.models.first?.details.families == ["clip"])

        var request = OKChatRequestData(
            model: "llava:latest",
            messages: [
                .init(role: .system, content: "short"),
                .init(role: .user, content: "describe", images: ["base64"])
            ]
        )
        request.options = OKCompletionOptions(temperature: 0)

        var values: [OKChatResponse] = []
        var finished = false
        var failure: Error?
        let cancellable = kit.chat(data: request)
            .sink { completion in
                switch completion {
                case .finished:
                    finished = true
                case .failure(let error):
                    failure = error
                }
            } receiveValue: { response in
                values.append(response)
            }

        let deadline = Date().addingTimeInterval(1)
        while !finished && failure == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        cancellable.cancel()

        #expect(failure == nil)
        #expect(finished)
        #expect(values.map { $0.message?.content ?? "" }.joined() == "Hello")
        #expect(values.last?.done == true)
        #expect(transport.requests.contains { $0.path == "/api/chat" && $0.authorization == "Bearer secret" })
        #expect(transport.chatBody?.contains(#""stream":true"#) == true)

        let sessionBackedKit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            bearerToken: "secret",
            session: "compat-session"
        )
        #expect(sessionBackedKit.baseURL.absoluteString == "http://localhost:11434")
        #expect(sessionBackedKit.bearerToken == "secret")
    }

    @Test("OllamaKit compatibility reports HTTP and stream parse failures")
    func ollamaKitErrorContractsAreDeterministic() async throws {
        let transport = FakeOllamaTransport(routes: [
            "/api/version": (503, #"{"error":"down"}"#),
            "/api/tags": (500, #"{"error":"boom"}"#)
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            transport: transport
        )

        #expect(await kit.reachable() == false)
        await #expect(throws: OllamaKitError.self) {
            _ = try await kit.models()
        }
        #expect(throws: (any Error).self) {
            _ = try OllamaKit.decodeChatResponses(from: Data("not-json\n".utf8))
        }
    }

    @Test("AsyncAlgorithms and Carbon compatibility cover prompt-panel imports")
    func asyncAlgorithmsAndCarbonContractsCompile() async {
        var iterator = AsyncTimerSequence(interval: .milliseconds(1), clock: .continuous).makeAsyncIterator()
        let firstTick = await iterator.next()

        #expect(firstTick != nil)
        #expect(CarbonCompatibility.available == false)
    }

    @Test("IOKit USB compatibility covers Quill USB watcher imports")
    func ioKitUSBContractsCompile() {
        var iterator: io_iterator_t = 99
        let port = IONotificationPortCreate(kIOMainPortDefault)
        let callback: IOServiceMatchingCallback = { _, iterator in
            _ = IOIteratorNext(iterator)
        }

        IONotificationPortSetDispatchQueue(port, nil)
        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            nil,
            callback,
            nil,
            &iterator
        )

        #expect(result == kIOReturnUnsupported)
        #expect(iterator == 0)
        #expect(IOIteratorNext(iterator) == 0)
        #expect(IOObjectRelease(iterator) == kIOReturnSuccess)
        #expect(kIOUSBDeviceClassName == "IOUSBDevice")
        #expect(kUSBVendorID == "idVendor")
        #expect(kUSBProductID == "idProduct")

        IONotificationPortDestroy(port)
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

    @Test("os Logger compatibility records privacy-aware diagnostics")
    func osLoggerCompatibilityRecordsDiagnostics() {
        let result = AppleCompatibilitySmoke.runOSLogSmoke()
        #expect(result.operations.contains("Logger.info"))
        #expect(result.operations.contains("Logger.error"))
        #expect(result.renderedPublicValue)
        #expect(result.redactedPrivateValue)
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
            "registerSingleUseSpace",
            "trustEvaluation",
            "launchAtLogin"
        ])))
    }

    @Test("previously-silent QuillUI stubs now record diagnostics")
    func previouslySilentStubsRecordDiagnostics() throws {
        QuillCompatibilityDiagnostics.shared.clear()

        // Bindings: previously returned self with no diagnostic.
        let binding: Binding<Int> = .constant(0)
        _ = binding.animation()
        _ = binding.animation(.easeOut(duration: 0.1))

        // listStyle(PlainListStyle): previously returned self with no diagnostic.
        _ = Text("List row").listStyle(PlainListStyle())

        // Animation chain methods: previously returned self with no diagnostic.
        _ = Animation.snappy()
        _ = Animation.snappy(duration: 0.5)
        _ = Animation.easeOut(duration: 0.2).repeatForever(autoreverses: true)
        _ = Animation.easeOut(duration: 0.2).delay(0.4)

        // ImageRenderer: previously returned nil with no diagnostic.
        let renderer = ImageRenderer(content: Text("rendered"))
        #expect(renderer.uiImage == nil)
        #expect(renderer.nsImage == nil)
        #expect(Image(systemName: "photo").render() == nil)
        let platformImage = PlatformImage(data: Data([1, 2, 3]))
        #expect(platformImage.convertImageToBase64String() == "AQID")
        #expect(platformImage.aspectFittedToHeight(200).data == Data([1, 2, 3]))
        #expect(platformImage.compressImageData() == Data([1, 2, 3]))

        // NSImage.tiffRepresentation: previously returned wrong bytes silently.
        let nsImage = NSImage(data: Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(nsImage?.tiffRepresentation == Data([0x89, 0x50, 0x4E, 0x47]))

        let events = QuillCompatibilityDiagnostics.shared.events
        let operations = Set(events.map(\.operation))

        #expect(operations.isSuperset(of: Set([
            "Binding.animation",
            "listStyle(PlainListStyle)",
            "Animation.snappy",
            "Animation.repeatForever",
            "Animation.delay",
            "ImageRenderer.init",
            "ImageRenderer.uiImage",
            "ImageRenderer.nsImage",
            "Image.render",
            "PlatformImage.aspectFittedToHeight",
            "PlatformImage.compressImageData",
            "NSImage.tiffRepresentation"
        ])))

        // Severity: stubs that just no-op are .info; stubs that return wrong/missing
        // data (NSImage tiff lie, ImageRenderer always-nil) are .warning so they
        // surface louder in any diagnostic UI that filters by severity.
        let severitiesByOperation = Dictionary(
            grouping: events,
            by: \.operation
        ).mapValues { Set($0.map(\.severity)) }

        #expect(severitiesByOperation["Binding.animation"]?.contains(.info) == true)
        #expect(severitiesByOperation["listStyle(PlainListStyle)"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.repeatForever"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.delay"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.snappy"]?.contains(.warning) == true)
        #expect(severitiesByOperation["NSImage.tiffRepresentation"]?.contains(.warning) == true)
        #expect(severitiesByOperation["ImageRenderer.uiImage"]?.contains(.warning) == true)
        #expect(severitiesByOperation["ImageRenderer.nsImage"]?.contains(.warning) == true)
        #expect(severitiesByOperation["Image.render"]?.contains(.warning) == true)
        #expect(severitiesByOperation["PlatformImage.aspectFittedToHeight"]?.contains(.warning) == true)
        #expect(severitiesByOperation["PlatformImage.compressImageData"]?.contains(.warning) == true)
    }

    @Test("Image(data:) deduplicates identical bytes within a process")
    func imageDataInitDeduplicatesIdenticalBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUIImages", isDirectory: true)

        // Snapshot existing files so we measure only the delta from this test.
        let before = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        // Make the bytes unique to this test run so we don't collide with other
        // tests' images that may share content.
        let unique = "quill-image-dedup-\(UUID().uuidString)".data(using: .utf8)!

        // Same bytes, three calls — should write exactly one file.
        _ = Image(data: unique)
        _ = Image(data: unique)
        _ = Image(data: unique)

        let after = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let added = Set(after).subtracting(Set(before))
        #expect(added.count == 1, "Image(data:) should write a single PNG for repeated identical bytes; instead wrote \(added.count): \(added.sorted())")

        // Different bytes should write a second file.
        let unique2 = "quill-image-dedup-2-\(UUID().uuidString)".data(using: .utf8)!
        _ = Image(data: unique2)

        let afterSecond = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let addedSecond = Set(afterSecond).subtracting(Set(before))
        #expect(addedSecond.count == 2, "Image(data:) with new bytes should add a second PNG; saw \(addedSecond.count) total new files")
    }

    // MARK: - Symbol name remapping

    @Test("QuillSystemSymbol remaps known SF Symbol names and passes unknown through")
    func quillSystemSymbolMapsKnownAndPassesUnknown() {
        let knownMappings: [(input: String, expected: String)] = [
            ("paperplane.fill", "arrow.forward.circle.fill"),
            ("photo", "folder.badge.plus"),
            ("photo.fill", "folder.badge.plus"),
            ("lightbulb", "info.circle"),
            ("lightbulb.circle", "info.circle"),
            ("lightbulb.circle.fill", "info.circle"),
            ("character.cursor.ibeam", "doc.text"),
            ("textformat", "doc.text"),
            ("textformat.abc", "doc.text"),
            ("keyboard", "doc.on.doc"),
            ("waveform", "ellipsis.circle")
        ]

        for (input, expected) in knownMappings {
            #expect(
                QuillSystemSymbol.compatibleName(input) == expected,
                "Expected \(input) -> \(expected); got \(QuillSystemSymbol.compatibleName(input))"
            )
        }

        // Unknown names pass through unchanged so apps requesting symbols Quill
        // hasn't aliased yet still render the original token.
        #expect(QuillSystemSymbol.compatibleName("unknown.symbol.name") == "unknown.symbol.name")
        #expect(QuillSystemSymbol.compatibleName("") == "")
    }

    // MARK: - AppStorage round-trip

    @Test("AppStorage persists values across reads for every supported scalar type")
    func appStorageRoundTripsScalarValues() {
        let suffix = UUID().uuidString
        let stringKey = "quill.test.string.\(suffix)"
        let boolKey = "quill.test.bool.\(suffix)"
        let intKey = "quill.test.int.\(suffix)"
        let doubleKey = "quill.test.double.\(suffix)"

        defer {
            UserDefaults.standard.removeObject(forKey: stringKey)
            UserDefaults.standard.removeObject(forKey: boolKey)
            UserDefaults.standard.removeObject(forKey: intKey)
            UserDefaults.standard.removeObject(forKey: doubleKey)
        }

        // Default values are returned when the key has never been written.
        #expect(AppStorage(wrappedValue: "default-string", stringKey).wrappedValue == "default-string")
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == true)
        #expect(AppStorage(wrappedValue: 42, intKey).wrappedValue == 42)
        #expect(AppStorage(wrappedValue: 3.14, doubleKey).wrappedValue == 3.14)

        // Writing through one wrapper and reading from a fresh wrapper proves
        // the value persisted to UserDefaults rather than just to local state.
        let stringStorage = AppStorage(wrappedValue: "ignored", stringKey)
        stringStorage.wrappedValue = "written"
        #expect(AppStorage(wrappedValue: "fallback", stringKey).wrappedValue == "written")

        let boolStorage = AppStorage(wrappedValue: false, boolKey)
        boolStorage.wrappedValue = true
        #expect(AppStorage(wrappedValue: false, boolKey).wrappedValue == true)
        boolStorage.wrappedValue = false
        // After explicit false write, value reads back as false (not the
        // wrapped default). Tests the object-existence guard in the read path.
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == false)

        let intStorage = AppStorage(wrappedValue: 0, intKey)
        intStorage.wrappedValue = 7
        #expect(AppStorage(wrappedValue: 0, intKey).wrappedValue == 7)

        let doubleStorage = AppStorage(wrappedValue: 0.0, doubleKey)
        doubleStorage.wrappedValue = 2.5
        #expect(AppStorage(wrappedValue: 0.0, doubleKey).wrappedValue == 2.5)
    }

    @Test("AppStorage encodes RawRepresentable enums via their raw value")
    func appStorageEncodesRawRepresentableEnums() {
        let key = "quill.test.mode.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Default value when nothing is stored.
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .classic)

        let storage = AppStorage(wrappedValue: AppStorageMode.classic, key)
        storage.wrappedValue = .modern
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .modern)
        // Underlying storage uses the rawValue, not Codable JSON.
        #expect(UserDefaults.standard.string(forKey: key) == "modern")

        // A garbage rawValue at the storage key falls back to the default.
        UserDefaults.standard.set("not-a-case", forKey: key)
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .classic)
    }

    // MARK: - File importer

    @Test("QuillFileImporter honors test-injected selection and validates types")
    func quillFileImporterUsesTestSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillFileImporterTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pngURL = directory.appendingPathComponent("hello.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
            QuillFileImporter.setTestSelection(nil)
        }

        QuillFileImporter.setTestSelection(pngURL)

        // Happy path: PNG conforms to image / png.
        switch QuillFileImporter.selectURL(allowedContentTypes: [.image]) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)")
        }

        switch QuillFileImporter.selectURL(allowedContentTypes: [.png]) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected png to match png allowedType: \(error)")
        }

        // Empty allowedContentTypes accepts any URL (matches SwiftUI behavior).
        switch QuillFileImporter.selectURL(allowedContentTypes: []) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected empty allowedTypes to accept any URL: \(error)")
        }

        // Mismatched type fails with the right error case.
        switch QuillFileImporter.selectURL(allowedContentTypes: [.jpeg]) {
        case .success:
            Issue.record("Expected jpeg-only allowedTypes to reject a .png URL")
        case .failure(let error):
            guard let quillError = error as? QuillCompatibilityError else {
                Issue.record("Expected QuillCompatibilityError, got \(type(of: error)): \(error)")
                return
            }
            switch quillError {
            case .unsupportedFileSelection(let url, let allowed):
                #expect(url == pngURL)
                #expect(allowed == [.jpeg])
            default:
                Issue.record("Expected .unsupportedFileSelection, got \(quillError)")
            }
        }
    }

    // MARK: - UTType behavior

    @Test("UTType infers types from file extensions and reports conformance")
    func utTypeInfersAndConforms() {
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.png")) == .png)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.PNG")) == .png)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.jpeg")) == .jpeg)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.jpg")) == .jpeg)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.tiff")) == .tiff)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.tif")) == .tiff)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/document.txt")) == nil)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/no-extension")) == nil)

        // Identity conformance.
        #expect(UTType.png.conforms(to: .png))
        #expect(UTType.jpeg.conforms(to: .jpeg))

        // png/jpeg/tiff conform to the image supertype but a custom type does not.
        #expect(UTType.png.conforms(to: .image))
        #expect(UTType.jpeg.conforms(to: .image))
        #expect(UTType.tiff.conforms(to: .image))
        #expect(UTType("public.text").conforms(to: .image) == false)

        // Unrelated concrete types do not conform to each other.
        #expect(UTType.png.conforms(to: .jpeg) == false)
    }

    // MARK: - NSItemProvider data flow

    @Test("NSItemProvider delivers data and file representations matching content type")
    func nsItemProviderDeliversMatchingRepresentations() throws {
        let payload = Data([0xCA, 0xFE, 0xBA, 0xBE])

        // Data-backed provider, matching type.
        let dataProvider = NSItemProvider(data: payload, type: .png)
        let dataCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .png) { data, error in
            dataCaptured.value = (data, error)
        }
        #expect(dataCaptured.value?.0 == payload)
        #expect(dataCaptured.value?.1 == nil)

        // Data-backed provider, image supertype matches concrete png too.
        let imgCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .image) { data, error in
            imgCaptured.value = (data, error)
        }
        #expect(imgCaptured.value?.0 == payload)
        #expect(imgCaptured.value?.1 == nil)

        // Data-backed provider, mismatched type produces an error.
        let mismatchCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .jpeg) { data, error in
            mismatchCaptured.value = (data, error)
        }
        #expect(mismatchCaptured.value?.0 == nil)
        #expect((mismatchCaptured.value?.1 as? QuillCompatibilityError) == .representationUnavailable("public.jpeg"))

        // File-backed provider reads bytes from the URL.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillItemProviderTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("payload.png")
        try payload.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileProvider = NSItemProvider(fileURL: fileURL)
        let fileCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = fileProvider.loadDataRepresentation(for: .png) { data, error in
            fileCaptured.value = (data, error)
        }
        #expect(fileCaptured.value?.0 == payload)
        #expect(fileCaptured.value?.1 == nil)

        // Empty provider always errors.
        let empty = NSItemProvider()
        let emptyCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = empty.loadDataRepresentation(for: .png) { data, error in
            emptyCaptured.value = (data, error)
        }
        #expect(emptyCaptured.value?.0 == nil)
        #expect(emptyCaptured.value?.1 != nil)
    }

    // MARK: - OpenURLAction custom handler

    @Test("OpenURLAction routes URLs through the configured handler")
    func openURLActionInvokesCustomHandler() {
        let captured = QuillTestBox<URL>()
        let action = OpenURLAction { url in
            captured.value = url
            return true
        }

        let url = URL(string: "https://quill.test/path?q=1")!
        let result = action(url)
        #expect(result == true)
        #expect(captured.value == url)

        // Returning false from the handler propagates.
        let rejecting = OpenURLAction { _ in false }
        #expect(rejecting(URL(string: "https://example.com")!) == false)
    }

    // MARK: - QuillMenuAction divider + disabled semantics

    @Test("QuillMenuAction divider is a divider and disabled actions never run")
    func quillMenuActionDividerAndDisabled() {
        let divider = QuillMenuAction.divider()
        #expect(divider.kind == .divider)
        // Calling perform() on a divider must not crash; the synthesized
        // empty closure is a no-op. Idempotent.
        divider.perform()
        divider.perform()

        // Disabled action does not invoke its closure.
        let disabledRan = QuillTestBox<Bool>(false)
        let disabled = QuillMenuAction(
            title: "Disabled",
            isDisabled: true,
            action: { disabledRan.value = true }
        )
        disabled.perform()
        #expect(disabledRan.value == false)

        // Enabled action invokes its closure exactly once per perform().
        let enabledCount = QuillTestBox<Int>(0)
        let enabled = QuillMenuAction(title: "Enabled") {
            enabledCount.value = (enabledCount.value ?? 0) + 1
        }
        enabled.perform()
        enabled.perform()
        #expect(enabledCount.value == 2)

        // Unspecified id falls back to the title.
        #expect(enabled.id == "Enabled")
        let withCustomID = QuillMenuAction(id: "explicit", title: "Title") {}
        #expect(withCustomID.id == "explicit")
    }
}

/// RawRepresentable enum for AppStorage round-trip tests. Defined at file
/// scope so its `RawValue` (String) is stable across compilations.
private enum AppStorageMode: String {
    case classic
    case modern
}

/// Tiny mutable reference container for capturing values out of closures in
/// tests without fighting Swift Testing's capture-list rules.
private final class QuillTestBox<Value>: @unchecked Sendable {
    var value: Value?

    init(_ value: Value? = nil) {
        self.value = value
    }
}

private struct CompatibilityModel: PersistentModel, Codable, Equatable {
    var id: String = UUID().uuidString
}

private final class FakeOllamaTransport: OllamaKitTransport, @unchecked Sendable {
    struct CapturedRequest: Sendable {
        var path: String
        var authorization: String?
    }

    private let routes: [String: (status: Int, body: String)]
    private let lock = NSLock()
    private var capturedRequests: [CapturedRequest] = []
    private var capturedChatBody: String?

    init(routes: [String: (Int, String)]) {
        self.routes = routes.mapValues { (status: $0.0, body: $0.1) }
    }

    var requests: [CapturedRequest] {
        lock.withLock { capturedRequests }
    }

    var chatBody: String? {
        lock.withLock { capturedChatBody }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? "/"
        lock.withLock {
            capturedRequests.append(
                CapturedRequest(
                    path: path,
                    authorization: request.value(forHTTPHeaderField: "Authorization")
                )
            )
            if path == "/api/chat", let httpBody = request.httpBody {
                capturedChatBody = String(data: httpBody, encoding: .utf8)
            }
        }

        let route = routes[path] ?? (404, #"{"error":"missing"}"#)
        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: route.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(route.body.utf8), response)
    }
}

private let markdownContractTheme = MarkdownUI.Theme()
    .text {
        FontSize(14)
    }
    .code {
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.85))
        BackgroundColor(Color("bgCustom"))
    }
    .strong {
        FontWeight(.semibold)
    }
    .link {
        ForegroundColor(.blue)
    }
    .heading1 { configuration in
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .relativePadding(.bottom, length: .em(0.3))
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(2))
                }
            Divider().overlay(Color.gray)
        }
    }
    .paragraph { configuration in
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(0.25))
            .markdownMargin(top: 0, bottom: 16)
    }
    .blockquote { configuration in
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray)
                .relativeFrame(width: .em(0.2))
            configuration.label
                .markdownTextStyle { ForegroundColor(.secondary) }
                .relativePadding(.horizontal, length: .em(1))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    .codeBlock { configuration in
        VStack(spacing: 0) {
            Text(configuration.language ?? "code")
                .font(.system(size: 13, design: .monospaced))
                .fontWeight(.semibold)
            configuration.label
                .relativeLineSpacing(.em(0.225))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
        }
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }
    .listItem { configuration in
        configuration.label.padding(.bottom, 10)
    }
    .taskListMarker { configuration in
        Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.gray, Color("bgCustom"))
            .imageScale(.small)
            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
    }
    .table { configuration in
        configuration.label
            .markdownTableBorderStyle(.init(color: .gray))
            .markdownTableBackgroundStyle(.alternatingRows(.white, Color("bgCustom")))
            .markdownMargin(top: 0, bottom: 16)
    }
    .tableCell { configuration in
        configuration.label
            .markdownTextStyle {
                if configuration.row == 0 {
                    FontWeight(.semibold)
                }
                BackgroundColor(nil)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .relativeLineSpacing(.em(0.25))
    }
    .thematicBreak {
        Divider()
            .relativeFrame(height: .em(0.25))
            .overlay(Color.gray)
            .markdownMargin(top: 24, bottom: 24)
    }

private struct ContractSplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let highlighter: SyntaxHighlighter<ContractTextOutputFormat>

    init(theme: Splash.Theme) {
        self.highlighter = SyntaxHighlighter(format: ContractTextOutputFormat(theme: theme))
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        guard language != nil else { return Text(content) }
        return highlighter.highlight(content)
    }
}

private struct ContractTextOutputFormat: OutputFormat {
    var theme: Splash.Theme

    func makeBuilder() -> Builder {
        Builder(theme: theme)
    }

    struct Builder: OutputBuilder {
        var theme: Splash.Theme
        var accumulatedText: [Text] = []

        mutating func addToken(_ token: String, ofType type: TokenType) {
            let color = theme.tokenColors[type] ?? theme.plainTextColor
            accumulatedText.append(Text(token).foregroundColor(.init(color)))
        }

        mutating func addPlainText(_ text: String) {
            accumulatedText.append(Text(text).foregroundColor(.init(theme.plainTextColor)))
        }

        mutating func addWhitespace(_ whitespace: String) {
            accumulatedText.append(Text(whitespace))
        }

        func build() -> Text {
            accumulatedText.reduce(Text(""), +)
        }
    }
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
