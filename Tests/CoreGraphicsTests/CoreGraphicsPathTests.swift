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

    @Test("CGAffineTransform applies scale, rotation, and composition to CGRect")
    func affineTransformAppliesToCGRect() {
        #expect(CGRect(x: 1, y: 2, width: 3, height: 4).applying(
            CGAffineTransform(scaleX: 2, y: 3)
        ) == CGRect(x: 2, y: 6, width: 6, height: 12))

        #expect(CGRect(x: 1, y: 2, width: 3, height: 4).applying(
            CGAffineTransform(translationX: 10, y: 20)
        ) == CGRect(x: 11, y: 22, width: 3, height: 4))

        let rotated = CGRect(x: 0, y: 0, width: 2, height: 1).applying(
            CGAffineTransform(rotationAngle: .pi / 2)
        )
        #expect(rotated.isClose(to: CGRect(x: -1, y: 0, width: 1, height: 2)))

        let point = CGPoint(x: 1, y: 1)
        let translateThenScale = CGAffineTransform(translationX: 10, y: 20)
            .concatenating(CGAffineTransform(scaleX: 2, y: 3))
        #expect(point.applying(translateThenScale) == CGPoint(x: 22, y: 63))
        #expect(point.applying(CGAffineTransform(translationX: 10, y: 20).scaledBy(x: 2, y: 3)) == CGPoint(x: 12, y: 23))
        #expect(point.applying(CGAffineTransform(scaleX: 2, y: 3).translatedBy(x: 10, y: 20)) == CGPoint(x: 22, y: 63))
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

    @Test("CGPath ellipse constructor applies the supplied affine transform")
    func ellipseConstructorAppliesTransform() {
        var transform = CGAffineTransform(translationX: 10, y: -2)
        let path = CGPath(ellipseIn: CGRect(x: 2, y: 4, width: 6, height: 10), transform: &transform)

        #expect(path.quillElements.map(\.type) == [
            .moveToPoint,
            .addCurveToPoint,
            .addCurveToPoint,
            .addCurveToPoint,
            .addCurveToPoint,
            .closeSubpath,
        ])
        #expect(path.quillElements.first?.points == [CGPoint(x: 15, y: 2)])
        #expect(path.boundingBox == CGRect(x: 12, y: 2, width: 6, height: 10))
    }

    @Test("CGMutablePath addArc records cubic arc segments")
    func addArcRecordsCubicSegments() {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 2, startAngle: 0, endAngle: .pi / 2, clockwise: false)

        let elements = path.quillElements
        #expect(elements.map(\.type) == [.moveToPoint, .addCurveToPoint])
        #expect(elements[0].points[0].isClose(to: CGPoint(x: 2, y: 0)))
        #expect(elements[1].points[2].isClose(to: CGPoint(x: 0, y: 2)))
        #expect(path.currentPoint.isClose(to: CGPoint(x: 0, y: 2)))
        #expect(abs(path.boundingBoxOfPath.width - 2) < 0.0001)
        #expect(abs(path.boundingBoxOfPath.height - 2) < 0.0001)

        let connected = CGMutablePath()
        connected.move(to: CGPoint(x: -1, y: 0))
        connected.addArc(center: .zero, radius: 2, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        #expect(connected.quillElements.map(\.type) == [.moveToPoint, .addLineToPoint, .addCurveToPoint])
        #expect(connected.quillElements[1].points[0].isClose(to: CGPoint(x: 2, y: 0)))
    }

    @Test("CGMutablePath tangent arcs join two line directions")
    func addTangentArcRecordsLineAndArc() {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addArc(
            tangent1End: CGPoint(x: 10, y: 0),
            tangent2End: CGPoint(x: 10, y: 10),
            radius: 2
        )

        let elements = path.quillElements
        #expect(elements.map(\.type) == [.moveToPoint, .addLineToPoint, .addCurveToPoint])
        #expect(elements[1].points[0].isClose(to: CGPoint(x: 8, y: 0)))
        #expect(elements[2].points[2].isClose(to: CGPoint(x: 10, y: 2)))
        #expect(path.currentPoint.isClose(to: CGPoint(x: 10, y: 2)))
        #expect(abs(path.boundingBoxOfPath.maxX - 10) < 0.0001)
        #expect(abs(path.boundingBoxOfPath.maxY - 2) < 0.0001)
    }

    @Test("CGPath exposes emptiness, current point, and point bounds")
    func pathAccessorsReflectRecordedElements() {
        let empty = CGMutablePath()
        #expect(empty.isEmpty)
        #expect(empty.currentPoint == .zero)
        #expect(empty.boundingBox.isNull)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: 2))
        path.addCurve(
            to: CGPoint(x: 7, y: 3),
            control1: CGPoint(x: 4, y: -2),
            control2: CGPoint(x: 5, y: 9)
        )

        #expect(!path.isEmpty)
        #expect(path.currentPoint == CGPoint(x: 7, y: 3))
        #expect(path.boundingBox == CGRect(x: 1, y: -2, width: 6, height: 11))
        #expect(path.boundingBoxOfPath.minX >= 1)
        #expect(path.boundingBoxOfPath.maxX <= 7)

        let closed = CGMutablePath()
        closed.addRect(CGRect(x: 3, y: 4, width: 10, height: 8))
        #expect(closed.currentPoint == CGPoint(x: 3, y: 4))
    }

    @Test("CGPath C callback apply enumerates path elements with caller info")
    func pathApplyCFunctionEnumeratesElements() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: 2))
        path.addLine(to: CGPoint(x: 3, y: 4))
        path.closeSubpath()

        var snapshots: [PathElementSnapshot] = []
        withUnsafeMutablePointer(to: &snapshots) { snapshotsPointer in
            path.apply(info: UnsafeMutableRawPointer(snapshotsPointer)) { info, elementPointer in
                guard let info else { return }
                let snapshots = info.assumingMemoryBound(to: [PathElementSnapshot].self)
                let element = elementPointer.pointee
                let points = (0..<element.type.quillPointCount).map { element.points[$0] }
                snapshots.pointee.append(PathElementSnapshot(type: element.type, points: points))
            }
        }

        #expect(snapshots == [
            PathElementSnapshot(type: .moveToPoint, points: [CGPoint(x: 1, y: 2)]),
            PathElementSnapshot(type: .addLineToPoint, points: [CGPoint(x: 3, y: 4)]),
            PathElementSnapshot(type: .closeSubpath, points: []),
        ])
    }

    @Test("CGPath path bounds use curve extrema instead of control-point bounds")
    func pathBoundingBoxOfPathUsesCurveExtrema() {
        let quadratic = CGMutablePath()
        quadratic.move(to: CGPoint(x: 0, y: 0))
        quadratic.addQuadCurve(to: CGPoint(x: 20, y: 0), control: CGPoint(x: 10, y: 10))
        #expect(quadratic.boundingBox == CGRect(x: 0, y: 0, width: 20, height: 10))
        #expect(abs(quadratic.boundingBoxOfPath.height - 5) < 0.0001)

        let cubic = CGMutablePath()
        cubic.move(to: CGPoint(x: 0, y: 0))
        cubic.addCurve(
            to: CGPoint(x: 3, y: 0),
            control1: CGPoint(x: 0, y: 3),
            control2: CGPoint(x: 3, y: 3)
        )
        #expect(cubic.boundingBox == CGRect(x: 0, y: 0, width: 3, height: 3))
        #expect(abs(cubic.boundingBoxOfPath.height - 2.25) < 0.0001)
    }

    @Test("CGPath contains supports rects, transforms, and even-odd holes")
    func pathContainsUsesFillRulesAndTransforms() {
        let rect = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 8), transform: nil)
        #expect(rect.contains(CGPoint(x: 5, y: 4)))
        #expect(rect.contains(CGPoint(x: 0, y: 4)))
        #expect(!rect.contains(CGPoint(x: 12, y: 4)))

        let transformed = CGMutablePath()
        transformed.addRect(CGRect(x: 0, y: 0, width: 10, height: 8))
        #expect(transformed.contains(
            CGPoint(x: 15, y: 24),
            using: .winding,
            transform: CGAffineTransform(translationX: 10, y: 20)
        ))
        #expect(!transformed.contains(
            CGPoint(x: 5, y: 4),
            using: .winding,
            transform: CGAffineTransform(translationX: 10, y: 20)
        ))

        let donut = CGMutablePath()
        donut.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        donut.addRect(CGRect(x: 3, y: 3, width: 4, height: 4))
        #expect(donut.contains(CGPoint(x: 5, y: 5), using: .winding))
        #expect(!donut.contains(CGPoint(x: 5, y: 5), using: .evenOdd))
        #expect(donut.contains(CGPoint(x: 1, y: 1), using: .evenOdd))
        #expect(donut.contains(CGPoint(x: 3, y: 5), using: .evenOdd))
    }

    @Test("CGPath contains flattens cubic ellipse paths")
    func pathContainsFlattenedEllipse() {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 2, y: 4, width: 6, height: 10))

        #expect(path.contains(CGPoint(x: 5, y: 9)))
        #expect(!path.contains(CGPoint(x: 5, y: 2)))
    }

    #if os(Linux)
    @Test("CGImage cropping preserves BGRA pixel backing")
    func imageCroppingPreservesPixelBacking() throws {
        let image = CGImage()
        image.width = 3
        image.height = 2
        image.quillBytesPerRow = 12
        image.quillBGRAPixels = [
            1, 2, 3, 255, 4, 5, 6, 255, 7, 8, 9, 255,
            10, 11, 12, 255, 13, 14, 15, 255, 16, 17, 18, 255,
        ]

        let cropped = try #require(image.cropping(to: CGRect(x: 1, y: 0, width: 2, height: 2)))
        #expect(cropped.width == 2)
        #expect(cropped.height == 2)
        #expect(cropped.quillBytesPerRow == 8)
        #expect(cropped.quillBGRAPixels == [
            4, 5, 6, 255, 7, 8, 9, 255,
            13, 14, 15, 255, 16, 17, 18, 255,
        ])
        #expect(image.cropping(to: CGRect(x: 4, y: 0, width: 1, height: 1)) == nil)

        let blank = CGImage()
        blank.width = 4
        blank.height = 3
        let blankCrop = try #require(blank.cropping(to: CGRect(x: 1.2, y: 0.2, width: 1.4, height: 1.4)))
        #expect(blankCrop.width == 2)
        #expect(blankCrop.height == 2)
        #expect(blankCrop.quillBytesPerRow == 8)
        #expect(blankCrop.quillBGRAPixels == nil)

        let padded = CGImage()
        padded.width = 2
        padded.height = 2
        padded.quillBytesPerRow = 12
        padded.quillBGRAPixels = [
            1, 2, 3, 255, 4, 5, 6, 255, 90, 91, 92, 93,
            7, 8, 9, 255, 10, 11, 12, 255, 94, 95, 96, 97,
        ]
        let paddedCrop = try #require(padded.cropping(to: CGRect(x: 0, y: 1, width: 2, height: 1)))
        #expect(paddedCrop.width == 2)
        #expect(paddedCrop.height == 1)
        #expect(paddedCrop.quillBytesPerRow == 8)
        #expect(paddedCrop.quillBGRAPixels == [
            7, 8, 9, 255, 10, 11, 12, 255,
        ])

        let corrupt = CGImage()
        corrupt.width = 2
        corrupt.height = 2
        corrupt.quillBytesPerRow = 8
        corrupt.quillBGRAPixels = [1, 2, 3, 255]
        #expect(corrupt.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)

        let shortStride = CGImage()
        shortStride.width = 3
        shortStride.height = 1
        shortStride.quillBytesPerRow = 8
        shortStride.quillBGRAPixels = Array(repeating: 0, count: 12)
        #expect(shortStride.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
    }
    #endif

    @Test("CGContext tracks current path without a backend")
    func contextTracksCurrentPathWithoutBackend() throws {
        let context = CGContext()
        #expect(context.isPathEmpty)
        #expect(context.currentPointOfPath == .zero)
        #expect(context.copyPath() == nil)

        context.move(to: CGPoint(x: 0, y: 0))
        context.addLine(to: CGPoint(x: 2, y: 0))
        context.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 3, y: 1))
        context.addCurve(
            to: CGPoint(x: 8, y: 0),
            control1: CGPoint(x: 5, y: 2),
            control2: CGPoint(x: 7, y: 2)
        )

        #expect(!context.isPathEmpty)
        #expect(context.currentPointOfPath == CGPoint(x: 8, y: 0))
        #expect(context.pathBoundingBox.minX == 0)
        #expect(context.pathBoundingBox.maxX == 8)

        let copy = try #require(context.copyPath())
        #expect(copy.quillElements.map(\.type) == [
            .moveToPoint,
            .addLineToPoint,
            .addQuadCurveToPoint,
            .addCurveToPoint,
        ])

        context.strokePath()
        #expect(context.isPathEmpty)
        #expect(context.copyPath() == nil)

        context.addRect(CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(!context.isPathEmpty)
        context.clip(using: .evenOdd)
        #expect(context.isPathEmpty)

        context.move(to: .zero)
        context.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 2)
        #expect(context.copyPath()?.quillElements.map(\.type) == [
            .moveToPoint,
            .addLineToPoint,
            .addCurveToPoint,
        ])
    }
}

private struct PathElementSnapshot: Equatable {
    var type: CGPathElementType
    var points: [CGPoint]
}

private extension CGPoint {
    func isClose(to other: CGPoint, tolerance: CGFloat = 0.0001) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

private extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 0.0001) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
            abs(origin.y - other.origin.y) <= tolerance &&
            abs(size.width - other.size.width) <= tolerance &&
            abs(size.height - other.size.height) <= tolerance
    }
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
