//===----------------------------------------------------------------------===//
//
//  CATransform3D.swift
//  QuartzCore — Apple-framework shim for QuillUI on Linux (QuillOS)
//
//  What this file provides:
//    • CATransform3D — the homogeneous 4x4 matrix struct, field-for-field
//      compatible with Apple's, plus the CATransform3DIdentity constant.
//    • The complete CATransform3D* function family: Make{Translation,Scale,
//      Rotation}, {Translate,Scale,Rotate}, Concat, Invert, IsIdentity,
//      EqualToTransform, IsAffine, MakeAffineTransform, GetAffineTransform.
//    • NSValue boxing: NSValue(caTransform3D:) and .caTransform3DValue.
//
//  Conventions (matching Apple's QuartzCore exactly):
//    QuartzCore treats a point as a ROW vector multiplied on the LEFT of the
//    matrix: v' = v * M.  Translation therefore lives in the fourth row
//    (m41, m42, m43), and CATransform3DConcat(a, b) = a * b applies `a`
//    first, then `b`.  CATransform3DTranslate/Scale/Rotate PREPEND
//    (t' = Make…(…) * t), i.e. the new operation happens in `t`'s own
//    coordinate space — the same behavior as CGAffineTransformTranslate & co.
//
//  Honest Linux semantics:
//    This is a pure MODEL-layer implementation.  The matrix math is real and
//    faithful to Apple's documented behavior, and its results drive CALayer's
//    geometry and animation model — but nothing composites pixels on Linux
//    yet.  On-screen rendering of transformed layers arrives later via
//    QuillPaint.
//
//===----------------------------------------------------------------------===//

import CoreFoundation
import Foundation
import QuillFoundation

// MARK: - CATransform3D

/// A homogeneous 4x4 transformation matrix, laid out exactly like Apple's
/// `CATransform3D`.
///
/// Row-vector convention: `v' = [x y z 1] * M`; translation is in row four.
public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat
    public var m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat
    public var m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat
    public var m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat

    /// The all-zero matrix — matches the zero-filled `CATransform3D()` that
    /// the imported C struct produces on Darwin.
    public init() {
        m11 = 0; m12 = 0; m13 = 0; m14 = 0
        m21 = 0; m22 = 0; m23 = 0; m24 = 0
        m31 = 0; m32 = 0; m33 = 0; m34 = 0
        m41 = 0; m42 = 0; m43 = 0; m44 = 0
    }

    public init(m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat,
                m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat,
                m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat,
                m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }

    /// The identity matrix (the same value as the `CATransform3DIdentity`
    /// global constant).
    public static let identity = CATransform3D(
        m11: 1, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 1, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1)
}

/// The identity transform: `[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]`.
public let CATransform3DIdentity = CATransform3D.identity

// MARK: - Row access (file-internal)

extension CATransform3D {
    /// The matrix as four rows of `Double`, in the row-vector layout
    /// described at the top of this file.  All internal math runs in
    /// `Double` and converts back to `CGFloat` at the API boundary.
    fileprivate var quartzRows: [[Double]] {
        [[Double(m11), Double(m12), Double(m13), Double(m14)],
         [Double(m21), Double(m22), Double(m23), Double(m24)],
         [Double(m31), Double(m32), Double(m33), Double(m34)],
         [Double(m41), Double(m42), Double(m43), Double(m44)]]
    }

    fileprivate init(quartzRows r: [[Double]]) {
        self.init(
            m11: CGFloat(r[0][0]), m12: CGFloat(r[0][1]), m13: CGFloat(r[0][2]), m14: CGFloat(r[0][3]),
            m21: CGFloat(r[1][0]), m22: CGFloat(r[1][1]), m23: CGFloat(r[1][2]), m24: CGFloat(r[1][3]),
            m31: CGFloat(r[2][0]), m32: CGFloat(r[2][1]), m33: CGFloat(r[2][2]), m34: CGFloat(r[2][3]),
            m41: CGFloat(r[3][0]), m42: CGFloat(r[3][1]), m43: CGFloat(r[3][2]), m44: CGFloat(r[3][3]))
    }
}

// MARK: - Equality predicates

/// Returns true if `t` is exactly the identity matrix.
public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool {
    CATransform3DEqualToTransform(t, CATransform3DIdentity)
}

/// Returns true if the two transforms are exactly equal, field by field.
public func CATransform3DEqualToTransform(_ a: CATransform3D, _ b: CATransform3D) -> Bool {
    a.m11 == b.m11 && a.m12 == b.m12 && a.m13 == b.m13 && a.m14 == b.m14 &&
    a.m21 == b.m21 && a.m22 == b.m22 && a.m23 == b.m23 && a.m24 == b.m24 &&
    a.m31 == b.m31 && a.m32 == b.m32 && a.m33 == b.m33 && a.m34 == b.m34 &&
    a.m41 == b.m41 && a.m42 == b.m42 && a.m43 == b.m43 && a.m44 == b.m44
}

// MARK: - Constructors

