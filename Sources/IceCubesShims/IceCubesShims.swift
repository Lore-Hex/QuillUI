#if os(Linux)
import Foundation
import SwiftOpenUI

// Scoped `@Observable` for the vendored IceCubes targets (auto-imported via
// `-import-module IceCubesShims`). Deliberately NOT in the shared SwiftUI shim:
// re-exporting Observation there changes `@Observable` resolution for other
// ports' real source and broke Enchanted's runtime composer-send smoke.
@_exported import Observation

// Linux compile shims for the REAL Dimillian/IceCubesApp `Models` source.
// These types are absent from swift-corelibs-foundation / the SwiftUI mirror
// on Linux; provided here and auto-imported (-import-module IceCubesShims, set
// on the Models target's swiftSettings) so the upstream source compiles
// UNMODIFIED — the WireGuard-style vendor pattern. Linux-only: on macOS the
// real SwiftUI / Foundation supply these, so the shim must not shadow them.

/// SwiftUI's localized-string key. Upstream uses it only as a return type
/// built from string literals / interpolation.
public struct LocalizedStringKey: Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public init(stringLiteral value: String) { self.key = value }
    public init(_ value: String) { self.key = value }
    public init(stringInterpolation: StringInterpolation) { self.key = stringInterpolation.value }

    public struct StringInterpolation: StringInterpolationProtocol {
        public var value = ""
        public init(literalCapacity: Int, interpolationCount: Int) {}
        public mutating func appendLiteral(_ literal: String) { value += literal }
        public mutating func appendInterpolation<T>(_ v: T) { value += "\(v)" }
    }
}

/// Minimal Foundation `RelativeDateTimeFormatter` (missing on Linux Foundation).
/// Covers the surface upstream `DateFormatterCache` uses.
public final class RelativeDateTimeFormatter {
    public enum UnitsStyle { case full, spellOut, short, abbreviated }
    public enum DateTimeStyle { case numeric, named }
    public enum Context { case unknown, standalone, listItem, beginningOfSentence, middleOfSentence, dynamic }
    public var unitsStyle: UnitsStyle = .full
    public var dateTimeStyle: DateTimeStyle = .numeric
    public var formattingContext: Context = .unknown
    public init() {}

    public func localizedString(for date: Date, relativeTo reference: Date) -> String {
        let delta = Int(date.timeIntervalSince(reference))
        let a = abs(delta)
        let past = delta <= 0
        let terse = unitsStyle == .short || unitsStyle == .abbreviated
        func fmt(_ n: Int, _ u: String) -> String {
            let unit = terse ? u : " \(u)"
            return past ? "\(n)\(unit) ago" : "in \(n)\(unit)"
        }
        switch a {
        case 0 ..< 60: return fmt(a, "s")
        case 60 ..< 3600: return fmt(a / 60, "m")
        case 3600 ..< 86400: return fmt(a / 3600, "h")
        case 86400 ..< 604_800: return fmt(a / 86400, "d")
        case 604_800 ..< 2_592_000: return fmt(a / 604_800, "w")
        case 2_592_000 ..< 31_536_000: return fmt(a / 2_592_000, "mo")
        default: return fmt(a / 31_536_000, "y")
        }
    }

    public func string(for date: Date) -> String? {
        localizedString(for: date, relativeTo: Date())
    }
}

// AttributedString exists on Linux Foundation but lacks Apple's Markdown
// parsing initializer. Provide the missing surface so HTMLString compiles;
// the Linux fallback is plain text (rich styling is rendered by QuillUI from
// htmlValue/asRawText anyway, not from this AttributedString).
public extension AttributedString {
    struct MarkdownParsingOptions {
        public enum InterpretedSyntax { case full, inlineOnly, inlineOnlyPreservingWhitespace }
        public var allowsExtendedAttributes: Bool
        public var interpretedSyntax: InterpretedSyntax
        public init(allowsExtendedAttributes: Bool = false,
                    interpretedSyntax: InterpretedSyntax = .full) {
            self.allowsExtendedAttributes = allowsExtendedAttributes
            self.interpretedSyntax = interpretedSyntax
        }
    }

    init(markdown: String, options: MarkdownParsingOptions) throws {
        self = AttributedString(stringLiteral: markdown)
    }
}

// `@AppStorage` for the vendored IceCubes targets, backed by SwiftOpenUI's
// StateStorage/Binding (UserDefaults-persisted). IceCubes-scoped (not the
// shared QuillUI AppStorage) so it resolves via -import-module without the
// SwiftUI shim having to `@_exported import QuillUI`.
public protocol IceCubesAppStorageValue {
    static func readAppStorageValue(forKey key: String) -> Self?
    static func writeAppStorageValue(_ value: Self, forKey key: String)
}
extension String: IceCubesAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    public static func writeAppStorageValue(_ value: String, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
extension Bool: IceCubesAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Bool? { UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : nil }
    public static func writeAppStorageValue(_ value: Bool, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
extension Int: IceCubesAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Int? { UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.integer(forKey: key) : nil }
    public static func writeAppStorageValue(_ value: Int, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
extension Double: IceCubesAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Double? { UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.double(forKey: key) : nil }
    public static func writeAppStorageValue(_ value: Double, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
@propertyWrapper
public struct AppStorage<Value>: AnyStateStorageProvider {
    private let writeValue: (Value) -> Void
    public let storage: StateStorage<Value>
    public init(wrappedValue d: Value, _ key: String) where Value: IceCubesAppStorageValue {
        writeValue = { Value.writeAppStorageValue($0, forKey: key) }
        storage = StateStorage(Value.readAppStorageValue(forKey: key) ?? d)
    }
    public init(wrappedValue d: Value, _ key: String) where Value: RawRepresentable, Value.RawValue: IceCubesAppStorageValue {
        writeValue = { Value.RawValue.writeAppStorageValue($0.rawValue, forKey: key) }
        if let rv = Value.RawValue.readAppStorageValue(forKey: key), let v = Value(rawValue: rv) { storage = StateStorage(v) } else { storage = StateStorage(d) }
    }
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { writeValue(newValue); storage.setValue(newValue) }
    }
    public var projectedValue: Binding<Value> {
        Binding(get: { storage.value }, set: { nv in writeValue(nv); storage.setValue(nv) })
    }
    public var anyStorage: AnyStateStorage { storage }
}

// Stub for the Models SwiftData `TagGroup` (excluded on Linux — SwiftData is
// Apple-only). Env references it only as a navigation payload type, so a plain
// class with the same surface suffices.
public final class TagGroup: Equatable {
    public var title: String
    public var symbolName: String
    public var tags: [String]
    public var creationDate: Date
    public init(title: String, symbolName: String, tags: [String]) {
        self.title = title; self.symbolName = symbolName; self.tags = tags; self.creationDate = Date()
    }
    public static func == (l: TagGroup, r: TagGroup) -> Bool {
        l.title == r.title && l.symbolName == r.symbolName && l.tags == r.tags && l.creationDate == r.creationDate
    }
}
#endif
