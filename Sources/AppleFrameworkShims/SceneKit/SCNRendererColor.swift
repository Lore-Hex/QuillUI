// SceneKit shim - software renderer color and material sampling.
import Foundation
import QuillFoundation

struct RGBA: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    static let neutral = RGBA(r: 185, g: 190, b: 198, a: 255)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(normalizedRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat = 1) {
        self.init(
            r: UInt8(clamping: Int(max(0, min(1, r)) * 255)),
            g: UInt8(clamping: Int(max(0, min(1, g)) * 255)),
            b: UInt8(clamping: Int(max(0, min(1, b)) * 255)),
            a: UInt8(clamping: Int(max(0, min(1, a)) * 255))
        )
    }

    var alpha: CGFloat {
        CGFloat(a) / 255
    }

    var luminance: CGFloat {
        (0.2126 * CGFloat(r) + 0.7152 * CGFloat(g) + 0.0722 * CGFloat(b)) / 255
    }

    func withAlphaMultiplier(_ opacity: CGFloat) -> RGBA {
        RGBA(r: r, g: g, b: b, a: UInt8(clamping: Int(CGFloat(a) * max(0, min(1, opacity)))))
    }

    func scaled(_ factor: CGFloat) -> RGBA {
        RGBA(
            r: UInt8(clamping: Int(CGFloat(r) * factor)),
            g: UInt8(clamping: Int(CGFloat(g) * factor)),
            b: UInt8(clamping: Int(CGFloat(b) * factor)),
            a: a
        )
    }

    func modulated(by other: RGBA) -> RGBA {
        RGBA(
            r: UInt8(clamping: Int(CGFloat(r) * CGFloat(other.r) / 255)),
            g: UInt8(clamping: Int(CGFloat(g) * CGFloat(other.g) / 255)),
            b: UInt8(clamping: Int(CGFloat(b) * CGFloat(other.b) / 255)),
            a: UInt8(clamping: Int(CGFloat(a) * CGFloat(other.a) / 255))
        )
    }

    func modulatedByMaterialMultiply(_ material: SCNMaterial?) -> RGBA {
        guard let material,
              material.multiply.intensity > 0,
              let multiply = color(from: material.multiply.contents) else {
            return self
        }

        let intensity = max(0, min(1, material.multiply.intensity))
        func modulate(_ component: UInt8, by multiplier: UInt8) -> UInt8 {
            let factor = (1 - intensity) + CGFloat(multiplier) / 255 * intensity
            return UInt8(clamping: Int(CGFloat(component) * factor))
        }

        return RGBA(
            r: modulate(r, by: multiply.r),
            g: modulate(g, by: multiply.g),
            b: modulate(b, by: multiply.b),
            a: a
        )
    }

    func interpolated(to other: RGBA, amount: CGFloat) -> RGBA {
        let t = max(0, min(1, amount))
        return RGBA(
            r: UInt8(clamping: Int(CGFloat(r) + (CGFloat(other.r) - CGFloat(r)) * t)),
            g: UInt8(clamping: Int(CGFloat(g) + (CGFloat(other.g) - CGFloat(g)) * t)),
            b: UInt8(clamping: Int(CGFloat(b) + (CGFloat(other.b) - CGFloat(b)) * t)),
            a: UInt8(clamping: Int(CGFloat(a) + (CGFloat(other.a) - CGFloat(a)) * t))
        )
    }

    static func average(_ lhs: RGBA, _ rhs: RGBA) -> RGBA {
        RGBA(
            r: UInt8((UInt16(lhs.r) + UInt16(rhs.r)) / 2),
            g: UInt8((UInt16(lhs.g) + UInt16(rhs.g)) / 2),
            b: UInt8((UInt16(lhs.b) + UInt16(rhs.b)) / 2),
            a: UInt8((UInt16(lhs.a) + UInt16(rhs.a)) / 2)
        )
    }

    static func interpolate(_ a: RGBA, _ b: RGBA, _ c: RGBA, weights: (CGFloat, CGFloat, CGFloat)) -> RGBA {
        func component(_ keyPath: KeyPath<RGBA, UInt8>) -> UInt8 {
            UInt8(clamping: Int(
                CGFloat(a[keyPath: keyPath]) * weights.0
                    + CGFloat(b[keyPath: keyPath]) * weights.1
                    + CGFloat(c[keyPath: keyPath]) * weights.2
            ))
        }

        return RGBA(
            r: component(\.r),
            g: component(\.g),
            b: component(\.b),
            a: component(\.a)
        )
    }
}

func color(for geometry: SCNGeometry, elementIndex: Int) -> RGBA {
    let material = material(for: geometry, elementIndex: elementIndex)
    if let material,
       material.emission.intensity > 0,
       let emission = color(from: material.emission.contents),
       emission != .black {
        return emission
            .scaled(max(0, material.emission.intensity))
            .modulatedByMaterialMultiply(material)
            .withAlphaMultiplier(material.opacityMultiplier)
    }
    let diffuse = color(from: material?.diffuse.contents) ?? .neutral
    return diffuse
        .scaled(max(0, material?.diffuse.intensity ?? 1))
        .modulatedByMaterialMultiply(material)
        .withAlphaMultiplier(material?.opacityMultiplier ?? 1)
}

func material(for geometry: SCNGeometry, elementIndex: Int) -> SCNMaterial? {
    if geometry.materials.indices.contains(elementIndex) {
        return geometry.materials[elementIndex]
    }
    return geometry.firstMaterial
}

func color(from contents: Any?) -> RGBA? {
    switch contents {
    case let color as RSColor:
        return rgba(components: color.components)
    case let color as RSCGColor:
        return rgba(components: color.components)
    case is CGImage:
        return RGBA(r: 210, g: 214, b: 218, a: 255)
    default:
        return nil
    }
}

private func rgba(components: [CGFloat]?) -> RGBA? {
    guard let components, !components.isEmpty else { return nil }
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
    if components.count == 2 {
        r = components[0]; g = components[0]; b = components[0]; a = components[1]
    } else {
        r = components[0]
        g = components.count > 1 ? components[1] : components[0]
        b = components.count > 2 ? components[2] : components[0]
        a = components.count > 3 ? components[3] : 1
    }
    return RGBA(
        r: UInt8(clamping: Int(max(0, min(1, r)) * 255)),
        g: UInt8(clamping: Int(max(0, min(1, g)) * 255)),
        b: UInt8(clamping: Int(max(0, min(1, b)) * 255)),
        a: UInt8(clamping: Int(max(0, min(1, a)) * 255))
    )
}

private extension SCNMaterial {
    var opacityMultiplier: CGFloat {
        max(0, min(1, transparency)) * transparentOpacityMultiplier
    }

    var transparentOpacityMultiplier: CGFloat {
        guard let transparentColor = color(from: transparent.contents) else {
            return 1
        }

        let sampledOpacity: CGFloat
        switch transparencyMode {
        case .rgbZero:
            sampledOpacity = transparentColor.luminance
        case .aOne, .singleLayer, .dualLayer:
            sampledOpacity = transparentColor.alpha
        }

        let intensity = max(0, min(1, transparent.intensity))
        return 1 - (1 - sampledOpacity) * intensity
    }
}
