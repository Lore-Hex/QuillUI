import Foundation
import Testing
import QuillPaint
@testable import QuillPaintCoreGraphics

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics

/// Golden tests: render each Mac-reference fixture in-memory via the
/// current code and assert it matches the PNG committed under
/// `Tests/Fixtures/MacReference/`.
///
/// These tests are the "did I just shift the renderer accidentally?"
/// safety net. If MacButtonPaint's metrics or colors change, this suite
/// fails first — well before the strict Mac-reference verifier (item 4)
/// catches it in a Linux GTK smoke run.
///
/// Tolerance: 0. A change to the fixture set MUST be paired with a
/// `swift run quill-render-mac-references` regeneration in the same PR.
@Suite("Mac-reference fixtures stay in sync with the current renderer")
struct MacReferenceGoldenTests {
    struct Case {
        let name: String
        let control: PaintControl
        let size: PaintSize
        let state: PaintControlState
    }

    static var cases: [Case] {
        [
            Case(name: "button-normal", control: MacButtonPaint(),
                 size: PaintSize(width: 80, height: 22), state: .normal),
            Case(name: "button-pressed", control: MacButtonPaint(),
                 size: PaintSize(width: 80, height: 22),
                 state: PaintControlState(isPressed: true)),
            Case(name: "button-focused", control: MacButtonPaint(),
                 size: PaintSize(width: 80, height: 22),
                 state: PaintControlState(isFocused: true)),
            Case(name: "button-disabled", control: MacButtonPaint(),
                 size: PaintSize(width: 80, height: 22),
                 state: PaintControlState(isDisabled: true)),
            Case(name: "button-default", control: MacButtonPaint(),
                 size: PaintSize(width: 80, height: 22),
                 state: PaintControlState(isDefault: true)),
            Case(name: "textfield-normal", control: MacTextFieldPaint(),
                 size: PaintSize(width: 140, height: 22), state: .normal),
            Case(name: "textfield-focused", control: MacTextFieldPaint(),
                 size: PaintSize(width: 140, height: 22),
                 state: PaintControlState(isFocused: true)),
            Case(name: "textfield-disabled", control: MacTextFieldPaint(),
                 size: PaintSize(width: 140, height: 22),
                 state: PaintControlState(isDisabled: true))
        ]
    }

    @Test("Every fixture round-trips through the current renderer", arguments: cases.map(\.name))
    func fixtureRoundTrip(name: String) throws {
        let testCase = Self.cases.first { $0.name == name }!
        let renderer = MacReferenceRenderer(margin: 8, scale: 2.0)

        // Render the candidate via the current paint code.
        let candidateImage = try renderer.renderImage(
            control: testCase.control,
            frame: testCase.size,
            state: testCase.state
        )
        let candidateBytes = try CGPixelExtraction.rawRGBA(from: candidateImage)

        // Load the committed reference PNG and decode it.
        let fixtureURL = try Self.locateFixtureURL(name: "\(name).png")
        let referenceImage = try CGPixelExtraction.loadImage(from: fixtureURL)
        let referenceBytes = try CGPixelExtraction.rawRGBA(from: referenceImage)

        #expect(referenceImage.width == candidateImage.width,
                "Reference \(name).png has stale dimensions; regenerate with `swift run quill-render-mac-references`")
        #expect(referenceImage.height == candidateImage.height,
                "Reference \(name).png has stale dimensions; regenerate with `swift run quill-render-mac-references`")

        guard referenceImage.width == candidateImage.width,
              referenceImage.height == candidateImage.height else {
            return  // already reported above
        }

        let result = try PixelComparator(tolerance: 0).compare(
            reference: referenceBytes,
            candidate: candidateBytes,
            width: candidateImage.width,
            height: candidateImage.height
        )
        #expect(result.isPerfect,
                "Reference fixture \(name).png drifted from current renderer (maxChannelDelta=\(result.maxChannelDelta), differingPixels=\(result.differingPixels)/\(result.totalPixels)). Regenerate with `swift run quill-render-mac-references`.")
    }

    /// Locate the canonical fixture directory by walking up from this source
    /// file. Works whether the test is run from the package root or via Xcode.
    private static func locateFixtureURL(name: String) throws -> URL {
        // #filePath points at this source file inside the build sandbox or
        // the workspace, depending on how tests are launched. Walking up
        // looking for the `Tests/Fixtures/MacReference/<name>` path covers
        // both cases.
        let thisFile = URL(fileURLWithPath: #filePath)
        var current = thisFile.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = current.appendingPathComponent("Tests/Fixtures/MacReference/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            current = current.deletingLastPathComponent()
        }
        // Fall back to looking under cwd.
        let cwdCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/MacReference/\(name)")
        if FileManager.default.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }
        throw FixtureLocationError.notFound(name)
    }

    enum FixtureLocationError: Error, CustomStringConvertible {
        case notFound(String)
        var description: String {
            switch self {
            case .notFound(let name): return "Could not locate fixture \(name); searched ancestors of this test file."
            }
        }
    }
}

#endif
