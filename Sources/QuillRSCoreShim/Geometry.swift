import Foundation

public extension CGRect {
    func centeredVertically(in containerRect: CGRect) -> CGRect {
        var rect = self
        rect.origin.y = containerRect.midY - (rect.height / 2.0)
        rect = rect.integral
        rect.size = size
        return rect
    }

    func centeredHorizontally(in containerRect: CGRect) -> CGRect {
        var rect = self
        rect.origin.x = containerRect.midX - (rect.width / 2.0)
        rect = rect.integral
        rect.size = size
        return rect
    }

    func centered(in containerRect: CGRect) -> CGRect {
        centeredHorizontally(in: centeredVertically(in: containerRect))
    }
}

public extension Array where Element == CGRect {
    func maxY() -> CGFloat {
        reduce(0.0) { Swift.max($0, $1.maxY) }
    }
}
