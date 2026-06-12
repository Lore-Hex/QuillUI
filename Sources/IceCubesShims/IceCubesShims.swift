#if os(Linux)
import Foundation
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
#endif
