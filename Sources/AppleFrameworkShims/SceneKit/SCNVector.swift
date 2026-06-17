// SceneKit shim — vector / quaternion / matrix value types.
//
// Models macOS SceneKit's geometry value types so real macOS SwiftUI+SceneKit
// apps (the QuillSceneKit fixtures, Euclid's interop, ShapeScript's Viewer)
// compile unmodified on QuillOS. On macOS these are CGFloat-based; CGFloat is
// Double on 64-bit Linux, so the same source — `SCNVector3(someDouble, 0, 0)`
// — type-checks here too.
import Foundation
import QuillFoundation

public struct SCNVector3: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat

    public init() {
        self.init(0, 0, 0)
    }

    public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: CGFloat, y: CGFloat, z: CGFloat) {
        self.init(x, y, z)
    }

    public init(_ vector: SIMD3<Float>) {
        self.init(CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z))
    }

    var quillSIMD3: SIMD3<Float> {
        SIMD3(Float(x), Float(y), Float(z))
    }
}

public func SCNVector3Make(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
    SCNVector3(x, y, z)
}

public struct SCNVector4: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    public var w: CGFloat

    public init() {
        self.init(0, 0, 0, 0)
    }

    public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) {
        self.init(x, y, z, w)
    }
}

public func SCNVector4Make(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat) -> SCNVector4 {
    SCNVector4(x, y, z, w)
}

/// On Apple platforms `SCNQuaternion` is a typealias for `SCNVector4`; matching
/// that keeps Euclid's `init(_ rotation: Rotation)` extension unambiguous.
public typealias SCNQuaternion = SCNVector4

/// A 4x4 transform matrix matching SceneKit/CATransform3D's public field
/// layout: translation lives in m41/m42/m43. Identity by default.
public struct SCNMatrix4: Equatable, Sendable {
    public var m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat
    public var m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat
    public var m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat
    public var m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat

    public init() {
        self = SCNMatrix4Identity
    }

    public init(
        m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat,
        m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat,
        m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat,
        m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }
}

public let SCNMatrix4Identity = SCNMatrix4(
    m11: 1, m12: 0, m13: 0, m14: 0,
    m21: 0, m22: 1, m23: 0, m24: 0,
    m31: 0, m32: 0, m33: 1, m34: 0,
    m41: 0, m42: 0, m43: 0, m44: 1
)

public func SCNMatrix4IsIdentity(_ m: SCNMatrix4) -> Bool {
    m == SCNMatrix4Identity
}

public func SCNMatrix4EqualToMatrix4(_ a: SCNMatrix4, _ b: SCNMatrix4) -> Bool {
    a == b
}

public func SCNMatrix4MakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> SCNMatrix4 {
    SCNMatrix4(
        m11: 1, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 1, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: tx, m42: ty, m43: tz, m44: 1
    )
}

public func SCNMatrix4MakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> SCNMatrix4 {
    SCNMatrix4(
        m11: sx, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: sy, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: sz, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1
    )
}

public func SCNMatrix4MakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNMatrix4 {
    let length = (x * x + y * y + z * z).squareRoot()
    guard length > 0 else { return SCNMatrix4Identity }

    let x = x / length
    let y = y / length
    let z = z / length
    let c = cos(angle)
    let s = sin(angle)
    let t = 1 - c

    return SCNMatrix4(
        m11: t * x * x + c,
        m12: t * x * y + z * s,
        m13: t * x * z - y * s,
        m14: 0,
        m21: t * x * y - z * s,
        m22: t * y * y + c,
        m23: t * y * z + x * s,
        m24: 0,
        m31: t * x * z + y * s,
        m32: t * y * z - x * s,
        m33: t * z * z + c,
        m34: 0,
        m41: 0,
        m42: 0,
        m43: 0,
        m44: 1
    )
}

