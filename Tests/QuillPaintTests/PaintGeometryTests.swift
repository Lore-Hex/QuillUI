import Foundation
import Testing
@testable import QuillPaint

@Suite("Paint geometry types")
struct PaintGeometryTests {

    @Test("PaintPoint equality and hashing")
    func paintPointBasics() {
        let p1 = PaintPoint(x: 10, y: 20)
        let p2 = PaintPoint(x: 10, y: 20)
        let p3 = PaintPoint(x: 0, y: 0)

        #expect(p1 == p2)
        #expect(p1 != p3)
        #expect(PaintPoint.zero == p3)

        let set: Set<PaintPoint> = [p1, p2, p3]
        #expect(set.count == 2)
        #expect(set.contains(p1))
        #expect(set.contains(p3))
    }

    @Test("PaintSize equality and hashing")
    func paintSizeBasics() {
        let s1 = PaintSize(width: 100, height: 200)
        let s2 = PaintSize(width: 100, height: 200)
        let s3 = PaintSize(width: 0, height: 0)

        #expect(s1 == s2)
        #expect(s1 != s3)
        #expect(PaintSize.zero == s3)

        let set: Set<PaintSize> = [s1, s2, s3]
        #expect(set.count == 2)
        #expect(set.contains(s1))
        #expect(set.contains(s3))
    }

    @Test("PaintRect properties (min/mid/max)")
    func paintRectProperties() {
        let rect = PaintRect(x: 10, y: 20, width: 100, height: 200)

        #expect(rect.minX == 10)
        #expect(rect.minY == 20)
        #expect(rect.maxX == 110)
        #expect(rect.maxY == 220)
        #expect(rect.midX == 60)
        #expect(rect.midY == 120)

        let zero = PaintRect.zero
        #expect(zero.origin == .zero)
        #expect(zero.size == .zero)
    }

    @Test("PaintRect insetBy")
    func paintRectInset() {
        let rect = PaintRect(x: 10, y: 20, width: 100, height: 200)

        // Positive inset
        let inset = rect.insetBy(dx: 10, dy: 20)
        #expect(inset.origin.x == 20)
        #expect(inset.origin.y == 40)
        #expect(inset.size.width == 80)
        #expect(inset.size.height == 160)

        // Negative inset (expansion)
        let expanded = rect.insetBy(dx: -10, dy: -20)
        #expect(expanded.origin.x == 0)
        #expect(expanded.origin.y == 0)
        #expect(expanded.size.width == 120)
        #expect(expanded.size.height == 240)

        // Inset that results in zero/negative size should be clamped to 0
        let clamped = rect.insetBy(dx: 60, dy: 110)
        #expect(clamped.size.width == 0)
        #expect(clamped.size.height == 0)
    }

    @Test("PaintRect equality and hashing")
    func paintRectEquality() {
        let r1 = PaintRect(x: 1, y: 2, width: 3, height: 4)
        let r2 = PaintRect(x: 1, y: 2, width: 3, height: 4)
        let r3 = PaintRect(x: 0, y: 0, width: 3, height: 4)

        #expect(r1 == r2)
        #expect(r1 != r3)

        let set: Set<PaintRect> = [r1, r2, r3]
        #expect(set.count == 2)
    }

    @Test("PaintColor channel storage and byte init")
    func paintColorBasics() {
        let c1 = PaintColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        #expect(c1.red == 0.1)
        #expect(c1.green == 0.2)
        #expect(c1.blue == 0.3)
        #expect(c1.alpha == 0.4)

        let white = PaintColor.white
        #expect(white.red == 1.0)
        #expect(white.green == 1.0)
        #expect(white.blue == 1.0)
        #expect(white.alpha == 1.0)

        let black = PaintColor.black
        #expect(black.red == 0.0)
        #expect(black.green == 0.0)
        #expect(black.blue == 0.0)
        #expect(black.alpha == 1.0)

        let clear = PaintColor.clear
        #expect(clear.alpha == 0.0)

        // Byte init
        let byteColor = PaintColor(r: 255, g: 127, b: 0, a: 64)
        #expect(byteColor.red == 1.0)
        #expect(byteColor.green == Double(127) / 255.0)
        #expect(byteColor.blue == 0.0)
        #expect(byteColor.alpha == Double(64) / 255.0)
    }

    @Test("PaintColor equality and hashing")
    func paintColorEquality() {
        let c1 = PaintColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let c2 = PaintColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let c3 = PaintColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

        #expect(c1 == c2)
        #expect(c1 != c3)

        let set: Set<PaintColor> = [c1, c2, c3]
        #expect(set.count == 2)
    }
}