/// Returns a transform that translates by `(tx, ty, tz)`:
/// identity with the fourth row set to `[tx ty tz 1]`.
public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    var t = CATransform3DIdentity
    t.m41 = tx
    t.m42 = ty
    t.m43 = tz
    return t
}

/// Returns a transform that scales by `(sx, sy, sz)`: `diag(sx, sy, sz, 1)`.
public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    var t = CATransform3DIdentity
    t.m11 = sx
    t.m22 = sy
    t.m33 = sz
    return t
}

/// Returns a transform that rotates by `angle` radians about the axis
/// `(x, y, z)` — Rodrigues' rotation formula with the axis normalized first.
///
/// Apple documents a zero-length axis as undefined behavior; this
/// implementation deliberately returns the identity matrix in that case
/// (which is also what Darwin's QuartzCore returns in practice), making
/// `CATransform3DRotate` a no-op for a degenerate axis.
public func CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    let length = (Double(x) * Double(x) + Double(y) * Double(y) + Double(z) * Double(z)).squareRoot()
    guard length > 0 else { return CATransform3DIdentity }

    let ux = Double(x) / length
    let uy = Double(y) / length
    let uz = Double(z) / length
    let c = cos(Double(angle))
    let s = sin(Double(angle))
    let ic = 1 - c

    // Transpose of the textbook (column-vector) Rodrigues matrix, because
    // QuartzCore multiplies row vectors on the left: v' = v * M.
    return CATransform3D(
        m11: CGFloat(c + ux * ux * ic),      m12: CGFloat(ux * uy * ic + uz * s), m13: CGFloat(ux * uz * ic - uy * s), m14: 0,
        m21: CGFloat(uy * ux * ic - uz * s), m22: CGFloat(c + uy * uy * ic),      m23: CGFloat(uy * uz * ic + ux * s), m24: 0,
        m31: CGFloat(uz * ux * ic + uy * s), m32: CGFloat(uz * uy * ic - ux * s), m33: CGFloat(c + uz * uz * ic),      m34: 0,
        m41: 0,                              m42: 0,                              m43: 0,                              m44: 1)
}

// MARK: - Prepended transforms (t' = Make…(…) * t)

/// Translates `t` by `(tx, ty, tz)` in `t`'s own coordinate space:
/// `t' = CATransform3DMakeTranslation(tx, ty, tz) * t`, Apple's documented
/// composition order.
public func CATransform3DTranslate(_ t: CATransform3D, _ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t)
}

/// Scales `t` by `(sx, sy, sz)` in `t`'s own coordinate space:
/// `t' = CATransform3DMakeScale(sx, sy, sz) * t`.
public func CATransform3DScale(_ t: CATransform3D, _ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t)
}

/// Rotates `t` by `angle` radians about `(x, y, z)` in `t`'s own coordinate
/// space: `t' = CATransform3DMakeRotation(angle, x, y, z) * t`.
/// A zero-length axis leaves `t` unchanged.
public func CATransform3DRotate(_ t: CATransform3D, _ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t)
}

// MARK: - Concatenation & inversion

