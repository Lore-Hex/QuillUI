//
// QuillUI Linux shim for `QuartzCore`.
//
// SignalServiceKit uses QuartzCore mostly for monotonic timing
// (CACurrentMediaTime, in benchmarks / batch pacing) and, in two places, a
// CADisplayLink and a CAGradientLayer. CACurrentMediaTime is implemented
// faithfully via ProcessInfo.systemUptime (a monotonic clock, available on
// Linux); the layer/display-link types are inert (no rendering or frame
// callbacks on Linux). CGRect/CGPoint/CGContext come from QuillFoundation.
//
import Foundation
import CoreFoundation
import QuillFoundation

// MARK: - CACurrentMediaTime
//
// Real QuartzCore returns mach_absolute_time converted to seconds -- a monotonic
// clock. ProcessInfo.systemUptime is the equivalent monotonic source on Linux,
// so SSK's elapsed-time measurements are accurate (not stubbed).

public func CACurrentMediaTime() -> CFTimeInterval {
    ProcessInfo.processInfo.systemUptime
}

// MARK: - CALayer / CAGradientLayer
//
// Inert layer types. AvatarBuilder builds a gradient layer and renders it into
// a graphics context; on Linux render(in:) is a no-op (the avatar gradient is
// not painted until a real layer compositor is bridged).

open class CALayer: NSObject {
    public var frame: CGRect = .zero
    public var bounds: CGRect = .zero
    public var contentsScale: CGFloat = 1

    public override init() { super.init() }

    // `ctx` is untyped: CGContext is not yet provided by the CoreGraphics shim,
    // and render is inert anyway (no compositor on Linux). When a CGContext
    // type lands this can be tightened to `render(in ctx: CGContext)`.
    open func render(in ctx: Any) {}
}

public final class CAGradientLayer: CALayer {
    public var colors: [Any]?
    public var locations: [NSNumber]?
    public var startPoint: CGPoint = CGPoint(x: 0.5, y: 0.0)
    public var endPoint: CGPoint = CGPoint(x: 0.5, y: 1.0)
}

// MARK: - CADisplayLink
//
// Inert: no frame callbacks fire on Linux. `selector` is untyped (Any) so it
// accepts the same-module Selector token SSK passes without depending on it.

public final class CADisplayLink {
    public var isPaused: Bool = false
    public var preferredFramesPerSecond: Int = 0
    public var timestamp: CFTimeInterval = 0
    public var duration: CFTimeInterval = 0

    public init(target: Any, selector: Any) {}

    public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    public func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    public func invalidate() {}
}