public func SCNMatrix4Translate(_ m: SCNMatrix4, _ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> SCNMatrix4 {
    var translated = m
    translated.m41 += tx
    translated.m42 += ty
    translated.m43 += tz
    return translated
}

public func SCNMatrix4Scale(_ m: SCNMatrix4, _ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> SCNMatrix4 {
    SCNMatrix4Mult(SCNMatrix4MakeScale(sx, sy, sz), m)
}

public func SCNMatrix4Rotate(_ m: SCNMatrix4, _ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNMatrix4 {
    SCNMatrix4Mult(SCNMatrix4MakeRotation(angle, x, y, z), m)
}

public func SCNMatrix4Mult(_ a: SCNMatrix4, _ b: SCNMatrix4) -> SCNMatrix4 {
    SCNMatrix4(
        m11: a.m11 * b.m11 + a.m12 * b.m21 + a.m13 * b.m31 + a.m14 * b.m41,
        m12: a.m11 * b.m12 + a.m12 * b.m22 + a.m13 * b.m32 + a.m14 * b.m42,
        m13: a.m11 * b.m13 + a.m12 * b.m23 + a.m13 * b.m33 + a.m14 * b.m43,
        m14: a.m11 * b.m14 + a.m12 * b.m24 + a.m13 * b.m34 + a.m14 * b.m44,
        m21: a.m21 * b.m11 + a.m22 * b.m21 + a.m23 * b.m31 + a.m24 * b.m41,
        m22: a.m21 * b.m12 + a.m22 * b.m22 + a.m23 * b.m32 + a.m24 * b.m42,
        m23: a.m21 * b.m13 + a.m22 * b.m23 + a.m23 * b.m33 + a.m24 * b.m43,
        m24: a.m21 * b.m14 + a.m22 * b.m24 + a.m23 * b.m34 + a.m24 * b.m44,
        m31: a.m31 * b.m11 + a.m32 * b.m21 + a.m33 * b.m31 + a.m34 * b.m41,
        m32: a.m31 * b.m12 + a.m32 * b.m22 + a.m33 * b.m32 + a.m34 * b.m42,
        m33: a.m31 * b.m13 + a.m32 * b.m23 + a.m33 * b.m33 + a.m34 * b.m43,
        m34: a.m31 * b.m14 + a.m32 * b.m24 + a.m33 * b.m34 + a.m34 * b.m44,
        m41: a.m41 * b.m11 + a.m42 * b.m21 + a.m43 * b.m31 + a.m44 * b.m41,
        m42: a.m41 * b.m12 + a.m42 * b.m22 + a.m43 * b.m32 + a.m44 * b.m42,
        m43: a.m41 * b.m13 + a.m42 * b.m23 + a.m43 * b.m33 + a.m44 * b.m43,
        m44: a.m41 * b.m14 + a.m42 * b.m24 + a.m43 * b.m34 + a.m44 * b.m44
    )
}

/// Full 4x4 inverse (cofactor / adjugate method), matching `SCNMatrix4Invert`.
/// Returns the identity for a singular matrix, as SceneKit does.
public func SCNMatrix4Invert(_ m: SCNMatrix4) -> SCNMatrix4 {
    let a = [
        m.m11, m.m12, m.m13, m.m14,
        m.m21, m.m22, m.m23, m.m24,
        m.m31, m.m32, m.m33, m.m34,
        m.m41, m.m42, m.m43, m.m44,
    ]
    var inv = [CGFloat](repeating: 0, count: 16)

    inv[0] = a[5]*a[10]*a[15] - a[5]*a[11]*a[14] - a[9]*a[6]*a[15] + a[9]*a[7]*a[14] + a[13]*a[6]*a[11] - a[13]*a[7]*a[10]
    inv[4] = -a[4]*a[10]*a[15] + a[4]*a[11]*a[14] + a[8]*a[6]*a[15] - a[8]*a[7]*a[14] - a[12]*a[6]*a[11] + a[12]*a[7]*a[10]
    inv[8] = a[4]*a[9]*a[15] - a[4]*a[11]*a[13] - a[8]*a[5]*a[15] + a[8]*a[7]*a[13] + a[12]*a[5]*a[11] - a[12]*a[7]*a[9]
    inv[12] = -a[4]*a[9]*a[14] + a[4]*a[10]*a[13] + a[8]*a[5]*a[14] - a[8]*a[6]*a[13] - a[12]*a[5]*a[10] + a[12]*a[6]*a[9]
    inv[1] = -a[1]*a[10]*a[15] + a[1]*a[11]*a[14] + a[9]*a[2]*a[15] - a[9]*a[3]*a[14] - a[13]*a[2]*a[11] + a[13]*a[3]*a[10]
    inv[5] = a[0]*a[10]*a[15] - a[0]*a[11]*a[14] - a[8]*a[2]*a[15] + a[8]*a[3]*a[14] + a[12]*a[2]*a[11] - a[12]*a[3]*a[10]
    inv[9] = -a[0]*a[9]*a[15] + a[0]*a[11]*a[13] + a[8]*a[1]*a[15] - a[8]*a[3]*a[13] - a[12]*a[1]*a[11] + a[12]*a[3]*a[9]
    inv[13] = a[0]*a[9]*a[14] - a[0]*a[10]*a[13] - a[8]*a[1]*a[14] + a[8]*a[2]*a[13] + a[12]*a[1]*a[10] - a[12]*a[2]*a[9]
    inv[2] = a[1]*a[6]*a[15] - a[1]*a[7]*a[14] - a[5]*a[2]*a[15] + a[5]*a[3]*a[14] + a[13]*a[2]*a[7] - a[13]*a[3]*a[6]
    inv[6] = -a[0]*a[6]*a[15] + a[0]*a[7]*a[14] + a[4]*a[2]*a[15] - a[4]*a[3]*a[14] - a[12]*a[2]*a[7] + a[12]*a[3]*a[6]
    inv[10] = a[0]*a[5]*a[15] - a[0]*a[7]*a[13] - a[4]*a[1]*a[15] + a[4]*a[3]*a[13] + a[12]*a[1]*a[7] - a[12]*a[3]*a[5]
    inv[14] = -a[0]*a[5]*a[14] + a[0]*a[6]*a[13] + a[4]*a[1]*a[14] - a[4]*a[2]*a[13] - a[12]*a[1]*a[6] + a[12]*a[2]*a[5]
    inv[3] = -a[1]*a[6]*a[11] + a[1]*a[7]*a[10] + a[5]*a[2]*a[11] - a[5]*a[3]*a[10] - a[9]*a[2]*a[7] + a[9]*a[3]*a[6]
    inv[7] = a[0]*a[6]*a[11] - a[0]*a[7]*a[10] - a[4]*a[2]*a[11] + a[4]*a[3]*a[10] + a[8]*a[2]*a[7] - a[8]*a[3]*a[6]
    inv[11] = -a[0]*a[5]*a[11] + a[0]*a[7]*a[9] + a[4]*a[1]*a[11] - a[4]*a[3]*a[9] - a[8]*a[1]*a[7] + a[8]*a[3]*a[5]
    inv[15] = a[0]*a[5]*a[10] - a[0]*a[6]*a[9] - a[4]*a[1]*a[10] + a[4]*a[2]*a[9] + a[8]*a[1]*a[6] - a[8]*a[2]*a[5]

    let det = a[0]*inv[0] + a[1]*inv[4] + a[2]*inv[8] + a[3]*inv[12]
    guard det != 0 else { return SCNMatrix4Identity }
    let invDet = 1 / det
    for i in 0..<16 { inv[i] *= invDet }
    return SCNMatrix4(
        m11: inv[0], m12: inv[1], m13: inv[2], m14: inv[3],
        m21: inv[4], m22: inv[5], m23: inv[6], m24: inv[7],
        m31: inv[8], m32: inv[9], m33: inv[10], m34: inv[11],
        m41: inv[12], m42: inv[13], m43: inv[14], m44: inv[15]
    )
}
