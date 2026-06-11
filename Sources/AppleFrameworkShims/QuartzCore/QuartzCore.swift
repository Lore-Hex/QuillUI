//
// QuillUI Linux shim for `QuartzCore` — module umbrella.
//
// The functional implementation lives in the sibling files:
//   CALayer.swift           — CAMediaTiming, CALayer model, delegate, actions
//   CALayerSubclasses.swift — CAShapeLayer/CAGradientLayer/CATextLayer/
//                             CAEmitterLayer/CAReplicatorLayer/CAScrollLayer/
//                             CAMetalLayer
//   CATransform3D.swift     — faithful 4×4 transform math + NSValue boxing
//   CAAnimation.swift       — animation classes, CATransaction, and the async
//                             timing engine (completion callbacks fire on
//                             DispatchQueue.main after the effective duration)
//   CADisplayLink.swift     — a display link that really ticks (DispatchSource
//                             timer on the main queue)
//
// This shim is a faithful MODEL + TIMING layer; there is no compositor or
// pixel rendering on Linux yet (that arrives later via QuillPaint).
// CGRect/CGPoint/CGColor/CGPath/CGContext come from QuillFoundation.
//
import Foundation
// Plain import: re-exporting all of corelibs CoreFoundation leaks its stub
// CFString/CFArray classes into every `import Cocoa` scope and collides with
// the bridged CF typealiases there (e.g. ServiceManagement.CFString). Only
// the CF names this shim's API surface needs are re-exported below.
import CoreFoundation
@_exported import Metal
@_exported import QuillFoundation

public typealias CFTimeInterval = CoreFoundation.CFTimeInterval
