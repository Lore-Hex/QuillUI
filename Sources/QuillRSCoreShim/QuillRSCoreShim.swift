import Foundation

/// QuillRSCoreShim — the minimal subset of upstream RSCore
/// surface that is reachable from `import RSCore` inside the
/// vendored Ranchero-Software/NetNewsWire parser modules
/// (`RSParser` first; later iterations will widen as needed
/// for `Articles`, `RSWeb`, `Account`).
///
/// Reproduces the symbols byte-for-byte rather than re-exporting
/// upstream RSCore because RSCore itself does not compile on
/// Linux today: it imports AppKit/UIKit/os and has an Objective-C
/// `RSCoreObjC` sibling. The shim lets us bring upstream parser
/// code over via SwiftPM `moduleAliases: ["RSCore":
/// "QuillRSCoreShim"]` without dragging the platform-coupled
/// pieces.
///
/// Today's surface:
///   - `String.md5String` (RSParser, Articles — content-addressed
///     uniqueIDs)
///   - `Platform.isRunningUnitTests` (Articles' AuthorCache uses
///     it to skip lowMemory observer wiring during XCTest runs)
///   - `Notification.Name.lowMemory` (Articles' AuthorCache
///     listens for it to drop its in-memory author table)
///
/// Future iterations expand only when an upstream `import RSCore`
/// reaches for something else. Don't grow this preemptively —
/// the smaller the shim, the easier the eventual split with
/// upstream is to maintain.

public extension String {
    /// Whitespace-trimmed copy. Mirrors upstream
    /// RSCore.String.trimmingWhitespace.
    var trimmingWhitespace: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case-insensitive substring search. Mirrors upstream
    /// RSCore.String.caseInsensitiveContains used by
    /// FeedSpecifier scoring.
    func caseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: .caseInsensitive) != nil
    }

    /// Strip a leading prefix when present. Mirrors upstream
    /// RSCore.String.stripping(prefix:caseSensitive:). Default
    /// case-insensitive, matching upstream's normalizedURL use.
    func stripping(prefix: String, caseSensitive: Bool = false) -> String {
        let options: String.CompareOptions = caseSensitive
            ? .anchored
            : [.anchored, .caseInsensitive]
        if let range = self.range(of: prefix, options: options) {
            return self.replacingCharacters(in: range, with: "")
        }
        return self
    }

    /// Normalize a feed URL the way upstream RSCore does so the
    /// reader can de-dupe feed:// vs https:// vs schemeless
    /// subscriptions. Verbatim port of RSCore's algorithm:
    ///   1) trim whitespace
    ///   2) strip `feed:` / `feeds:` prefix (remember which)
    ///   3) if no http(s) prefix, prepend `https://` when the
    ///      original was `feeds:` else `http://`
    ///   4) add a trailing slash to bare-host URLs (3 path
    ///      components: scheme/empty/host)
    var normalizedURL: String {
        enum Prefix {
            static let feed = "feed:"
            static let feeds = "feeds:"
            static let http = "http"
            static let https = "https"
        }
        var s = self.trimmingWhitespace
        var wasFeeds = false
        var lowercaseS = s.lowercased()
        if lowercaseS.hasPrefix(Prefix.feeds) {
            wasFeeds = true
            s = s.stripping(prefix: Prefix.feeds)
        } else if lowercaseS.hasPrefix(Prefix.feed) {
            s = s.stripping(prefix: Prefix.feed)
        }
        if s.hasPrefix("//") {
            s = s.stripping(prefix: "//")
        }
        lowercaseS = s.lowercased()
        if !lowercaseS.hasPrefix(Prefix.http) {
            s = "\(wasFeeds ? Prefix.https : Prefix.http)://\(s)"
        }
        let componentsCount = s.components(separatedBy: "/").count
        if componentsCount == 3 {
            s = s.appending("/")
        }
        return s
    }

    /// MD5 hash of the string's UTF-8 bytes, formatted as 32
    /// lowercase hex characters. Compatible byte-for-byte with
    /// upstream RSCore's `String.md5String` so parsed-feed
    /// article IDs round-trip unchanged.
    ///
    /// Implementation: pure-Swift RFC 1321 MD5 so the shim
    /// stays self-contained on Linux without pulling in
    /// swift-crypto / CryptoKit / CommonCrypto. MD5 is used
    /// only for content-addressed IDs, not for security.
    var md5String: String {
        let digest = MD5.hash(Array(self.utf8))
        return MD5.hexString(digest)
    }
}

