#if os(Linux)
import Foundation
import QuillFoundation
import QuillSwiftUICompatibility
import SwiftData
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
/// built from string literals / interpolation — which String satisfies
/// directly (Apple's LocalizedStringKey exposes no public accessors).
///
/// MUST stay the same underlying type as QuillSwiftUICompatibility's
/// `LocalizedStringKey`: IceCubes' Models sees BOTH modules, and two
/// same-named aliases are unambiguous only while they denote one canonical type.
public typealias LocalizedStringKey = QuillSwiftUICompatibility.LocalizedStringKey

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

public final class ListFormatter {
    public init() {}

    public static func localizedString(byJoining strings: [String]) -> String {
        switch strings.count {
        case 0: return ""
        case 1: return strings[0]
        case 2: return strings.joined(separator: " and ")
        default:
            return strings.dropLast().joined(separator: ", ") + ", and " + (strings.last ?? "")
        }
    }

    public func string(from strings: [String]) -> String? {
        Self.localizedString(byJoining: strings)
    }
}

// AttributedString exists on Linux Foundation but lacks Apple's Markdown
// parsing initializer. Provide the missing surface so IceCubes' HTMLString
// compiles and status text renders as display text instead of literal
// Markdown syntax.
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
extension Optional: IceCubesAppStorageValue where Wrapped: IceCubesAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Optional<Wrapped>? {
        Wrapped.readAppStorageValue(forKey: key)
    }
    public static func writeAppStorageValue(_ value: Optional<Wrapped>, forKey key: String) {
        guard let wrapped = value else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        Wrapped.writeAppStorageValue(wrapped, forKey: key)
    }
}
// NOTE: IceCubesShims used to carry its own `AppStorage` property wrapper.
// QuillSwiftUICompatibility (re-exported through the SwiftUI shadow) now
// declares the canonical one, and two same-named types made every
// vendored-IceCubes `@AppStorage` ambiguous (type-lookup ambiguity can't
// be solved with @_disfavoredOverload). The conformer sets are identical
// (String/Bool/Int/Double/Data/Optional + RawRepresentable), so the
// canonical wrapper serves the vendored sources directly. The
// IceCubesAppStorageValue protocol above stays for SceneStorage and
// friends.

// Linux replacements for IceCubes' SwiftData models that are excluded from the
// vendored Models target. Keep these shapes aligned with upstream stored
// properties so Query/FetchDescriptor/ModelContext can use QuillData.
public final class TagGroup: PersistentModel, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var symbolName: String
    public var tags: [String]
    public var creationDate: Date

    public init(title: String, symbolName: String, tags: [String]) {
        self.id = UUID()
        self.title = title
        self.symbolName = symbolName
        self.tags = tags
        self.creationDate = Date()
    }

    public static func == (l: TagGroup, r: TagGroup) -> Bool {
        l.id == r.id
    }
}

public final class MetricsNotificationGroup: PersistentModel, Identifiable {
    public var id: UUID
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
        self.id = UUID()
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
}

public final class LocalTimeline: PersistentModel, Identifiable {
    public var id: UUID
    public var instance: String
    public var creationDate: Date

    public init(instance: String) {
        self.id = UUID()
        self.instance = instance
        self.creationDate = Date()
    }
}

@MainActor
public final class Telemetry {
    public static func setup() {}
    public static func signal(_ event: String, parameters: [String: String] = [:]) {
        _ = event
        _ = parameters
    }
}

public final class Draft: PersistentModel, Equatable, Identifiable {
    public var id: UUID
    public var content: String
    public var creationDate: Date

    public init(content: String) {
        self.id = UUID()
        self.content = content
        self.creationDate = Date()
    }

    public static func == (lhs: Draft, rhs: Draft) -> Bool {
        lhs.id == rhs.id
    }
}

public final class RecentTag: PersistentModel, Equatable, Identifiable {
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

// Value-form `.mask(_:)` (SwiftUI's original signature), e.g. IceCubes
// DisplaySettingsView's `.mask(LinearGradient(...))`. Lives HERE (icecubes-only,
// force-imported via -import-module IceCubesShims) rather than in
// DesignSystemSurfaceCompat: a second disfavored value-form mask in the shared
// QuillSwiftUICompatibility module ties with QuillUI's value-form mask for
// callers that import both (compat-module tests, generated quill-chat) and
// yields "ambiguous use of 'mask'". IceCubes imports only the SwiftUI shim, so
// it never sees QuillUI's — this is its sole value-form mask. Layout-neutral.
public extension View {
    @_disfavoredOverload
    func mask<Mask: View>(alignment: Alignment = .center, _ mask: Mask) -> Self {
        _ = alignment
        _ = mask
        return self
    }
}
#endif
