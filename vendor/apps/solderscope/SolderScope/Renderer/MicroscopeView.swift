import SwiftUI
import CoreImage
import Combine

struct MicroscopeView: NSViewRepresentable {
    let captureManager: CaptureManager
    @Binding var transform: ViewTransform
    let isFrozen: Bool

    func makeNSView(context: Context) -> MicroscopeNSView {
        let view = MicroscopeNSView()
        view.delegate = context.coordinator
        view.captureManager = captureManager
        return view
    }

    func updateNSView(_ nsView: MicroscopeNSView, context: Context) {
        nsView.transform = transform
        nsView.isFrozen = isFrozen
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: MicroscopeNSViewDelegate {
        let parent: MicroscopeView

        init(_ parent: MicroscopeView) {
            self.parent = parent
        }

        func microscopeView(_ view: MicroscopeNSView, didZoom factor: CGFloat, at point: CGPoint) {
            guard let imageSize = view.imageSize else { return }
            parent.transform.zoom(
                by: factor,
                around: point,
                imageSize: imageSize,
                viewSize: view.bounds.size
            )
        }

        func microscopeView(_ view: MicroscopeNSView, didPan delta: CGPoint) {
            parent.transform.pan(by: delta)
        }

        func microscopeViewDidDoubleClick(_ view: MicroscopeNSView) {
            parent.transform.reset()
        }
    }
}

// MARK: - Delegate Protocol

protocol MicroscopeNSViewDelegate: AnyObject {
    func microscopeView(_ view: MicroscopeNSView, didZoom factor: CGFloat, at point: CGPoint)
    func microscopeView(_ view: MicroscopeNSView, didPan delta: CGPoint)
    func microscopeViewDidDoubleClick(_ view: MicroscopeNSView)
}

// MARK: - NSView Implementation

class MicroscopeNSView: NSView {
    weak var delegate: MicroscopeNSViewDelegate?

    var transform: ViewTransform = ViewTransform() {
        didSet { needsDisplay = true }
    }

    var isFrozen: Bool = false {
        didSet {
            if isFrozen && frozenFrame == nil {
                frozenFrame = currentFrame
            } else if !isFrozen {
                frozenFrame = nil
            }
        }
    }

    weak var captureManager: CaptureManager? {
        didSet {
            setupFrameSubscription()
        }
    }

    private var currentFrame: CIImage?
    private var frozenFrame: CIImage?
    private var ciContext: CIContext?
    private var frameSubscription: AnyCancellable?

    private var isDragging: Bool = false
    private var lastDragPoint: CGPoint = .zero

    var imageSize: CGSize? {
        (isFrozen ? frozenFrame : currentFrame)?.extent.size
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Create CI context for rendering
        ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])

        // Enable mouse tracking
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    private func setupFrameSubscription() {
        frameSubscription?.cancel()

        guard let manager = captureManager else { return }

        frameSubscription = manager.$latestFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self = self, !self.isFrozen, let frame = frame else { return }
                self.currentFrame = frame
                self.needsDisplay = true
            }
    }

    func setFrame(_ image: CIImage) {
        if isFrozen {
            if frozenFrame == nil {
                frozenFrame = image
            }
        } else {
            currentFrame = image
            frozenFrame = nil
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let ciContext = ciContext else { return }

        // Fill background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        // Get the frame to display
        let frameToDisplay = isFrozen ? frozenFrame : currentFrame
        guard let ciImage = frameToDisplay else { return }

        // Convert CIImage to CGImage for reliable rendering
        let imageExtent = ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: imageExtent) else { return }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        guard imageWidth > 0 && imageHeight > 0 else { return }

        // Calculate fit scale (letterbox)
        let fitScale = min(bounds.width / imageWidth, bounds.height / imageHeight)
        let scaledWidth = imageWidth * fitScale
        let scaledHeight = imageHeight * fitScale

        // Center the image
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2

        // Apply user transforms to context
        context.saveGState()

        // Move to center of view
        context.translateBy(x: bounds.width / 2, y: bounds.height / 2)

        // Apply user pan
        context.translateBy(x: transform.panOffset.x, y: transform.panOffset.y)

        // Apply user zoom
        context.scaleBy(x: transform.zoomFactor, y: transform.zoomFactor)

        // Apply rotation
        context.rotate(by: transform.rotation.radians)

        // Apply flips
        let flipX: CGFloat = transform.isFlippedHorizontally ? -1 : 1
        let flipY: CGFloat = transform.isFlippedVertically ? -1 : 1
        context.scaleBy(x: flipX, y: flipY)

        // Move back from center
        context.translateBy(x: -bounds.width / 2, y: -bounds.height / 2)

        // Calculate destination rect for the image
        let destRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)

        // Draw the CGImage
        context.draw(cgImage, in: destRect)

        context.restoreGState()
    }

    // MARK: - Mouse Events

    override func scrollWheel(with event: NSEvent) {
        let zoomFactor: CGFloat
        if event.hasPreciseScrollingDeltas {
            // Trackpad - use smaller increments
            zoomFactor = 1.0 + event.scrollingDeltaY * 0.01
        } else {
            // Mouse wheel
            zoomFactor = event.scrollingDeltaY > 0 ? 1.1 : 0.9
        }

        let location = convert(event.locationInWindow, from: nil)
        delegate?.microscopeView(self, didZoom: zoomFactor, at: location)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            delegate?.microscopeViewDidDoubleClick(self)
        } else {
            isDragging = true
            lastDragPoint = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(
            x: currentPoint.x - lastDragPoint.x,
            y: currentPoint.y - lastDragPoint.y
        )

        delegate?.microscopeView(self, didPan: delta)
        lastDragPoint = currentPoint
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            NSCursor.pop()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isDragging {
            NSCursor.closedHand.set()
        } else {
            NSCursor.openHand.set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Let the app handle keyboard shortcuts
        super.keyDown(with: event)
    }
}