/// Mirrors `RSCore.Platform`. Articles' AuthorCache uses
/// `isRunningUnitTests` to skip a NotificationCenter
/// registration during XCTest so tests can be re-run without
/// observer leaks. The Quill app process is never a test
/// runner — return false unconditionally; tests can override
/// the detection with the environment variable upstream uses.
public struct Platform {
    public nonisolated static var isRunningUnitTests: Bool {
        // Multiple detection paths because Apple's test runners
        // and swift-corelibs `swift test` use different signals:
        //   1. XCTestConfigurationFilePath env var — set by XCTest
        //   2. SWIFT_TESTING_ENABLED — swift-testing variant
        //   3. arguments[0] basename ending in 'xctest' or
        //      'swiftpm-testing-helper' — `swift test` from a
        //      Package.swift sets the latter, which doesn't set
        //      either env var on Apple platforms (verified via
        //      diagnostic test)
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["SWIFT_TESTING_ENABLED"] != nil { return true }
        if let arg0 = CommandLine.arguments.first {
            let base = (arg0 as NSString).lastPathComponent
            if base == "xctest" || base.contains("xctest") { return true }
            if base.contains("testing-helper") { return true }
        }
        return false
    }
}

public extension Notification.Name {
    /// Posted when an app surface (Articles' AuthorCache today)
    /// should evict in-memory caches due to memory pressure.
    /// Upstream `RSCore.AppNotifications` declares the same name
    /// on the same `Notification.Name` namespace; the literal
    /// string ("LowMemoryNotification") is matched byte-for-byte
    /// so notifications posted from either side route the same.
    static let lowMemory = Notification.Name("LowMemoryNotification")

    /// Posted when the app moves to background. Matches the
    /// raw string upstream RSCore uses.
    static let appDidGoToBackground = Notification.Name("AppDidGoToBackgroundNotification")
}

public extension TimeInterval {
    /// Whole-day TimeInterval, mirrors RSCore.TimeInterval(days:).
    /// Used by upstream RSWeb's 4xx cache expiry, downloader
    /// backoff, etc.
    init(days: Int) {
        self.init(days * 24 * 60 * 60)
    }

    /// Whole-hour TimeInterval, mirrors RSCore.TimeInterval(hours:).
    init(hours: Int) {
        self.init(hours * 60 * 60)
    }

    /// Whole-minute TimeInterval, mirrors RSCore.TimeInterval(minutes:).
    init(minutes: Int) {
        self.init(minutes * 60)
    }
}

/// Mirrors `RSCore.ProgressInfo`. Carries a snapshot of an
/// in-flight batch's task count + how many have completed.
/// Used by upstream RSWeb's DownloadSession + post-fetch
/// observers; structured the same way so observers wired against
/// upstream's `.progressInfoDidChange` notification read the
/// same shape regardless of which side posted.
public struct ProgressInfo: Sendable, Equatable {
    public let numberOfTasks: Int
    public let numberCompleted: Int
    public let numberRemaining: Int

    public var isComplete: Bool { numberRemaining < 1 }

    public init(numberOfTasks: Int = 0, numberCompleted: Int = 0, numberRemaining: Int = 0) {
        assert(numberOfTasks >= 0 && numberCompleted >= 0 && numberRemaining >= 0)
        self.numberOfTasks = numberOfTasks
        self.numberCompleted = numberCompleted
        self.numberRemaining = numberRemaining
    }
}

/// Mirrors `RSCore.ProgressInfoReporter`. RSWeb's DownloadSession
/// conforms; UI surfaces (sidebar refresh spinner, status bar)
/// observe via the matching notification name.
@MainActor public protocol ProgressInfoReporter: AnyObject {
    var progressInfo: ProgressInfo { get }
}

