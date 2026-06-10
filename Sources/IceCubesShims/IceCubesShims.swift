#if os(Linux)
import Foundation
import QuillFoundation
import SwiftOpenUI
import SwiftData
import SwiftUI

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
        _ = options
        self = AttributedString(stringLiteral: HTMLText.plainText(fromMarkdown: markdown))
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
extension Data: IceCubesAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
    public static func writeAppStorageValue(_ value: Data, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}
@propertyWrapper
public struct AppStorage<Value>: AnyStateStorageProvider {
    private let writeValue: (Value) -> Void
    public let storage: StateStorage<Value>
    public init(wrappedValue d: Value, _ key: String) where Value: IceCubesAppStorageValue {
        self.init(wrappedValue: d, key, store: nil)
    }
    public init(wrappedValue d: Value, _ key: String, store: UserDefaults?) where Value: IceCubesAppStorageValue {
        let defaults = store ?? .standard
        writeValue = { defaults.set($0, forKey: key) }
        storage = StateStorage(Self.readValue(Value.self, forKey: key, store: defaults) ?? d)
    }
    public init(wrappedValue d: Value, _ key: String) where Value: RawRepresentable, Value.RawValue: IceCubesAppStorageValue {
        self.init(wrappedValue: d, key, store: nil)
    }
    public init(wrappedValue d: Value, _ key: String, store: UserDefaults?) where Value: RawRepresentable, Value.RawValue: IceCubesAppStorageValue {
        let defaults = store ?? .standard
        writeValue = { defaults.set($0.rawValue, forKey: key) }
        if let rv = Self.readValue(Value.RawValue.self, forKey: key, store: defaults), let v = Value(rawValue: rv) {
            storage = StateStorage(v)
        } else {
            storage = StateStorage(d)
        }
    }
    public init(_ key: String) where Value == Data? {
        self.init(key, store: nil)
    }
    public init(_ key: String, store: UserDefaults?) where Value == Data? {
        let defaults = store ?? .standard
        writeValue = { value in
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        storage = StateStorage(defaults.data(forKey: key))
    }
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { writeValue(newValue); storage.setValue(newValue) }
    }
    public var projectedValue: Binding<Value> {
        Binding(get: { storage.value }, set: { nv in writeValue(nv); storage.setValue(nv) })
    }
    public var anyStorage: AnyStateStorage { storage }

    private static func readValue<T: IceCubesAppStorageValue>(
        _ type: T.Type,
        forKey key: String,
        store: UserDefaults
    ) -> T? {
        _ = type
        switch T.self {
        case is String.Type:
            return store.string(forKey: key) as? T
        case is Bool.Type:
            return (store.object(forKey: key) != nil ? store.bool(forKey: key) : nil) as? T
        case is Int.Type:
            return (store.object(forKey: key) != nil ? store.integer(forKey: key) : nil) as? T
        case is Double.Type:
            return (store.object(forKey: key) != nil ? store.double(forKey: key) : nil) as? T
        case is Data.Type:
            return store.data(forKey: key) as? T
        default:
            return T.readAppStorageValue(forKey: key)
        }
    }
}

// Stub for the Models SwiftData `TagGroup` (excluded on Linux — SwiftData is
// Apple-only). Env references it only as a navigation payload type, so a plain
// class with the same surface suffices.
public final class TagGroup: PersistentModel, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var symbolName: String
    public var tags: [String]
    public var creationDate: Date
    public init(title: String, symbolName: String, tags: [String]) {
        self.id = UUID()
        self.title = title; self.symbolName = symbolName; self.tags = tags; self.creationDate = Date()
    }
    public static func == (l: TagGroup, r: TagGroup) -> Bool {
        l.id == r.id
    }
}

public final class LocalTimeline: PersistentModel, Identifiable, Equatable {
    public var id: UUID
    public var instance: String
    public var creationDate: Date

    public init(instance: String) {
        self.id = UUID()
        self.instance = instance
        self.creationDate = Date()
    }

    public static func == (lhs: LocalTimeline, rhs: LocalTimeline) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public enum Telemetry {
    public static func setup() {}

    public static func signal(_ event: String, parameters: [String: String] = [:]) {
        _ = event
        _ = parameters
    }
}

public final class RecentTag: PersistentModel, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var lastUse: Date

