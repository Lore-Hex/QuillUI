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
