import Foundation

#if os(Linux)
#if !QUILLUI_NO_FOUNDATION_MODELS_MACROS
@attached(member)
public macro Generable() = #externalMacro(module: "QuillDataMacros", type: "QuillObservableMacro")

@attached(peer)
public macro Guide(
    description: String,
    _ options: GuideOption...
) = #externalMacro(module: "QuillDataMacros", type: "QuillAttributeMacro")
#endif

public struct GuideOption: Sendable {
    public init() {}
    public static func count(_ value: Int) -> GuideOption {
        _ = value
        return GuideOption()
    }
}

@available(iOS 26.0, *)
public struct SystemLanguageModel: Sendable {
    public static let `default` = SystemLanguageModel()
    public var isAvailable: Bool { false }
    public init() {}
}

@available(iOS 26.0, *)
public struct LanguageModelSession: Sendable {
    public struct Model: Sendable {
        public enum UseCase: Sendable {
            case general
        }

        public let useCase: UseCase

        public init(useCase: UseCase) {
            self.useCase = useCase
        }
    }

    public struct GenerationOptions: Sendable {
        public let temperature: Double

        public init(temperature: Double = 1.0) {
            self.temperature = temperature
        }
    }

    public struct Response<Content>: Sendable where Content: Sendable {
        public let content: Content

        public init(content: Content) {
            self.content = content
        }
    }

    public struct ResponseStream<Content>: AsyncSequence, Sendable where Content: Sendable {
        public typealias Element = Response<Content>

        public struct AsyncIterator: AsyncIteratorProtocol {
            public init() {}
            public mutating func next() async throws -> Element? { nil }
        }

        public init() {}
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
    }

    public typealias Options = GenerationOptions

    public init(model: Model, instructions: @Sendable () -> String) {
        _ = model
        _ = instructions
    }

    public func prewarm() {}

    public func respond<Content>(
        to prompt: String,
        generating type: Content.Type
    ) async throws -> Response<Content> where Content: Sendable {
        _ = prompt
        throw FoundationModelsUnavailableError()
    }

    public func streamResponse(
        to prompt: String,
        options: Options = Options()
    ) -> ResponseStream<String>? {
        _ = prompt
        _ = options
        return nil
    }
}

public struct FoundationModelsUnavailableError: Error, CustomStringConvertible, Sendable {
    public init() {}
    public var description: String {
        "FoundationModels is unavailable on Linux."
    }
}
#endif
