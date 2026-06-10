import Foundation
import UniformTypeIdentifiers

public struct LocalizedStringResource: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Hashable, Sendable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }

    public init(stringInterpolation: StringInterpolation) {
        self.value = stringInterpolation.value
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        public var value = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            value.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            value += literal
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            self.value += String(describing: value)
        }
    }
}

public struct IntentDescription: ExpressibleByStringLiteral, Sendable {
    public var value: String
    public init(_ value: String) { self.value = value }
    public init(stringLiteral value: String) { self.value = value }
}

public struct IntentDialog: ExpressibleByStringLiteral, Sendable {
    public var value: String
    public init(_ value: String) { self.value = value }
    public init(stringLiteral value: String) { self.value = value }
}

public struct DisplayRepresentation: ExpressibleByStringLiteral, Sendable {
    public var title: LocalizedStringResource

    public init(title: LocalizedStringResource) {
        self.title = title
    }

    public init(title: String) {
        self.title = LocalizedStringResource(title)
    }

    public init(stringLiteral value: String) {
        self.title = LocalizedStringResource(value)
    }
}

public struct TypeDisplayRepresentation: ExpressibleByStringLiteral, Sendable {
    public var title: LocalizedStringResource
    public init(_ title: LocalizedStringResource) { self.title = title }
    public init(stringLiteral value: String) { self.title = LocalizedStringResource(value) }
}

public protocol AppIntent: Sendable {}
public protocol AppEntity: Sendable {}
public protocol AppEnum: Sendable {}
public protocol EntityQuery: Sendable {}

public protocol IntentResult: Sendable {}
public protocol ProvidesDialog: Sendable {}
public protocol ShowsSnippetView: Sendable {}

public struct IntentResultValue: IntentResult, ProvidesDialog, ShowsSnippetView {
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

public struct InputConnectionBehavior: Sendable {
    public init() {}
    public static let connectToPreviousIntentResult = InputConnectionBehavior()
}

@propertyWrapper
public struct Parameter<Value>: @unchecked Sendable {
    private var value: Value?

    public var wrappedValue: Value {
        get {
            guard let value else {
                fatalError("AppIntents.Parameter has no Linux runtime value.")
            }
            return value
        }
        set { value = newValue }
    }

    public init(
        title: LocalizedStringResource,
        description: LocalizedStringResource? = nil,
        requestValueDialog: IntentDialog? = nil,
        supportedContentTypes: [UTType] = [],
        inputConnectionBehavior: InputConnectionBehavior? = nil
    ) {
        _ = title
        _ = description
        _ = requestValueDialog
        _ = supportedContentTypes
        _ = inputConnectionBehavior
        value = nil
    }
}

public struct IntentFile: Sendable {
    public var fileURL: URL?
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }
}

public struct AppShortcut: Sendable {
    public init(
        intent: any AppIntent,
        phrases: [LocalizedStringResource],
        shortTitle: LocalizedStringResource,
        systemImageName: String
    ) {
        _ = intent
        _ = phrases
        _ = shortTitle
        _ = systemImageName
    }
}

@resultBuilder
public enum AppShortcutsBuilder {
    public static func buildBlock(_ components: AppShortcut...) -> [AppShortcut] {
        components
    }

    public static func buildArray(_ components: [[AppShortcut]]) -> [AppShortcut] {
        components.flatMap { $0 }
    }
}

public protocol AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }
}

public struct AppShortcutPhraseToken: Sendable, CustomStringConvertible {
    public var description: String
    public static let applicationName = AppShortcutPhraseToken(description: "App")
}

public extension LocalizedStringResource.StringInterpolation {
    mutating func appendInterpolation(_ token: AppShortcutPhraseToken) {
        value += token.description
    }
}

@propertyWrapper
public struct IntentParameterDependency<Root, Value>: @unchecked Sendable {
    public var wrappedValue: Value?

    public init(_ keyPath: KeyPath<Root, Value>) {
        _ = keyPath
        wrappedValue = nil
    }
}
