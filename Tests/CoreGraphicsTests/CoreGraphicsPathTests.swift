import CoreGraphics
import Testing

struct CoreGraphicsPathTests {
    @Test("CGPath rect constructors apply the supplied affine transform")
    func rectConstructorAppliesTransform() {
        var transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 5, ty: -7)
        let path = CGPath(rect: CGRect(x: 1, y: 2, width: 3, height: 4), transform: &transform)

        #expect(path.quillElements == [
            PathElementSnapshot(type: .moveToPoint, points: [CGPoint(x: 7, y: -1)]),
            PathElementSnapshot(type: .addLineToPoint, points: [CGPoint(x: 13, y: -1)]),
            PathElementSnapshot(type: .addLineToPoint, points: [CGPoint(x: 13, y: 11)]),
            PathElementSnapshot(type: .addLineToPoint, points: [CGPoint(x: 7, y: 11)]),
            PathElementSnapshot(type: .closeSubpath, points: []),
        ])
    }

    @Test("CGMutablePath addPath(transform:) transforms every imported element point")
    func mutablePathAddPathAppliesTransform() {
        let source = CGMutablePath()
        source.move(to: CGPoint(x: 0, y: 0))
        source.addLine(to: CGPoint(x: 2, y: 0))
        source.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 3, y: 1))

        let destination = CGMutablePath()
        destination.addPath(source, transform: CGAffineTransform(translationX: 10, y: 20))

        #expect(destination.quillElements == [
            PathElementSnapshot(type: .moveToPoint, points: [CGPoint(x: 10, y: 20)]),
            PathElementSnapshot(type: .addLineToPoint, points: [CGPoint(x: 12, y: 20)]),
            PathElementSnapshot(type: .addQuadCurveToPoint, points: [
                CGPoint(x: 13, y: 21),
                CGPoint(x: 14, y: 20),
            ]),
        ])
    }

    @Test("CGPath copy(using:) returns a transformed copy without mutating the source")
    func copyUsingTransformDoesNotMutateSource() throws {
        let source = CGMutablePath()
        source.move(to: CGPoint(x: 1, y: 1))
        source.addCurve(
            to: CGPoint(x: 4, y: 1),
            control1: CGPoint(x: 2, y: 3),
            control2: CGPoint(x: 3, y: 3)
        )

        var transform = CGAffineTransform(translationX: -1, y: 2)
        let copy = try #require(source.copy(using: &transform))

        #expect(source.quillElements == [
            PathElementSnapshot(type: .moveToPoint, points: [CGPoint(x: 1, y: 1)]),
            PathElementSnapshot(type: .addCurveToPoint, points: [
                CGPoint(x: 2, y: 3),
                CGPoint(x: 3, y: 3),
                CGPoint(x: 4, y: 1),
            ]),
        ])
        #expect(copy.quillElements == [
            PathElementSnapshot(type: .moveToPoint, points: [CGPoint(x: 0, y: 3)]),
            PathElementSnapshot(type: .addCurveToPoint, points: [
                CGPoint(x: 1, y: 5),
                CGPoint(x: 2, y: 5),
                CGPoint(x: 3, y: 3),
            ]),
        ])
    }

    @Test("CGPath roundedRect records cubic corner curves")
    func roundedRectRecordsCubicCorners() {
        let path = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: 10, height: 8),
            cornerWidth: 2,
            cornerHeight: 3,
            transform: nil
        )

        #expect(path.quillElements.map(\.type) == [
            .moveToPoint,
            .addLineToPoint,
            .addCurveToPoint,
            .addLineToPoint,
            .addCurveToPoint,
            .addLineToPoint,
            .addCurveToPoint,
            .addLineToPoint,
            .addCurveToPoint,
            .closeSubpath,
        ])
        #expect(path.quillElements.filter { $0.type == .addCurveToPoint }.allSatisfy { $0.points.count == 3 })
    }

    @Test("CGMutablePath addEllipse records a closed cubic path")
    func ellipseRecordsClosedCubicPath() {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 2, y: 4, width: 6, height: 10))

        #expect(path.quillElements.map(\.type) == [
            .moveToPoint,
            .addCurveToPoint,
            .addCurveToPoint,
            .addCurveToPoint,
            .addCurveToPoint,
            .closeSubpath,
        ])
        #expect(path.quillElements.first?.points == [CGPoint(x: 5, y: 4)])
        #expect(path.quillElements.dropFirst().prefix(4).allSatisfy { $0.points.count == 3 })
    }
}

private struct PathElementSnapshot: Equatable {
    var type: CGPathElementType
    var points: [CGPoint]
}

private extension CGPath {
    var quillElements: [PathElementSnapshot] {
        var snapshots: [PathElementSnapshot] = []
        applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = (0..<element.type.quillPointCount).map { element.points[$0] }
            snapshots.append(PathElementSnapshot(type: element.type, points: points))
        }
        return snapshots
    }
}

private extension CGPathElementType {
    var quillPointCount: Int {
        switch self {
        case .moveToPoint, .addLineToPoint:
            return 1
        case .addQuadCurveToPoint:
            return 2
        case .addCurveToPoint:
            return 3
        case .closeSubpath:
            return 0
        @unknown default:
            return 0
        }
    }
}
