import Foundation

/// Result of comparing two RGBA bitmaps pixel-by-pixel.
public struct PixelComparisonResult: Equatable {
    /// Fraction of pixels (0...1) whose per-channel diff was within tolerance.
    /// A value of `1.0` means every pixel matched within tolerance; `0.0`
    /// means none did. The strict Mac-reference verifier (Roadmap item 4)
    /// targets `≥ 0.95`.
    public let matchRatio: Double

    /// Number of pixels whose diff exceeded the tolerance.
    public let differingPixels: Int

    /// Total pixel count in the compared images.
    public let totalPixels: Int

    /// Maximum absolute per-channel byte difference observed across the
    /// entire image. `0` means perfect match; `255` means at least one
    /// channel diverged from black ↔ white.
    public let maxChannelDelta: Int

    public var isPerfect: Bool { maxChannelDelta == 0 }
    public var passes: Bool { differingPixels == 0 }
}

/// Reasons a comparison could fail to run.
public enum PixelComparatorError: Error, CustomStringConvertible {
    case dimensionMismatch(referenceWidth: Int, referenceHeight: Int, candidateWidth: Int, candidateHeight: Int)
    case dataLengthMismatch(width: Int, height: Int, expectedBytes: Int, actualBytes: Int)

    public var description: String {
        switch self {
        case let .dimensionMismatch(rw, rh, cw, ch):
            return "Image dimensions disagree: reference \(rw)×\(rh), candidate \(cw)×\(ch)."
        case let .dataLengthMismatch(w, h, expected, actual):
            return "Raw RGBA byte length is wrong for \(w)×\(h): expected \(expected), got \(actual)."
        }
    }
}

/// Compares two equally-sized RGBA bitmaps with a per-channel tolerance.
///
/// This is the format-agnostic core of the Mac-reference verifier — give
/// it raw RGBA from a CoreGraphics, Cairo, or Skia bitmap and it reports
/// how close they are. PNG-to-RGBA decoding lives in per-backend helpers
/// (CG on Apple, libpng on Linux) so this type stays Foundation-only.
///
/// Tolerance is in bytes (0...255). A tolerance of 0 means strict
/// byte-for-byte equality. The strict Mac-reference verifier uses 2
/// (~0.8% per channel) to tolerate minor anti-aliasing rounding while
/// catching genuine visual drift.
public struct PixelComparator {
    public var tolerance: UInt8

    public init(tolerance: UInt8 = 0) {
        self.tolerance = tolerance
    }

    public func compare(
        reference: Data,
        candidate: Data,
        width: Int,
        height: Int
    ) throws -> PixelComparisonResult {
        let expectedBytes = width * height * 4
        if reference.count != expectedBytes {
            throw PixelComparatorError.dataLengthMismatch(
                width: width, height: height,
                expectedBytes: expectedBytes, actualBytes: reference.count
            )
        }
        if candidate.count != expectedBytes {
            throw PixelComparatorError.dataLengthMismatch(
                width: width, height: height,
                expectedBytes: expectedBytes, actualBytes: candidate.count
            )
        }

        let totalPixels = width * height
        if totalPixels == 0 {
            return PixelComparisonResult(
                matchRatio: 1.0,
                differingPixels: 0,
                totalPixels: 0,
                maxChannelDelta: 0
            )
        }

        var differingPixels = 0
        var maxDelta: Int = 0
        let tol = Int(tolerance)

        reference.withUnsafeBytes { refRaw in
            candidate.withUnsafeBytes { candRaw in
                guard let refPtr = refRaw.bindMemory(to: UInt8.self).baseAddress,
                      let candPtr = candRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                var i = 0
                while i < expectedBytes {
                    let dr = Self.absDiff(refPtr[i], candPtr[i])
                    let dg = Self.absDiff(refPtr[i + 1], candPtr[i + 1])
                    let db = Self.absDiff(refPtr[i + 2], candPtr[i + 2])
                    let da = Self.absDiff(refPtr[i + 3], candPtr[i + 3])
                    let pixelMax = max(max(dr, dg), max(db, da))
                    if pixelMax > maxDelta { maxDelta = pixelMax }
                    if pixelMax > tol { differingPixels += 1 }
                    i += 4
                }
            }
        }

        let matchRatio = Double(totalPixels - differingPixels) / Double(totalPixels)
        return PixelComparisonResult(
            matchRatio: matchRatio,
            differingPixels: differingPixels,
            totalPixels: totalPixels,
            maxChannelDelta: maxDelta
        )
    }

    private static func absDiff(_ a: UInt8, _ b: UInt8) -> Int {
        a > b ? Int(a) - Int(b) : Int(b) - Int(a)
    }
}
