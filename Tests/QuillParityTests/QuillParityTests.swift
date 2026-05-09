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

// On macOS QuillUI re-exports SwiftUI (`@_exported import SwiftUI`), so
// importing QuillUI here gives the parity tests access to `ImageRenderer`,
// `Color`, `Text`, etc. — pointing at real Apple SwiftUI on macOS and Quill's
// shims on Linux. The `#if canImport(...)` block above already imports
// QuillUI on Linux; on macOS we add it explicitly here.
#if canImport(SwiftUI)
import QuillUI
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

    // MARK: - Color parity

    @Test("Color(hex:) parity for 6 and 8 digit strings")
    func colorHexParity() {
        // 6-digit hex (RGB, assumes alpha 1.0)
        let redHex = Color(hex: "#FF0000")
        #expect(redHex.red == 1.0)
        #expect(redHex.green == 0.0)
        #expect(redHex.blue == 0.0)
        #expect(redHex.alpha == 1.0)

        // 8-digit hex (RGBA)
        let semiTransparentBlue = Color(hex: "0000FF7F") // ~50% opacity
        #expect(semiTransparentBlue.red == 0.0)
        #expect(semiTransparentBlue.green == 0.0)
        #expect(semiTransparentBlue.blue == 1.0)
        #expect(abs(semiTransparentBlue.alpha - 0.498) < 0.01) // 127/255

        // Invalid hex should fallback safely (usually black or primary)
        let invalid = Color(hex: "GIBBERISH")
        #expect(invalid.red == 0.0)
        #expect(invalid.green == 0.0)
        #expect(invalid.blue == 0.0)
    }

    @Test("Color(rgba:) UInt32 parity")
    func colorRGBAParity() {
        // 0xRRGGBBAA
        let green = Color(rgba: 0x00FF00FF)
        #expect(green.red == 0.0)
        #expect(green.green == 1.0)
        #expect(green.blue == 0.0)
        #expect(green.alpha == 1.0)

        let semiWhite = Color(rgba: 0xFFFFFF80)
        #expect(semiWhite.red == 1.0)
        #expect(semiWhite.green == 1.0)
        #expect(semiWhite.blue == 1.0)
        #expect(abs(semiWhite.alpha - 0.5) < 0.01)
    }

    @Test("Color component access parity (RGB/Alpha)")
    func colorComponentParity() {
        let custom = Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4)
        #expect(abs(custom.red - 0.1) < 0.001)
        #expect(abs(custom.green - 0.2) < 0.001)
        #expect(abs(custom.blue - 0.3) < 0.001)
        #expect(abs(custom.alpha - 0.4) < 0.001)
    }

    // MARK: - Edge / Inset parity

    @Test("Edge.Set constants match Apple bitmasks")
    func edgeSetParity() {
        #expect(Edge.Set.top.rawValue == 1 << 0)
        #expect(Edge.Set.leading.rawValue == 1 << 1)
        #expect(Edge.Set.bottom.rawValue == 1 << 2)
        #expect(Edge.Set.trailing.rawValue == 1 << 3)
        #expect(Edge.Set.all.contains(.top))
        #expect(Edge.Set.horizontal.contains(.leading))
        #expect(Edge.Set.horizontal.contains(.trailing))
        #expect(!Edge.Set.horizontal.contains(.top))
    }

    @Test("EdgeInsets initialization parity")
    func edgeInsetsParity() {
        let insets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        #expect(insets.top == 10)
        #expect(insets.leading == 20)
        #expect(insets.bottom == 30)
        #expect(insets.trailing == 40)
    }

    // MARK: - Layout Primitives parity

    @Test("Axis set membership parity")
    func axisParity() {
        #expect(Axis.horizontal != Axis.vertical)
        #expect(Axis.Set.horizontal.contains(.horizontal))
        #expect(Axis.Set.vertical.contains(.vertical))
        #expect(!Axis.Set.horizontal.contains(.vertical))
        #expect(!Axis.Set.vertical.contains(.horizontal))
    }

    @Test("LayoutPriority constants parity")
    func layoutPriorityParity() {
        #expect(LayoutPriority.default.rawValue == 0.0)
        #expect(LayoutPriority.required.rawValue == 1000.0)
        #expect(LayoutPriority(10).rawValue == 10.0)
    }

    // MARK: - Angle parity

    @Test("Angle degrees and radians conversion parity")
    func angleParity() {
        let deg = Angle.degrees(180)
        #expect(abs(deg.radians - .pi) < 0.001)
        #expect(deg.degrees == 180.0)

        let rad = Angle.radians(.pi / 2)
        #expect(rad.degrees == 90.0)
        #expect(rad.radians == .pi / 2)

        #expect(Angle.zero.degrees == 0.0)
    }

    // MARK: - UnitPoint parity

    @Test("UnitPoint constants match Apple's coordinates")
    func unitPointParity() {
        #expect(UnitPoint.zero == UnitPoint(x: 0, y: 0))
        #expect(UnitPoint.center == UnitPoint(x: 0.5, y: 0.5))
        #expect(UnitPoint.topLeading == UnitPoint(x: 0, y: 0))
        #expect(UnitPoint.top == UnitPoint(x: 0.5, y: 0))
        #expect(UnitPoint.topTrailing == UnitPoint(x: 1, y: 0))
        #expect(UnitPoint.leading == UnitPoint(x: 0, y: 0.5))
        #expect(UnitPoint.trailing == UnitPoint(x: 1, y: 0.5))
        #expect(UnitPoint.bottomLeading == UnitPoint(x: 0, y: 1))
        #expect(UnitPoint.bottom == UnitPoint(x: 0.5, y: 1))
        #expect(UnitPoint.bottomTrailing == UnitPoint(x: 1, y: 1))
    }

    // MARK: - Layout Enums parity

    @Test("ContentMode case parity")
    func contentModeParity() {
        // Source compatibility check
        let fit = ContentMode.fit
        let fill = ContentMode.fill
        #expect(fit != fill)
    }

    @Test("Visibility case parity")
    func visibilityParity() {
        #expect(Visibility.automatic != Visibility.visible)
        #expect(Visibility.visible != Visibility.hidden)
        #expect(Visibility.hidden != Visibility.automatic)
    }

    @Test("Alignment constants presence")
    func alignmentParity() {
        // These must exist for ZStack/frame alignment
        _ = Alignment.center
        _ = Alignment.leading
        _ = Alignment.trailing
        _ = Alignment.top
        _ = Alignment.bottom
        _ = Alignment.topLeading
        _ = Alignment.topTrailing
        _ = Alignment.bottomLeading
        _ = Alignment.bottomTrailing

        _ = HorizontalAlignment.center
        _ = HorizontalAlignment.leading
        _ = HorizontalAlignment.trailing

        _ = VerticalAlignment.center
        _ = VerticalAlignment.top
        _ = VerticalAlignment.bottom
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

    // MARK: - ImageRenderer Color content parity

    /// `ImageRenderer(content: Color.red).nsImage` (or `.uiImage`) must
    /// produce a non-nil image on both platforms. On macOS this exercises real
    /// Apple SwiftUI's `ImageRenderer`, which decodes the Color into a
    /// CGImage-backed NSImage. On Linux it exercises QuillUI's shim, which
    /// extracts RGBA components and synthesizes a PNG via gdk-pixbuf
    /// (`quillRenderSolidColorImage`).
    ///
    /// We can't assert byte equality between platforms because the encoders
    /// produce different (but equivalent) bytes. We CAN assert "non-nil
    /// result" — that's the behavioral contract Apple devs depend on.
    @Test("ImageRenderer rasterizes Color content to non-nil image bytes on both platforms")
    @MainActor
    func imageRendererColorContentParity() async {
#if canImport(AppKit)
        // macOS: Apple SwiftUI's ImageRenderer.nsImage is @MainActor-isolated
        // because it touches AppKit / Core Graphics state. The @MainActor
        // annotation on the test ensures we're already on the main actor when
        // we read the property.
        let renderer = ImageRenderer(content: Color.red)
        let nsImage = renderer.nsImage
        #expect(nsImage != nil, "Apple ImageRenderer should rasterize Color.red on macOS")
#else
        // Linux: QuillUI's ImageRenderer goes through quillRenderSolidColorImage.
        let renderer = ImageRenderer(content: Color.red)
        guard let image = renderer.nsImage else {
            Issue.record("Linux ImageRenderer should rasterize Color.red via gdk-pixbuf")
            return
        }
        // The Linux PlatformImage carries PNG bytes; verify the magic.
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if let data = image.data {
            #expect(Array(data.prefix(8)) == pngMagic)
        } else {
            Issue.record("Linux PlatformImage should carry data bytes")
        }
#endif
    }

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
                let copyCount = Swift.min(8, bytes.count - i)
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