public extension Notification.Name {
    /// Posted when a ProgressInfoReporter's snapshot changes.
    /// Same raw string as upstream `RSCore.AppNotifications` so
    /// cross-side observers route together.
    static let progressInfoDidChange = Notification.Name(rawValue: "ProgressInfoDidChangeNotification")
}

@MainActor public extension ProgressInfoReporter {
    func postProgressInfoDidChangeNotification() {
        NotificationCenter.default.post(name: .progressInfoDidChange, object: self)
    }
}

public extension Date {
    /// Add a day count, returning a new Date. Mirrors
    /// RSCore.Date.byAdding(days:).
    func byAdding(days: Int) -> Date {
        return addingTimeInterval(TimeInterval(days: days))
    }

    /// Subtract a day count, returning a new Date. Mirrors
    /// RSCore.Date.bySubtracting(days:).
    func bySubtracting(days: Int) -> Date {
        return addingTimeInterval(-TimeInterval(days: days))
    }

    /// Subtract an hour count, returning a new Date. Mirrors
    /// RSCore.Date.bySubtracting(hours:). Used by upstream RSWeb's
    /// DownloadSession.cleanUp4xxResponsesCache().
    func bySubtracting(hours: Int) -> Date {
        return addingTimeInterval(-TimeInterval(hours: hours))
    }
}

/// Pure-Swift MD5 implementation (RFC 1321). The intent is to
/// match the output of upstream RSCore's CryptoKit-backed
/// `Insecure.MD5.hash(data:)` for the exact byte sequences the
/// feed parsers compute over. Bit-for-bit equivalence is
/// asserted in QuillRSCoreShimTests against published RFC 1321
/// test vectors.
enum MD5 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var bytes = message
        let bitLength = UInt64(bytes.count) * 8

        // Append 0x80 then 0x00s until length ≡ 56 (mod 64).
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0x00)
        }
        // Append 64-bit little-endian bit length.
        for i in 0..<8 {
            bytes.append(UInt8((bitLength >> (8 * UInt64(i))) & 0xFF))
        }

        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xEFCDAB89
        var c0: UInt32 = 0x98BADCFE
        var d0: UInt32 = 0x10325476

        let blocks = bytes.count / 64
        for block in 0..<blocks {
            var m = [UInt32](repeating: 0, count: 16)
            for j in 0..<16 {
                let base = block * 64 + j * 4
                m[j] = UInt32(bytes[base])
                    | (UInt32(bytes[base + 1]) << 8)
                    | (UInt32(bytes[base + 2]) << 16)
                    | (UInt32(bytes[base + 3]) << 24)
            }
            var a = a0, b = b0, c = c0, d = d0

            for i in 0..<64 {
                var f: UInt32
                var g: Int
                switch i {
                case 0..<16:
                    f = (b & c) | (~b & d); g = i
                case 16..<32:
                    f = (d & b) | (~d & c); g = (5 * i + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d; g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | ~d); g = (7 * i) % 16
                }
                f = f &+ a &+ kTable[i] &+ m[g]
                a = d
                d = c
                c = b
                b = b &+ leftRotate(f, by: sTable[i])
            }

            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        var out = [UInt8]()
        out.reserveCapacity(16)
        for word in [a0, b0, c0, d0] {
            for i in 0..<4 {
                out.append(UInt8((word >> (8 * UInt32(i))) & 0xFF))
            }
        }
        return out
    }

    static func hexString(_ bytes: [UInt8]) -> String {
        let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
        var hex = [UInt8](repeating: 0, count: bytes.count * 2)
        var i = 0
        for byte in bytes {
            hex[i]     = hexDigits[Int(byte >> 4)]
            hex[i + 1] = hexDigits[Int(byte & 0x0F)]
            i += 2
        }
        return String(decoding: hex, as: UTF8.self)
    }

    private static func leftRotate(_ x: UInt32, by amount: UInt32) -> UInt32 {
        return (x << amount) | (x >> (32 - amount))
    }

    private static let sTable: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    private static let kTable: [UInt32] = [
        0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE,
        0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501,
        0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE,
        0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821,
        0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA,
        0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
        0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED,
        0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A,
        0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C,
        0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70,
        0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05,
        0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
        0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039,
        0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1,
        0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1,
        0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391
    ]
}
