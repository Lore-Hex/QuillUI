import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import QuillKit
import QuillData

// On macOS we want to compare Quill's behavior against the *real* Apple
// frameworks. On Linux there is no Apple framework to compare against, so the
// same source path simply exercises Quill's implementation. If a test passes
// on both platforms with the same assertion, the behaviors are observationally
// identical; that is the parity guarantee we want.
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#else
import QuillUI
#endif

// AppKit only exists on macOS. On Linux, `import AppKit` resolves to QuillUI's
// AppKit shadow target, but the parity tests don't link against the shadow
// modules directly (they run cross-platform without the Linux shadow targets).
// So Linux parity assertions that need AppKit are gated to macOS only and
// documented as such; the equivalent Linux test lives in
// QuillCompatibilityModuleTests.
#if os(macOS) && canImport(AppKit)
import AppKit
#endif

/// QuillParity tests run on both macOS and Linux. They are deliberately written
/// in pure cross-platform Swift, with `#if canImport(...)` import switching so
/// the SAME assertion exercises Apple frameworks on macOS and Quill shadows on
/// Linux. A test that passes on both platforms proves parity for that surface.
@Suite("Quill Apple parity", .serialized)
struct QuillParityTests {

    // MARK: - UTType identifiers

    @Test("UTType public identifiers match Apple's canonical strings")
    func utTypeIdentifiersMatchAppleCanonicalStrings() {
        // These string constants are Apple's canonical UTType identifiers,
        // unchanged since Mac OS X 10.4. Quill's UTType shim must use the
        // exact same strings so any code that compares identifiers works
        // unchanged across platforms.
        #expect(UTType.png.identifier == "public.png")
        #expect(UTType.jpeg.identifier == "public.jpeg")
        #expect(UTType.tiff.identifier == "public.tiff")
        #expect(UTType.image.identifier == "public.image")
    }

    @Test("UTType.image is a supertype of png/jpeg/tiff on both platforms")
    func utTypeImageIsImageSupertype() {
        #expect(UTType.png.conforms(to: UTType.image))
        #expect(UTType.jpeg.conforms(to: UTType.image))
        #expect(UTType.tiff.conforms(to: UTType.image))
    }

    // MARK: - URL / Foundation parity

    @Test("URL pathExtension is the literal substring after the last dot")
    func urlPathExtensionParity() {
        // Foundation's URL is identical between Apple's Foundation and
        // swift-corelibs-foundation. These assertions document the contract
        // QuillUI's UTType.type(for:) relies on.
        #expect(URL(fileURLWithPath: "/tmp/photo.png").pathExtension == "png")
        #expect(URL(fileURLWithPath: "/tmp/photo.PNG").pathExtension == "PNG")
        #expect(URL(fileURLWithPath: "/tmp/document.tar.gz").pathExtension == "gz")
        #expect(URL(fileURLWithPath: "/tmp/no-extension").pathExtension == "")
        #expect(URL(fileURLWithPath: "/tmp/.hidden").pathExtension == "")
    }

    @Test("URL lastPathComponent strips the directory prefix")
    func urlLastPathComponentParity() {
        #expect(URL(fileURLWithPath: "/tmp/foo/bar.txt").lastPathComponent == "bar.txt")
        #expect(URL(fileURLWithPath: "/tmp/foo/").lastPathComponent == "foo")
        #expect(URL(fileURLWithPath: "/").lastPathComponent == "/")
    }

    // MARK: - UserDefaults round-trip parity

    @Test("UserDefaults string round-trips identically on both platforms")
    func userDefaultsStringRoundTrip() {
        let key = "quill.parity.string.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("hello world", forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == "hello world")

        UserDefaults.standard.set("", forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == "")

        UserDefaults.standard.removeObject(forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test("UserDefaults bool round-trip preserves explicit false (object-presence semantics)")
    func userDefaultsBoolRoundTripPreservesFalse() {
        let key = "quill.parity.bool.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Crucially, `bool(forKey:)` returns `false` for an absent key. The
        // only way to distinguish "explicitly false" from "absent" is to use
        // `object(forKey:) != nil` first. Quill's AppStorage relies on this
        // contract; verify it holds on both platforms.
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.object(forKey: key) != nil)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)
    }

