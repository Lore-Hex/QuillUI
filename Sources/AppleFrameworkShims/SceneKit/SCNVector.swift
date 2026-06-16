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

/// On Apple platforms `SCNQuaternion` is a typealias for `SCNVector4`; matching
/// that keeps Euclid's `init(_ rotation: Rotation)` extension unambiguous.
public typealias SCNQuaternion = SCNVector4

/// A 4x4 column-major transform matrix (row-vector layout matching SceneKit's
/// `SCNMatrix4`: m11…m44). Identity by default.
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
