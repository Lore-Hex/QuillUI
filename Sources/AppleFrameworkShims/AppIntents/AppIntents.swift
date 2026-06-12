import Foundation
import UniformTypeIdentifiers

public struct LocalizedStringResource: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable, Hashable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }

    public init(stringInterpolation: StringInterpolation) {
        self.value = stringInterpolation.output
    }

    public static let applicationName = LocalizedStringResource("Application")

    public struct StringInterpolation: StringInterpolationProtocol {
        public var output = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            output.reserveCapacity(literalCapacity + interpolationCount * 12)
        }

        public mutating func appendLiteral(_ literal: String) {
            output += literal
        }

        public mutating func appendInterpolation(_ value: LocalizedStringResource) {
            output += value.value
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            output += String(describing: value)
        }
    }
}

public typealias TypeDisplayRepresentation = LocalizedStringResource
public typealias IntentDescription = LocalizedStringResource

public struct DisplayRepresentation: ExpressibleByStringLiteral, Sendable, Hashable {
    public var title: LocalizedStringResource

    public init(title: LocalizedStringResource) {
        self.title = title
    }

    public init(stringLiteral value: String) {
        self.title = LocalizedStringResource(value)
    }
}

public struct IntentDialog: ExpressibleByStringLiteral, Sendable, Hashable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }
}

public struct InputConnectionBehavior: Sendable, Hashable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let connectToPreviousIntentResult = InputConnectionBehavior("connectToPreviousIntentResult")
}

@propertyWrapper
public struct Parameter<Value> {
    public var wrappedValue: Value {
        get { fatalError("AppIntents.Parameter has no runtime value in the Linux shim") }
        nonmutating set { _ = newValue }
    }

    public init(
        title: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        supportedContentTypes: [UTType]? = nil,
        inputConnectionBehavior: InputConnectionBehavior? = nil,
        requestValueDialog: IntentDialog? = nil
    ) {
        _ = (title, description, supportedContentTypes, inputConnectionBehavior, requestValueDialog)
    }
}

public protocol AppIntent {}
public protocol AppEnum {}
public protocol AppEntity {}
public protocol EntityQuery {}

public protocol AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }
}

@resultBuilder
public enum AppShortcutsBuilder {
    public static func buildBlock(_ components: AppShortcut...) -> [AppShortcut] {
        components
    }

    public static func buildArray(_ components: [[AppShortcut]]) -> [AppShortcut] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [AppShortcut]?) -> [AppShortcut] {
        component ?? []
    }

    public static func buildEither(first component: [AppShortcut]) -> [AppShortcut] {
        component
    }

    public static func buildEither(second component: [AppShortcut]) -> [AppShortcut] {
        component
    }
}

public struct AppShortcut {
    public var intent: any AppIntent
    public var phrases: [LocalizedStringResource]
    public var shortTitle: LocalizedStringResource
    public var systemImageName: String

    public init<Intent: AppIntent>(
        intent: Intent,
        phrases: [LocalizedStringResource],
        shortTitle: LocalizedStringResource,
        systemImageName: String
    ) {
        self.intent = intent
        self.phrases = phrases
        self.shortTitle = shortTitle
        self.systemImageName = systemImageName
    }
}

public protocol IntentResult {}
public protocol ProvidesDialog {}
public protocol ShowsSnippetView {}

public struct IntentResultValue: IntentResult, ProvidesDialog, ShowsSnippetView, Sendable {
    public var dialog: IntentDialog?

    public init(dialog: IntentDialog? = nil) {
        self.dialog = dialog
    }
}

public extension IntentResult where Self == IntentResultValue {
    static func result() -> IntentResultValue {
        IntentResultValue()
    }

    static func result(dialog: IntentDialog) -> IntentResultValue {
        IntentResultValue(dialog: dialog)
    }

    static func result(dialog: String) -> IntentResultValue {
        IntentResultValue(dialog: IntentDialog(dialog))
    }
}

public struct IntentFile: Sendable, Hashable {
    public var fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }
}
