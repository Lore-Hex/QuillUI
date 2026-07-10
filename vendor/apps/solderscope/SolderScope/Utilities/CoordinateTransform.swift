import Foundation
import CoreGraphics

/// Utility for converting between coordinate spaces
enum CoordinateTransform {
    /// Calculate the fit transform that letterboxes an image into a view
    static func fitTransform(imageSize: CGSize, viewSize: CGSize) -> CGAffineTransform {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2

        return CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
    }

    /// Calculate the scale factor for fitting an image into a view
    static func fitScale(imageSize: CGSize, viewSize: CGSize) -> CGFloat {
        min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    /// Convert a point from view coordinates to image coordinates
    static func viewToImage(
        point: CGPoint,
        imageSize: CGSize,
        viewSize: CGSize,
        zoomFactor: CGFloat = 1.0,
        panOffset: CGPoint = .zero
    ) -> CGPoint {
        let fitScale = self.fitScale(imageSize: imageSize, viewSize: viewSize)
        let fittedWidth = imageSize.width * fitScale
        let fittedHeight = imageSize.height * fitScale
        let offsetX = (viewSize.width - fittedWidth) / 2
        let offsetY = (viewSize.height - fittedHeight) / 2

        // Remove pan, zoom, and fit transforms in reverse order
        let centered = CGPoint(
            x: point.x - viewSize.width / 2 - panOffset.x,
            y: point.y - viewSize.height / 2 - panOffset.y
        )

        let unzoomed = CGPoint(
            x: centered.x / zoomFactor,
            y: centered.y / zoomFactor
        )

        let imagePoint = CGPoint(
            x: unzoomed.x + imageSize.width / 2,
            y: unzoomed.y + imageSize.height / 2
        )

        return imagePoint
    }

    /// Convert a point from image coordinates to view coordinates
    static func imageToView(
        point: CGPoint,
        imageSize: CGSize,
        viewSize: CGSize,
        zoomFactor: CGFloat = 1.0,
        panOffset: CGPoint = .zero
    ) -> CGPoint {
        // Center in image space
        let centered = CGPoint(
            x: point.x - imageSize.width / 2,
            y: point.y - imageSize.height / 2
        )

        // Apply zoom
        let zoomed = CGPoint(
            x: centered.x * zoomFactor,
            y: centered.y * zoomFactor
        )

        // Apply pan and center in view
        let viewPoint = CGPoint(
            x: zoomed.x + viewSize.width / 2 + panOffset.x,
            y: zoomed.y + viewSize.height / 2 + panOffset.y
        )

        return viewPoint
    }

    /// Calculate the distance between two points in image space
    static func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Calculate the angle between two points (in radians)
    static func angle(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        atan2(p2.y - p1.y, p2.x - p1.x)
    }

    /// Calculate the midpoint between two points
    static func midpoint(of p1: CGPoint, and p2: CGPoint) -> CGPoint {
        CGPoint(
            x: (p1.x + p2.x) / 2,
            y: (p1.y + p2.y) / 2
        )
    }

    /// Clamp a point to be within a given rect
    static func clamp(point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }
}