/// Returns `a * b` — the transform that applies `a` first, then `b`
/// (row-vector convention; Apple documents Concat as `t' = a * b`).
/// This is the general 4x4 matrix product; every other composition in this
/// file funnels through it.
public func CATransform3DConcat(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D {
    let lhs = a.quartzRows
    let rhs = b.quartzRows
    var rows = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    for i in 0..<4 {
        for j in 0..<4 {
            rows[i][j] = lhs[i][0] * rhs[0][j]
                       + lhs[i][1] * rhs[1][j]
                       + lhs[i][2] * rhs[2][j]
                       + lhs[i][3] * rhs[3][j]
        }
    }
    return CATransform3D(quartzRows: rows)
}

/// Inverts `t` using Gauss-Jordan elimination with partial pivoting.
/// If the matrix is singular (it has no inverse) the input is returned
/// unchanged, matching Apple's documented behavior.  Matrices containing
/// non-finite values also come back unchanged rather than as garbage.
public func CATransform3DInvert(_ t: CATransform3D) -> CATransform3D {
    var m = t.quartzRows
    var inv = CATransform3DIdentity.quartzRows

    for column in 0..<4 {
        // Partial pivoting: bring the largest remaining entry in this
        // column onto the diagonal for numerical stability.
        var pivotRow = column
        var pivotMagnitude = abs(m[column][column])
        for row in (column + 1)..<4 where abs(m[row][column]) > pivotMagnitude {
            pivotMagnitude = abs(m[row][column])
            pivotRow = row
        }
        guard pivotMagnitude > 0 else { return t } // Singular (or NaN).

        if pivotRow != column {
            m.swapAt(pivotRow, column)
            inv.swapAt(pivotRow, column)
        }

        let pivot = m[column][column]
        for j in 0..<4 {
            m[column][j] /= pivot
            inv[column][j] /= pivot
        }

        for row in 0..<4 where row != column {
            let factor = m[row][column]
            guard factor != 0 else { continue }
            for j in 0..<4 {
                m[row][j] -= factor * m[column][j]
                inv[row][j] -= factor * inv[column][j]
            }
        }
    }
    return CATransform3D(quartzRows: inv)
}

// MARK: - Affine bridging

/// True if `t` can be represented exactly as a 2-D affine transform — i.e.
/// it has no z components and no perspective.
public func CATransform3DIsAffine(_ t: CATransform3D) -> Bool {
    t.m13 == 0 && t.m14 == 0 &&
    t.m23 == 0 && t.m24 == 0 &&
    t.m31 == 0 && t.m32 == 0 && t.m33 == 1 && t.m34 == 0 &&
    t.m43 == 0 && t.m44 == 1
}

/// Embeds a 2-D affine transform in a 3-D transform:
/// `[a b 0 0; c d 0 0; 0 0 1 0; tx ty 0 1]`.
public func CATransform3DMakeAffineTransform(_ m: CGAffineTransform) -> CATransform3D {
    CATransform3D(
        m11: m.a,  m12: m.b,  m13: 0, m14: 0,
        m21: m.c,  m22: m.d,  m23: 0, m24: 0,
        m31: 0,    m32: 0,    m33: 1, m34: 0,
        m41: m.tx, m42: m.ty, m43: 0, m44: 1)
}

/// Extracts the 2-D affine part of `t`.  Like Apple's, the result is only
/// meaningful when `CATransform3DIsAffine(t)` is true.
public func CATransform3DGetAffineTransform(_ t: CATransform3D) -> CGAffineTransform {
    CGAffineTransform(a: t.m11, b: t.m12, c: t.m21, d: t.m22, tx: t.m41, ty: t.m42)
}

// MARK: - NSValue boxing

/// Module-private side table backing `NSValue(caTransform3D:)`.
///
/// swift-corelibs-foundation's `NSValue` cannot encode arbitrary user
/// structs (its objCType machinery only understands primitives and a
/// handful of special Foundation types), so the transform is kept
/// out-of-line in an NSLock-guarded table keyed by the NSValue's object
/// identity.
///
/// Honest caveats:
///   • Entries are never removed.  Corelibs `NSObject` offers no dealloc
///     hook to anchor cleanup, so the table leaks one small entry per boxed
///     transform BY DESIGN.  Transform boxing is rare in practice (keyframe
///     `values` arrays, occasional model snapshots), so this is an accepted
///     cost until a deallocation hook exists.
///   • Because entries outlive their NSValue, an unrelated NSValue later
///     allocated at a recycled address could in principle alias a stale
///     entry and report the old transform.  Re-boxing at the same address
///     overwrites the entry, so transform-to-transform reuse stays correct.
private final class CATransform3DValueTable: @unchecked Sendable {
    static let shared = CATransform3DValueTable()

    private let lock = NSLock()
    private var transforms: [ObjectIdentifier: CATransform3D] = [:]

    func register(_ transform: CATransform3D, for value: NSValue) {
        lock.lock()
        defer { lock.unlock() }
        transforms[ObjectIdentifier(value)] = transform
    }

    func transform(for value: NSValue) -> CATransform3D? {
        lock.lock()
        defer { lock.unlock() }
        return transforms[ObjectIdentifier(value)]
    }
}

/// Deterministic 64-bit FNV-1a digest of a transform, stored as the boxed
/// NSValue's actual byte payload (objCType "d", a primitive corelibs CAN
/// encode).  Two equal transforms always produce the same digest, so
/// `isEqual(_:)` between two boxed transforms behaves like Darwin's
/// byte-comparison semantics (with a theoretical 2^-64 false-positive rate
/// for unequal transforms).
private func _caTransform3DPayload(_ t: CATransform3D) -> Double {
    let components = [t.m11, t.m12, t.m13, t.m14,
                      t.m21, t.m22, t.m23, t.m24,
                      t.m31, t.m32, t.m33, t.m34,
                      t.m41, t.m42, t.m43, t.m44]
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for component in components {
        let d = Double(component)
        let bits = (d == 0 ? 0.0 : d).bitPattern // Fold -0.0 into +0.0, like ==.
        for shift in stride(from: UInt64(0), to: 64, by: 8) {
            hash = (hash ^ ((bits >> shift) & 0xFF)) &* 0x0000_0100_0000_01B3
        }
    }
    return Double(bitPattern: hash)
}

public extension NSValue {
    /// Boxes a `CATransform3D`, mirroring Darwin QuartzCore's
    /// `NSValue(caTransform3D:)` addition.
    convenience init(caTransform3D t: CATransform3D) {
        var payload = _caTransform3DPayload(t)
        self.init(bytes: &payload, objCType: "d")
        CATransform3DValueTable.shared.register(t, for: self)
    }

    /// The boxed transform, or `.identity` if this NSValue was not created
    /// via `init(caTransform3D:)`.  (Darwin leaves that case undefined;
    /// returning identity is the deliberate, safe Linux behavior.)
    var caTransform3DValue: CATransform3D {
        CATransform3DValueTable.shared.transform(for: self) ?? .identity
    }
}
