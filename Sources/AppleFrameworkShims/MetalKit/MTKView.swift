//
//  MTKView.swift
//  MetalKit shim — QuillUI Apple-framework reimplementation for Linux
//
//  MTKView + MTKViewDelegate: the MetalKit view family Signal-iOS touches.
//  Consumers in the upstream tree:
//    - SignalUI/Views/BodyRanges/SpoilerRendering/SpoilerParticleView.swift
//      (subclasses MTKView; uses init(frame:device:), required init(coder:),
//      framebufferOnly, preferredFramesPerSecond, isPaused, drawableSize,
//      currentDrawable, layer.isOpaque/shouldRasterize, setNeedsDisplay()).
//    - Signal/Calls/UserInterface/RemoteVideoView.swift (`subview is MTKView`).
//
//  MODEL HONESTY: there is no Metal device, swap chain, or display link on
//  Linux, so this view never renders and never schedules frames. The API
//  shape matches Apple's MetalKit; `currentDrawable` and
//  `currentRenderPassDescriptor` return nil — the same signal Apple's MTKView
//  gives when no drawable is available — so upstream draw loops (e.g.
//  SpoilerParticleView.draw(_:)) hit their guard-and-return paths and the
//  view is inert rather than wrong.
//

import Foundation
import Metal
import QuartzCore
import QuillFoundation
import QuillUIKit

@MainActor
open class MTKView: UIView {

    /// Apple shape: MTKView is hosted on a CAMetalLayer.
    open override class var layerClass: AnyClass { CAMetalLayer.self }

    open var device: MTLDevice?
    open weak var delegate: (any MTKViewDelegate)?

    open var framebufferOnly: Bool = true
    /// MODEL HONESTY: recorded state only — no display link drives this view
    /// on Linux, so changing the rate never schedules anything.
    open var preferredFramesPerSecond: Int = 60
    /// MODEL HONESTY: recorded state only (SpoilerParticleView toggles this
    /// constantly); there is no internal redraw loop to pause.
    open var isPaused: Bool = false
    open var enableSetNeedsDisplay: Bool = false
    open var autoResizeDrawable: Bool = true
    open var presentsWithTransaction: Bool = false

    open var drawableSize: CGSize = .zero
    open var colorPixelFormat: MTLPixelFormat = .bgra8Unorm
    open var depthStencilPixelFormat: MTLPixelFormat = .invalid
    open var sampleCount: Int = 1
    open var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    open var clearDepth: Double = 1.0
    open var clearStencil: UInt32 = 0

    /// MODEL HONESTY: nil — no CAMetalLayer swap chain exists on Linux.
    /// Apple's MTKView also returns nil when a drawable is unavailable, and
    /// upstream render loops guard on it, so rendering becomes a no-op.
    open var currentDrawable: (any CAMetalDrawable)? { nil }
    open var currentRenderPassDescriptor: MTLRenderPassDescriptor? { nil }
    open var preferredDevice: (any MTLDevice)? { device }

    public init(frame frameRect: CGRect, device: MTLDevice?) {
        self.device = device
        super.init(frame: frameRect)
    }

    // Apple's MTKView declares a NON-failable required init(coder:) —
    // SpoilerParticleView overrides exactly this shape
    // (`required init(coder: NSCoder)`, no `?`).
    public required init(coder: NSCoder) {
        self.device = nil
        super.init(frame: .zero)
    }

    /// Manually triggers one frame, Apple-style: the delegate draw path wins;
    /// otherwise the UIView.draw(_:) subclass override point runs. Inert in
    /// practice — see MODEL HONESTY on `currentDrawable`.
    open func draw() {
        if let delegate {
            delegate.draw(in: self)
        } else {
            draw(bounds)
        }
    }

    open func releaseDrawables() {
        // MODEL HONESTY: nothing to release — no drawables exist on Linux.
    }
}

/// Apple shape. @MainActor to match the shim's UIKit posture (UIView and the
/// view that calls these methods are MainActor-isolated).
@MainActor
public protocol MTKViewDelegate: AnyObject {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    func draw(in view: MTKView)
}