    @Test("UserDefaults numeric round-trip preserves Int and Double")
    func userDefaultsNumericRoundTrip() {
        let intKey = "quill.parity.int.\(UUID().uuidString)"
        let doubleKey = "quill.parity.double.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: intKey)
            UserDefaults.standard.removeObject(forKey: doubleKey)
        }

        // swift-corelibs UserDefaults does not preserve every platform-sized
        // extreme Int through integer(forKey:). AppStorage depends on ordinary
        // persisted preference values, so keep this parity assertion inside the
        // portable range shared by Apple Foundation and swift-corelibs.
        for value in [0, 1, -1, 42, Int(Int32.max), Int(Int32.min)] {
            UserDefaults.standard.set(value, forKey: intKey)
            #expect(UserDefaults.standard.integer(forKey: intKey) == value)
        }

        for value in [0.0, 1.0, -1.0, 3.14159, .pi, .infinity, -.infinity] as [Double] {
            UserDefaults.standard.set(value, forKey: doubleKey)
            let read = UserDefaults.standard.double(forKey: doubleKey)
            if value.isNaN {
                #expect(read.isNaN)
            } else if value.isInfinite {
                #expect(read.isInfinite)
                #expect(read.sign == value.sign)
            } else {
                #expect(read == value, "Round-trip differs for \(value) -> \(read)")
            }
        }
    }

    // MARK: - JSON encoder parity

    @Test("JSONEncoder/JSONDecoder round-trip preserves Codable structs identically")
    func jsonRoundTripParity() throws {
        struct Sample: Codable, Equatable {
            var id: String
            var count: Int
            var ratio: Double
            var enabled: Bool
            var tags: [String]
        }

        let original = Sample(
            id: UUID().uuidString,
            count: 42,
            ratio: 3.14,
            enabled: true,
            tags: ["a", "b", "c"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)

        // Encoded shape must be deterministic with sortedKeys.
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""count":42"#))
        #expect(json.contains(#""enabled":true"#))
        #expect(json.contains(#""tags":["a","b","c"]"#))

        let decoded = try JSONDecoder().decode(Sample.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Date / Calendar parity

    @Test("Calendar.dateComponents produces the same day delta on both platforms")
    func calendarDayDeltaParity() {
        let calendar = Foundation.Calendar(identifier: .gregorian)
        var components = Foundation.DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 8
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = Foundation.TimeZone(identifier: "UTC")

        guard let mayEighth = calendar.date(from: components) else {
            Issue.record("Failed to construct reference date")
            return
        }

        // Three days later, same hour, same TZ.
        let mayEleventh = mayEighth.addingTimeInterval(60 * 60 * 24 * 3)
        var utcCalendar = calendar
        utcCalendar.timeZone = Foundation.TimeZone(identifier: "UTC")!

        let delta = utcCalendar.dateComponents([.day], from: mayEighth, to: mayEleventh)
        #expect(delta.day == 3)
    }

    // MARK: - QuillData (cross-platform implementation)

    @Test("QuillData ModelContainer + ModelContext round-trips a simple model identically")
    func quillDataRoundTripsBasicModel() throws {
        struct Note: PersistentModel, Equatable, Hashable {
            var id: String
            var body: String
            var ratio: Double
        }

        let container = try ModelContainer(
            for: Schema([Note.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let inserted = (0..<5).map { Note(id: "n\($0)", body: "body \($0)", ratio: Double($0) / 5) }
        for note in inserted {
            context.insert(note)
        }

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(Set(fetched) == Set(inserted))
    }

    // MARK: - Property-based fuzz: round-trip invariants

    @Test("Fuzz: any UUID string survives a UserDefaults round-trip", arguments: parityRandomSeeds(count: 32))
    func fuzzUUIDRoundTrip(seed: UInt64) {
        let key = "quill.parity.fuzz.string.\(seed)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Generate a deterministic value from the seed so a failing test can
        // be re-run with the same input.
        var rng = SeededRNG(seed: seed)
        let value = UUID(rng: &rng).uuidString

        UserDefaults.standard.set(value, forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == value)
    }

    @Test("Fuzz: any small Codable struct round-trips through JSON unchanged",
          arguments: parityRandomSeeds(count: 32))
    func fuzzCodableJSONRoundTrip(seed: UInt64) throws {
        struct Bag: Codable, Equatable {
            var id: String
            var label: String
            var value: Int
            var enabled: Bool
        }

        var rng = SeededRNG(seed: seed)
        let original = Bag(
            id: UUID(rng: &rng).uuidString,
            label: "label-\(rng.next() % 1_000_000)",
            value: Int(truncatingIfNeeded: rng.next()),
            enabled: rng.next() % 2 == 0
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Bag.self, from: data)
        #expect(decoded == original)
    }

    @Test("Fuzz: random URL paths produce consistent pathExtension behavior",
          arguments: parityRandomSeeds(count: 32))
    func fuzzURLPathExtension(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let stems = ["photo", "doc", "data", "archive", "file", ""]
        let exts = ["png", "PNG", "jpg", "jpeg", "tiff", "tar.gz", "", "txt"]

        let stem = stems[Int(rng.next() % UInt64(stems.count))]
        let ext = exts[Int(rng.next() % UInt64(exts.count))]
        let path: String
        if ext.isEmpty || stem.isEmpty {
            path = "/tmp/\(stem)\(ext.isEmpty ? "" : "." + ext)"
        } else {
            path = "/tmp/\(stem).\(ext)"
        }

        let url = URL(fileURLWithPath: path)
        // Foundation contract: pathExtension is the substring after the LAST
        // dot in the last path component, never lowercased, empty when no dot.
        let expected: String = {
            let component = (path as NSString).lastPathComponent
            guard let dotIndex = component.lastIndex(of: ".") else { return "" }
            // Hidden files like ".hidden" with the dot at index 0 have no extension.
            if dotIndex == component.startIndex { return "" }
            return String(component[component.index(after: dotIndex)...])
        }()
        #expect(url.pathExtension == expected, "path=\(path) ext=\(ext) seed=\(seed)")
    }

    // MARK: - NSImage TIFF passthrough parity (macOS-only assertion)

#if os(macOS) && canImport(AppKit)
    /// On macOS, real Apple `NSImage(data:).tiffRepresentation` for a valid
    /// TIFF input returns TIFF bytes that decode to the same image. Apple does
    /// NOT promise byte-for-byte passthrough; the encoder may rewrite the
    /// header. So the strongest cross-platform contract we can assert here is:
    ///
    ///   * Apple's NSImage with valid TIFF input produces a non-nil TIFF
    ///     representation.
    ///   * Apple's NSImage with garbage bytes produces nil.
    ///
    /// QuillUI's NSImage shim on Linux *does* promise byte-for-byte passthrough
    /// for TIFF input (a stricter contract than Apple's). The Linux behavior is
    /// asserted in `QuillCompatibilityModuleTests.nsImageTiffPassthroughParity`.
    /// Together these two tests bound Quill's behavior between "no worse than
    /// Apple" (returns Data when Apple does) and "stricter than Apple"
    /// (deterministic byte equality).
    @Test("Apple NSImage produces TIFF data for valid TIFF input and nil for garbage")
    func appleNSImageTIFFContract() throws {
        // Build a 4x4 RGB bitmap, encode it as TIFF, then verify NSImage can
        // round-trip it. The bitmap representation gives us guaranteed-valid
        // TIFF bytes without depending on a specific TIFF golden file.
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4,
            pixelsHigh: 4,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 12,
            bitsPerPixel: 24
        )
        guard let validTIFF = rep?.representation(using: .tiff, properties: [:]) else {
            Issue.record("Failed to synthesize a TIFF reference fixture")
            return
        }

        // Apple parity: valid TIFF in, non-nil TIFF out.
        let validImage = NSImage(data: validTIFF)
        #expect(validImage?.tiffRepresentation != nil)

        // Apple parity: garbage in, nil image (or nil tiffRepresentation).
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
        let garbageImage = NSImage(data: garbage)
        // Apple may either fail to construct NSImage (returns nil from init)
        // or succeed with no usable representation. Either is acceptable;
        // returning *non-nil bogus bytes* would be the bug.
        #expect(garbageImage == nil || garbageImage?.tiffRepresentation == nil)
    }
#endif

    // MARK: - NSImage PNG to TIFF transcoding parity

#if os(macOS) && canImport(AppKit)
    /// Apple parity: PNG bytes through `NSImage(data:).tiffRepresentation`
    /// produce real TIFF bytes (decoded + re-encoded). On macOS this is the
    /// real AppKit path. On Linux the same QuillUI test exists in
    /// `QuillCompatibilityModuleTests.nsImageTiffPNGToTIFFTranscodes`, where
    /// it exercises the gdk-pixbuf bridge.
    ///
    /// The cross-platform parity proof is: the assertion below passes on
    /// macOS (against real AppKit) and the matching assertion passes on Linux
    /// (against QuillUI's gdk-pixbuf-backed shim). Identical observable
    /// behavior = parity.
    @Test("Apple NSImage transcodes a valid PNG to real TIFF bytes")
    func appleNSImagePNGToTIFFTranscode() throws {
        // 67-byte 1x1 grayscale PNG. Stable, well-known fixture.
        guard let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==") else {
            Issue.record("Failed to decode reference PNG fixture")
            return
        }

        guard let img = NSImage(data: png) else {
            Issue.record("Apple NSImage(data:) failed to decode reference PNG")
            return
        }

        let tiff = img.tiffRepresentation
        #expect(tiff != nil, "Apple NSImage.tiffRepresentation must yield TIFF bytes for valid PNG")
        if let tiff, tiff.count >= 4 {
            let prefix = Array(tiff.prefix(4))
            let isLittle = prefix == [0x49, 0x49, 0x2A, 0x00]  // "II*\0"
            let isBig = prefix == [0x4D, 0x4D, 0x00, 0x2A]  // "MM\0*"
            #expect(isLittle || isBig, "Output must start with TIFF magic; got \(prefix)")
        }
    }
#endif

    // MARK: - QuillCompatibilityDiagnostics shape parity

    @Test("QuillCompatibilityEvent severity raw values are stable")
    func compatibilityEventSeverityRawValuesStable() {
        // The severity rawValue strings get logged and surfaced in any
        // diagnostic UI; they must not drift across platforms or releases.
        #expect(QuillCompatibilityEvent.Severity.info.rawValue == "info")
        #expect(QuillCompatibilityEvent.Severity.warning.rawValue == "warning")
        #expect(QuillCompatibilityEvent.Severity.unsupported.rawValue == "unsupported")
    }
}

// MARK: - Test fixtures

/// Deterministic PRNG so fuzz failures are reproducible by seed.
/// xorshift64; fast and adequate for property-based test inputs.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Ensure non-zero state (xorshift requires it).
        self.state = seed == 0 ? 0xDEADBEEF_CAFEBABE : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }
}

private extension UUID {
    /// Build a UUID from a seeded PRNG so fuzz inputs are reproducible.
    init(rng: inout SeededRNG) {
        var bytes = [UInt8](repeating: 0, count: 16)
        var i = 0
        while i < bytes.count {
            let chunk = rng.next()
            withUnsafeBytes(of: chunk) { raw in
                let copyCount = min(8, bytes.count - i)
                for offset in 0..<copyCount {
                    bytes[i + offset] = raw[offset]
                }
            }
            i += 8
        }
        // Set version (4) and variant (RFC 4122) bits so the UUID string
        // formats canonically.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Stable seed sequence so the same fuzz cases run in the same order on every
/// platform. Generated from a fixed root seed so failures are reproducible.
fileprivate func parityRandomSeeds(count: Int) -> [UInt64] {
    var rng = SeededRNG(seed: 0xCAFEF00D_BAADC0DE)
    return (0..<count).map { _ in rng.next() }
}
