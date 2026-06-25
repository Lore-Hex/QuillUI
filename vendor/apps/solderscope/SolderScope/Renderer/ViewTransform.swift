import Foundation
import CoreGraphics

struct ViewTransform: Equatable {
    var zoomFactor: CGFloat = 1.0
    var panOffset: CGPoint = .zero
    var rotation: Rotation = .none
    var isFlippedHorizontally: Bool = false
    var isFlippedVertically: Bool = false

    // Zoom limits
    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 20.0

    // MARK: - Transform Application

    func applying(to imageSize: CGSize, in viewSize: CGSize) -> CGAffineTransform {
        // Calculate base fit transform (letterbox)
        let fitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)

        // Center offset for letterboxing
        let fittedWidth = imageSize.width * fitScale
        let fittedHeight = imageSize.height * fitScale
        let centerX = (viewSize.width - fittedWidth) / 2
        let centerY = (viewSize.height - fittedHeight) / 2

        var transform = CGAffineTransform.identity

        // Translate to view center
        transform = transform.translatedBy(x: viewSize.width / 2, y: viewSize.height / 2)

        // Apply user pan
        transform = transform.translatedBy(x: panOffset.x, y: panOffset.y)

        // Apply user zoom
        transform = transform.scaledBy(x: zoomFactor, y: zoomFactor)

        // Apply rotation
        transform = transform.rotated(by: rotation.radians)

        // Apply flips
        let flipX: CGFloat = isFlippedHorizontally ? -1 : 1
        let flipY: CGFloat = isFlippedVertically ? -1 : 1
        transform = transform.scaledBy(x: flipX, y: flipY)

        // Translate back and apply base fit
        transform = transform.translatedBy(x: -imageSize.width / 2, y: -imageSize.height / 2)
        transform = transform.scaledBy(x: fitScale, y: fitScale)

        return transform
    }

    func fitTransform(imageSize: CGSize, viewSize: CGSize) -> CGAffineTransform {
        let fitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * fitScale) / 2
        let offsetY = (viewSize.height - imageSize.height * fitScale) / 2

        return CGAffineTransform(scaleX: fitScale, y: fitScale)
            .translatedBy(x: offsetX / fitScale, y: offsetY / fitScale)
    }

    // MARK: - Coordinate Conversion

    func viewToImage(point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
        let transform = applying(to: imageSize, in: viewSize)
        let inverse = transform.inverted()
        return point.applying(inverse)
    }

    func imageToView(point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
        let transform = applying(to: imageSize, in: viewSize)
        return point.applying(transform)
    }

    // MARK: - Zoom

    mutating func zoom(by factor: CGFloat, around viewPoint: CGPoint, imageSize: CGSize, viewSize: CGSize) {
        let oldZoom = zoomFactor
        let newZoom = (zoomFactor * factor).clamped(to: Self.minZoom...Self.maxZoom)

        if newZoom == oldZoom { return }

        // Get image point under cursor before zoom
        let imagePoint = viewToImage(point: viewPoint, imageSize: imageSize, viewSize: viewSize)

        // Apply zoom
        zoomFactor = newZoom

        // Get new view position of that image point
        let newViewPoint = imageToView(point: imagePoint, imageSize: imageSize, viewSize: viewSize)

        // Adjust pan to keep image point under cursor
        panOffset.x += viewPoint.x - newViewPoint.x
        panOffset.y += viewPoint.y - newViewPoint.y
    }

    // MARK: - Pan

    mutating func pan(by delta: CGPoint) {
        panOffset.x += delta.x
        panOffset.y += delta.y
    }

    // MARK: - Reset

    mutating func reset() {
        zoomFactor = 1.0
        panOffset = .zero
    }

    mutating func resetAll() {
        zoomFactor = 1.0
        panOffset = .zero
        rotation = .none
        isFlippedHorizontally = false
        isFlippedVertically = false
    }

    // MARK: - Rotation

    mutating func rotateClockwise() {
        rotation = rotation.next
    }

    mutating func rotateCounterclockwise() {
        rotation = rotation.previous
    }

    mutating func toggleHorizontalFlip() {
        isFlippedHorizontally.toggle()
    }

    mutating func toggleVerticalFlip() {
        isFlippedVertically.toggle()
    }
}

// MARK: - Rotation Enum

enum Rotation: Int, CaseIterable, Codable {
    case none = 0
    case clockwise90 = 90
    case clockwise180 = 180
    case clockwise270 = 270

    var radians: CGFloat {
        CGFloat(rawValue) * .pi / 180
    }

    var next: Rotation {
        switch self {
        case .none: return .clockwise90
        case .clockwise90: return .clockwise180
        case .clockwise180: return .clockwise270
        case .clockwise270: return .none
        }
    }

    var previous: Rotation {
        switch self {
        case .none: return .clockwise270
        case .clockwise90: return .none
        case .clockwise180: return .clockwise90
        case .clockwise270: return .clockwise180
        }
    }
}

// MARK: - CGFloat Extension

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
