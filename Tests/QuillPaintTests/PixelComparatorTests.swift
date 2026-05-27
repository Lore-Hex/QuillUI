import Foundation
import Testing
@testable import QuillPaint

@Suite("PixelComparator")
struct PixelComparatorTests {
    @Test("Identical bitmaps produce a perfect match")
    func identical() throws {
        let bytes = Data((0..<16).map { UInt8($0) })  // 4 pixels (4 * 4 bytes)
        let result = try PixelComparator(tolerance: 0).compare(
            reference: bytes, candidate: bytes, width: 2, height: 2
        )
        #expect(result.isPerfect)
        #expect(result.passes)
        #expect(result.matchRatio == 1.0)
        #expect(result.differingPixels == 0)
        #expect(result.maxChannelDelta == 0)
    }

    @Test("Single differing pixel is counted")
    func singleDifferingPixel() throws {
        let ref = Data([255, 255, 255, 255, /*p2*/ 0, 0, 0, 255])
        // p2's red flipped by 10
        let cand = Data([255, 255, 255, 255, /*p2*/ 10, 0, 0, 255])
        let result = try PixelComparator(tolerance: 0).compare(
            reference: ref, candidate: cand, width: 2, height: 1
        )
        #expect(!result.isPerfect)
        #expect(!result.passes)
        #expect(result.differingPixels == 1)
        #expect(result.totalPixels == 2)
        #expect(result.matchRatio == 0.5)
        #expect(result.maxChannelDelta == 10)
    }

    @Test("Tolerance suppresses sub-threshold differences")
    func toleranceSuppressesSmallDiffs() throws {
        let ref = Data([100, 100, 100, 255, 200, 200, 200, 255])
        let cand = Data([102, 100, 100, 255, 200, 198, 200, 255])
        let strict = try PixelComparator(tolerance: 0).compare(
            reference: ref, candidate: cand, width: 2, height: 1
        )
        #expect(strict.differingPixels == 2)
        #expect(strict.maxChannelDelta == 2)

        let lenient = try PixelComparator(tolerance: 2).compare(
            reference: ref, candidate: cand, width: 2, height: 1
        )
        #expect(lenient.differingPixels == 0)
        #expect(lenient.passes)
        // maxChannelDelta still tracks the raw delta, regardless of tolerance
        #expect(lenient.maxChannelDelta == 2)
    }

    @Test("Dimension mismatch in either dimension throws")
    func dimensionMismatchThrows() {
        let twoPixels = Data(repeating: 0, count: 8)
        let onePixel = Data(repeating: 0, count: 4)
        #expect(throws: PixelComparatorError.self) {
            try PixelComparator().compare(
                reference: twoPixels, candidate: onePixel, width: 1, height: 1
            )
        }
    }

    @Test("Zero-sized bitmap reports trivially perfect")
    func zeroSized() throws {
        let result = try PixelComparator().compare(
            reference: Data(), candidate: Data(), width: 0, height: 0
        )
        #expect(result.matchRatio == 1.0)
        #expect(result.totalPixels == 0)
    }
}