    public init(title: String) {
        self.id = UUID()
        self.title = title
        self.lastUse = Date()
    }

    public var formattedDate: String {
        RelativeDateTimeFormatter().localizedString(for: lastUse, relativeTo: Date())
    }

    public static func == (lhs: RecentTag, rhs: RecentTag) -> Bool {
        lhs.id == rhs.id
    }
}

public final class Draft: PersistentModel, Identifiable {
    public var id: UUID
    public var content: String
    public var creationDate: Date

    public init(content: String) {
        self.id = UUID()
        self.content = content
        self.creationDate = Date()
    }
}

@MainActor
public extension View {
    func withPreviewsEnv() -> Self { self }
}

public final class HapticManager: @unchecked Sendable {
    public enum NotificationFeedbackType: Sendable {
        case success
        case warning
        case error
    }

    public enum HapticType: Sendable {
        case buttonPress
        case dataRefresh(intensity: Double)
        case timeline
        case tabSelection
        case notification(NotificationFeedbackType)
    }

    public static let shared = HapticManager()
    private init() {}

    public var supportsHaptics: Bool { false }

    public func fireHaptic(_ type: HapticType) {
        _ = type
    }
}

public final class MetricsNotificationGroup: PersistentModel, @unchecked Sendable {
    public var groupKey: String
    public var type: String
    public var notificationsCount: Int
    public var mostRecentNotificationId: Int
    public var latestPageNotificationAt: Date
    public var dayStart: Date
    public var statusId: String
    public var accountId: String
    public var server: String

    public init(
        groupKey: String,
        type: String,
        notificationsCount: Int,
        mostRecentNotificationId: Int,
        latestPageNotificationAt: Date,
        dayStart: Date,
        statusId: String,
        accountId: String,
        server: String
    ) {
        self.groupKey = groupKey
        self.type = type
        self.notificationsCount = notificationsCount
        self.mostRecentNotificationId = mostRecentNotificationId
        self.latestPageNotificationAt = latestPageNotificationAt
        self.dayStart = dayStart
        self.statusId = statusId
        self.accountId = accountId
        self.server = server
    }

    private enum CodingKeys: String, CodingKey {
        case groupKey
        case type
        case notificationsCount
        case mostRecentNotificationId
        case latestPageNotificationAt
        case dayStart
        case statusId
        case accountId
        case server
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupKey = try container.decode(String.self, forKey: .groupKey)
        type = try container.decode(String.self, forKey: .type)
        notificationsCount = try container.decode(Int.self, forKey: .notificationsCount)
        mostRecentNotificationId = try container.decode(Int.self, forKey: .mostRecentNotificationId)
        latestPageNotificationAt = try container.decode(Date.self, forKey: .latestPageNotificationAt)
        dayStart = try container.decode(Date.self, forKey: .dayStart)
        statusId = try container.decode(String.self, forKey: .statusId)
        accountId = try container.decode(String.self, forKey: .accountId)
        server = try container.decode(String.self, forKey: .server)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupKey, forKey: .groupKey)
        try container.encode(type, forKey: .type)
        try container.encode(notificationsCount, forKey: .notificationsCount)
        try container.encode(mostRecentNotificationId, forKey: .mostRecentNotificationId)
        try container.encode(latestPageNotificationAt, forKey: .latestPageNotificationAt)
        try container.encode(dayStart, forKey: .dayStart)
        try container.encode(statusId, forKey: .statusId)
        try container.encode(accountId, forKey: .accountId)
        try container.encode(server, forKey: .server)
    }
}

public final class ListFormatter {
    public static func localizedString(byJoining strings: [String]) -> String {
        strings.joined(separator: ", ")
    }
}

@MainActor
public final class SoundEffectManager {
    public enum SoundEffect: String, CaseIterable, Sendable {
        case pull
        case refresh
        case tootSent
        case tabSelection
        case bookmark
        case boost
        case favorite
        case share
    }

    public static let shared = SoundEffectManager()
    private init() {}

    public func playSound(_ effect: SoundEffect) {
        _ = effect
    }
}

@MainActor
public enum AppStore {
    public static func requestReview(in scene: UIWindowScene) {
        _ = scene
    }
}
#endif
