//
//  CALayerModelTests.swift
//  QuillUI — tests for the AppleFrameworkShims/QuartzCore shim (Linux)
//
//  Exercises the FUNCTIONAL MODEL layer of the QuartzCore shim:
//    - real geometry math (position/bounds/anchorPoint <-> frame)
//    - real layer hierarchy (add/insert/remove/replace, superlayer wiring)
//    - coordinate-space conversion across a layer tree (incl. scroll offsets
//      expressed via a nonzero bounds.origin)
//    - contains/hitTest
//    - maskedCorners + CACornerMask OptionSet behavior
//    - mini-KVC (setValue/value forKeyPath:) without any Objective-C runtime
//    - init(layer:) model-value copying
//    - synchronous animation bookkeeping (animationKeys/animation(forKey:))
//    - CATransform3D matrix math (second XCTestCase below)
//
//  Honest Linux semantics: there is NO pixel rendering/compositing yet
//  (that arrives later via QuillPaint), so these tests assert ONLY model
//  state and bookkeeping — never visual output.
//
//  CI-stability rules (few-core, starved runners): everything here is purely
//  synchronous. No wall-clock polling, no sleeps, no timing asserts. The only
//  animations added use a 60-second duration so nothing can complete mid-test.
//
//  Public API only — no @testable.
//

import XCTest
import QuartzCore
import Metal

// MARK: - File-private helpers

/// Component-wise floating-point comparison helpers (per CI rules, never rely
/// on exact == for derived floating-point values).
private func assertEqual(_ actual: CGPoint, _ expected: CGPoint, accuracy: CGFloat = 1e-9,
                         _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(message) [x]", file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(message) [y]", file: file, line: line)
}

private func assertEqual(_ actual: CGSize, _ expected: CGSize, accuracy: CGFloat = 1e-9,
                         _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, "\(message) [width]", file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, "\(message) [height]", file: file, line: line)
}

private func assertEqual(_ actual: CGRect, _ expected: CGRect, accuracy: CGFloat = 1e-9,
                         _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertEqual(actual.origin, expected.origin, accuracy: accuracy, "\(message) origin", file: file, line: line)
    assertEqual(actual.size, expected.size, accuracy: accuracy, "\(message) size", file: file, line: line)
}

/// Identity-based ordering snapshot for sublayer arrays.
private func ids(_ layers: [CALayer]?) -> [ObjectIdentifier] {
    (layers ?? []).map { ObjectIdentifier($0) }
}

/// Extracts a numeric scalar from a mini-KVC boxed value without assuming
/// which numeric type the implementation boxes with. There is no Objective-C
/// bridging on Linux, so `as?` casts do NOT convert between numeric types —
/// each candidate must be tried explicitly.
private func scalar(_ any: Any?) -> Double? {
    switch any {
    case let v as NSNumber: return v.doubleValue
    case let v as Double: return v
    case let v as Float: return Double(v)
    case let v as CGFloat: return Double(v)
    case let v as Int: return Double(v)
    default: return nil
    }
}

private final class LayerTestAction: CAAction, @unchecked Sendable {
    let id: String

    init(_ id: String) {
        self.id = id
    }

    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

private final class LayerActionDelegate: CALayerDelegate {
    var action: CAAction?

    init(action: CAAction?) {
        self.action = action
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        action
    }
}

private final class DefaultActionLayer: CALayer {
    private static let defaultLayerAction = LayerTestAction("default")

    override class func defaultAction(forKey event: String) -> CAAction? {
        event == "opacity" ? defaultLayerAction : nil
    }
}

private func assertAction(
    _ action: CAAction?,
    hasID expectedID: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual((action as? LayerTestAction)?.id, expectedID, file: file, line: line)
}

// MARK: - CALayer model tests

final class CALayerModelTests: XCTestCase {

    // MARK: Geometry: frame is DERIVED from position/bounds/anchorPoint

    func testFrameIsDerivedFromPositionBoundsAndAnchorPoint() {
        let layer = CALayer()
        // Default anchor point is the center.
        assertEqual(layer.anchorPoint, CGPoint(x: 0.5, y: 0.5), "default anchorPoint")

        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.position = CGPoint(x: 50, y: 25)
        assertEqual(layer.frame, CGRect(x: 0, y: 0, width: 100, height: 50),
                    "frame must derive from position/bounds/anchorPoint")
    }

    func testSettingFrameUpdatesBoundsSizeAndPosition() {
        let layer = CALayer()
        layer.frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        assertEqual(layer.bounds.size, CGSize(width: 200, height: 100), "bounds.size after frame set")
        assertEqual(layer.position, CGPoint(x: 110, y: 70), "position after frame set")
    }

    func testChangingAnchorPointMovesFrameNotPosition() {
        let layer = CALayer()
        layer.frame = CGRect(x: 10, y: 20, width: 200, height: 100)
        let positionBefore = layer.position // (110, 70) with default 0.5/0.5 anchor

        layer.anchorPoint = CGPoint(x: 0, y: 0)

        assertEqual(layer.position, positionBefore, "position must NOT move when anchorPoint changes")
        assertEqual(layer.frame, CGRect(x: 110, y: 70, width: 200, height: 100),
                    "frame MUST move when anchorPoint changes")
    }

    // MARK: Hierarchy

    func testAddSublayerSetsSuperlayer() {
        let parent = CALayer()
        let child = CALayer()
        XCTAssertNil(child.superlayer)

        parent.addSublayer(child)

        XCTAssertTrue(child.superlayer === parent)
        XCTAssertEqual(parent.sublayers?.count, 1)
        XCTAssertTrue(parent.sublayers?.first === child)
    }

    func testInsertSublayerOrdering() {
        let parent = CALayer()
        let a = CALayer()
        let b = CALayer()
        let c = CALayer()

        parent.addSublayer(a)
        parent.addSublayer(c)
        parent.insertSublayer(b, at: 1)
        XCTAssertEqual(ids(parent.sublayers), ids([a, b, c]), "insert(at: 1) lands between a and c")

        let d = CALayer()
        parent.insertSublayer(d, above: a)
        XCTAssertEqual(ids(parent.sublayers), ids([a, d, b, c]), "insert(above: a) lands immediately after a")
        XCTAssertTrue(d.superlayer === parent)

        let e = CALayer()
        parent.insertSublayer(e, below: c)
        XCTAssertEqual(ids(parent.sublayers), ids([a, d, b, e, c]), "insert(below: c) lands immediately before c")

        let back = CALayer()
        parent.insertSublayer(back, at: 0)
        XCTAssertEqual(ids(parent.sublayers), ids([back, a, d, b, e, c]), "insert(at: 0) lands at the back")
    }

    func testRemoveFromSuperlayer() {
        let parent = CALayer()
        let a = CALayer()
        let b = CALayer()
        parent.addSublayer(a)
        parent.addSublayer(b)

        a.removeFromSuperlayer()

        XCTAssertNil(a.superlayer)
        XCTAssertEqual(ids(parent.sublayers), ids([b]))
    }

    func testReplaceSublayer() {
        let parent = CALayer()
        let first = CALayer()
        let old = CALayer()
        let last = CALayer()
        parent.addSublayer(first)
        parent.addSublayer(old)
        parent.addSublayer(last)

        let replacement = CALayer()
        parent.replaceSublayer(old, with: replacement)

        XCTAssertNil(old.superlayer)
        XCTAssertTrue(replacement.superlayer === parent)
        XCTAssertEqual(ids(parent.sublayers), ids([first, replacement, last]),
                       "replacement must occupy the old layer's slot")
    }

    func testReAddingALayerDetachesItFromItsOldParentFirst() {
        let oldParent = CALayer()
        let newParent = CALayer()
        let child = CALayer()

        oldParent.addSublayer(child)
        newParent.addSublayer(child)

        XCTAssertTrue(child.superlayer === newParent)
        XCTAssertTrue((oldParent.sublayers ?? []).isEmpty, "old parent must no longer list the child")
        XCTAssertEqual(ids(newParent.sublayers), ids([child]))
    }

    // MARK: Coordinate-space conversion (3-layer tree with a scroll offset)

    /// root -> mid -> leaf. `mid` has a nonzero bounds.origin (a scroll
    /// offset), which must shift everything hosted inside it.
    private func makeConversionTree() -> (root: CALayer, mid: CALayer, leaf: CALayer) {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 300, height: 300)

        let mid = CALayer()
        mid.frame = CGRect(x: 20, y: 30, width: 200, height: 200)
        // Scroll offset: changes the coordinate space of mid's CONTENT,
        // not mid's own frame within root.
        mid.bounds = CGRect(x: 50, y: 60, width: 200, height: 200)

        let leaf = CALayer()
        leaf.frame = CGRect(x: 70, y: 80, width: 50, height: 50)

        root.addSublayer(mid)
        mid.addSublayer(leaf)
        return (root, mid, leaf)
    }

    func testConvertPointAcrossTree() {
        let (root, mid, leaf) = makeConversionTree()

        // leaf-origin in mid's space: leaf.frame.origin.
        assertEqual(leaf.convert(CGPoint.zero, to: mid), CGPoint(x: 70, y: 80), "leaf -> mid")

        // leaf-origin in root's space: mid.frame.origin + (leaf.frame.origin - mid.bounds.origin)
        //   = (20,30) + ((70,80) - (50,60)) = (40,50)
        assertEqual(leaf.convert(CGPoint.zero, to: root), CGPoint(x: 40, y: 50), "leaf -> root (scroll offset applied)")

        // Inverse direction, both spellings.
        assertEqual(leaf.convert(CGPoint(x: 40, y: 50), from: root), CGPoint.zero, "root -> leaf via from:")
        assertEqual(root.convert(CGPoint.zero, from: leaf), CGPoint(x: 40, y: 50), "leaf -> root via from:")
        assertEqual(root.convert(CGPoint(x: 40, y: 50), to: leaf), CGPoint.zero, "root -> leaf via to:")
    }

    func testConvertRectAcrossTree() {
        let (root, mid, leaf) = makeConversionTree()

        let local = CGRect(x: 0, y: 0, width: 10, height: 10)

        let inRoot = leaf.convert(local, to: root)
        assertEqual(inRoot, CGRect(x: 40, y: 50, width: 10, height: 10), "rect leaf -> root")

        let roundTripped = root.convert(inRoot, to: leaf)
        assertEqual(roundTripped, local, "rect root -> leaf round-trip")

        let inMid = mid.convert(local, from: leaf)
        assertEqual(inMid, CGRect(x: 70, y: 80, width: 10, height: 10), "rect leaf -> mid via from:")
    }

    func testFrameConversionAndHitTestingHonorAffineTransforms() {
        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 300, height: 300)

        let child = CALayer()
        child.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        child.position = CGPoint(x: 100, y: 100)
        child.transform = CATransform3DMakeScale(2, 2, 1)
        parent.addSublayer(child)

        assertEqual(child.frame, CGRect(x: 0, y: 50, width: 200, height: 100),
                    "scaled frame is the transformed bounds bounding box")
        assertEqual(child.convert(CGPoint(x: 100, y: 25), to: parent),
                    CGPoint(x: 200, y: 100),
                    "local point converts through layer transform")
        assertEqual(child.convert(CGPoint(x: 200, y: 100), from: parent),
                    CGPoint(x: 100, y: 25),
                    "inverse conversion uses transform inverse")
        XCTAssertTrue(parent.hitTest(CGPoint(x: 199, y: 100)) === child,
                      "hit testing maps the parent point through the inverse transform")
    }

    func testRotatedFrameUsesBoundingBox() {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        layer.position = CGPoint(x: 0, y: 0)
        layer.transform = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)

        let frame = layer.frame
        XCTAssertEqual(frame.width, 50, accuracy: 1e-9)
        XCTAssertEqual(frame.height, 100, accuracy: 1e-9)
        XCTAssertEqual(frame.midX, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.midY, 0, accuracy: 1e-9)
    }

    // MARK: contains + hitTest

    func testContains() {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertTrue(layer.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(layer.contains(CGPoint(x: 150, y: 50)))
        XCTAssertFalse(layer.contains(CGPoint(x: -1, y: 50)))
    }

    func testHitTestFindsDeepestLayerSkipsHiddenAndReturnsNilOutside() {
        let parent = CALayer()
        parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let child = CALayer()
        child.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        parent.addSublayer(child)

        // Point is given in the parent's SUPERLAYER coordinate space.
        XCTAssertTrue(parent.hitTest(CGPoint(x: 15, y: 15)) === child, "deepest hit wins")
        XCTAssertTrue(parent.hitTest(CGPoint(x: 50, y: 50)) === parent, "parent itself when no child contains the point")
        XCTAssertNil(parent.hitTest(CGPoint(x: 150, y: 150)), "outside everything -> nil")

        child.isHidden = true
        XCTAssertTrue(parent.hitTest(CGPoint(x: 15, y: 15)) === parent, "hidden child must be skipped")
    }

    // MARK: maskedCorners / CACornerMask

    func testMaskedCornersDefaultsToAllFourCorners() {
        let layer = CALayer()
        let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                 .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        XCTAssertEqual(layer.maskedCorners, all)
    }

    func testCACornerMaskBehavesAsAnOptionSet() {
        var mask: CACornerMask = [.layerMinXMinYCorner]
        XCTAssertTrue(mask.contains(.layerMinXMinYCorner))
        XCTAssertFalse(mask.contains(.layerMaxXMaxYCorner))

        mask.insert(.layerMaxXMaxYCorner)
        XCTAssertTrue(mask.contains(.layerMaxXMaxYCorner))

        let union = mask.union([.layerMaxXMinYCorner])
        XCTAssertTrue(union.contains(.layerMaxXMinYCorner))
        XCTAssertTrue(union.contains(.layerMinXMinYCorner))

        mask.remove(.layerMinXMinYCorner)
        XCTAssertFalse(mask.contains(.layerMinXMinYCorner))

        XCTAssertEqual(CACornerMask().rawValue, 0, "empty mask has empty raw value")
    }

    // MARK: mini-KVC (no Objective-C runtime on Linux)

    func testMiniKVCOpacityRoundTrip() {
        let layer = CALayer()
        layer.setValue(0.5 as Float, forKeyPath: "opacity")

        XCTAssertEqual(layer.opacity, 0.5, accuracy: 1e-6, "setValue must hit the real property")

        let boxed = layer.value(forKeyPath: "opacity")
        XCTAssertNotNil(boxed)
        XCTAssertEqual(scalar(boxed) ?? .nan, 0.5, accuracy: 1e-6, "value(forKeyPath:) must round-trip")
    }

    func testMiniKVCNestedKeyPath() {
        let layer = CALayer()
        layer.position = CGPoint(x: 12, y: 34)

        let x = layer.value(forKeyPath: "position.x")
        XCTAssertNotNil(x)
        XCTAssertEqual(scalar(x) ?? .nan, 12, accuracy: 1e-9)

        let y = layer.value(forKeyPath: "position.y")
        XCTAssertEqual(scalar(y) ?? .nan, 34, accuracy: 1e-9)
    }

    func testMiniKVCUnknownKeyReturnsNilWithoutCrashing() {
        let layer = CALayer()
        XCTAssertNil(layer.value(forKeyPath: "definitelyNotARealKey"))
    }

    // MARK: init(layer:) copies model values

    func testInitLayerCopiesModelValues() {
        let original = CALayer()
        original.bounds = CGRect(x: 1, y: 2, width: 30, height: 40)
        original.position = CGPoint(x: 5, y: 6)
        original.cornerRadius = 7
        original.backgroundColor = CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0)

        let copy = CALayer(layer: original)

        assertEqual(copy.bounds, original.bounds, "bounds copied")
        assertEqual(copy.position, original.position, "position copied")
        XCTAssertEqual(copy.cornerRadius, 7, accuracy: 1e-9)
        // Default backgroundColor is nil, so non-nil here proves the copy
        // carried the color over. (Value equality is not asserted: CGColor's
        // comparison semantics live in QuillFoundation, not this module.)
        XCTAssertNotNil(copy.backgroundColor, "backgroundColor copied")
    }

    func testPresentationReturnsDistinctSubclassSnapshot() {
        let original = CATextLayer()
        original.frame = CGRect(x: 10, y: 20, width: 80, height: 30)
        original.string = "Snapshot"
        original.fontSize = 14

        guard let snapshot = original.presentation() else {
            XCTFail("presentation must produce a snapshot")
            return
        }
        XCTAssertTrue(snapshot !== original, "presentation must not return the model layer itself")
        XCTAssertEqual(ObjectIdentifier(type(of: snapshot)), ObjectIdentifier(CATextLayer.self))
        assertEqual(snapshot.frame, original.frame)
        XCTAssertEqual(snapshot.string as? String, "Snapshot")
        XCTAssertEqual(snapshot.fontSize, 14, accuracy: 1e-9)
    }

    // MARK: Animation bookkeeping (synchronous only)

    func testAnimationKeysReflectAddAndRemoveSynchronously() {
        let layer = CALayer()
        // Empty state: Apple returns nil; an empty array is equally acceptable.
        XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)

        // 60-second duration: the async engine cannot complete these during
        // this purely synchronous test.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 60
        layer.add(fade, forKey: "fade")

        XCTAssertEqual(layer.animationKeys(), ["fade"])
        XCTAssertNotNil(layer.animation(forKey: "fade"))
        XCTAssertEqual((layer.animation(forKey: "fade") as? CABasicAnimation)?.keyPath, "opacity")

        let move = CABasicAnimation(keyPath: "position")
        move.duration = 60
        layer.add(move, forKey: "move")
        XCTAssertEqual(Set(layer.animationKeys() ?? []), Set(["fade", "move"]))

        layer.removeAnimation(forKey: "fade")
        XCTAssertNil(layer.animation(forKey: "fade"))
        XCTAssertEqual(layer.animationKeys() ?? [], ["move"])

        layer.removeAllAnimations()
        XCTAssertTrue((layer.animationKeys() ?? []).isEmpty)
        XCTAssertNil(layer.animation(forKey: "move"))
    }

    // MARK: Actions

    func testActionLookupFollowsApplePrecedenceAndStyleFallback() {
        let layer = DefaultActionLayer()
        let styleAction = LayerTestAction("style")
        let dictionaryAction = LayerTestAction("dictionary")
        let delegateAction = LayerTestAction("delegate")

        assertAction(layer.action(forKey: "opacity"), hasID: "default")

        layer.style = ["actions": ["opacity": styleAction as CAAction]]
        assertAction(layer.action(forKey: "opacity"), hasID: "style")

        layer.actions = ["opacity": dictionaryAction]
        assertAction(layer.action(forKey: "opacity"), hasID: "dictionary")

        let delegate = LayerActionDelegate(action: delegateAction)
        layer.delegate = delegate
        assertAction(layer.action(forKey: "opacity"), hasID: "delegate")
    }

    func testNSNullSuppressesLowerPriorityLayerActions() {
        let layer = DefaultActionLayer()
        let styleAction = LayerTestAction("style")

        layer.style = ["actions": ["opacity": styleAction as CAAction]]
        layer.actions = ["opacity": NSNull()]
        XCTAssertNil(layer.action(forKey: "opacity"), "actions NSNull suppresses style and defaults")

        layer.actions = nil
        layer.style = ["actions": ["opacity": NSNull()]]
        XCTAssertNil(layer.action(forKey: "opacity"), "style NSNull suppresses class defaults")

        let delegate = LayerActionDelegate(action: NSNull())
        layer.delegate = delegate
        layer.style = ["actions": ["opacity": styleAction as CAAction]]
        XCTAssertNil(layer.action(forKey: "opacity"), "delegate NSNull suppresses every lower-priority action")
    }

    // MARK: Subclass model/KVC coverage

    func testShapeLayerDefaultsCopyAndKVC() {
        let shape = CAShapeLayer()
        XCTAssertNotNil(shape.fillColor, "CAShapeLayer.fillColor defaults to opaque black")
        XCTAssertNil(shape.strokeColor, "CAShapeLayer.strokeColor defaults to nil")

        shape.setValue(4.5, forKey: "lineWidth")
        shape.setValue("round", forKey: "lineCap")
        shape.setValue("bevel", forKey: "lineJoin")
        shape.setValue(0.25, forKey: "strokeStart")
        shape.setValue(0.75, forKey: "strokeEnd")

        XCTAssertEqual(scalar(shape.value(forKey: "lineWidth")) ?? .nan, 4.5, accuracy: 1e-9)
        XCTAssertEqual((shape.value(forKey: "lineCap") as? CAShapeLayerLineCap)?.rawValue, "round")
        XCTAssertEqual((shape.value(forKey: "lineJoin") as? CAShapeLayerLineJoin)?.rawValue, "bevel")

        let copy = CAShapeLayer(layer: shape)
        XCTAssertEqual(copy.lineWidth, 4.5, accuracy: 1e-9)
        XCTAssertEqual(copy.lineCap, .round)
        XCTAssertEqual(copy.lineJoin, .bevel)
        XCTAssertEqual(copy.strokeStart, 0.25, accuracy: 1e-9)
        XCTAssertEqual(copy.strokeEnd, 0.75, accuracy: 1e-9)
    }

    func testGradientTextScrollAndMetalLayerCopyAndKVC() {
        let gradient = CAGradientLayer()
        gradient.setValue([CGColor.black, CGColor.white], forKey: "colors")
        gradient.setValue([0.2 as NSNumber, 0.8 as NSNumber], forKey: "locations")
        gradient.setValue(CGPoint(x: 0, y: 1), forKey: "startPoint")
        gradient.setValue("radial", forKey: "type")

        let gradientCopy = CAGradientLayer(layer: gradient)
        XCTAssertEqual(gradientCopy.colors?.count, 2)
        XCTAssertEqual(gradientCopy.locations, [0.2 as NSNumber, 0.8 as NSNumber])
        assertEqual(gradientCopy.startPoint, CGPoint(x: 0, y: 1))
        XCTAssertEqual(gradientCopy.type, .radial)

        let text = CATextLayer()
        XCTAssertEqual(text.fontSize, 36, accuracy: 1e-9)
        XCTAssertNotNil(text.foregroundColor)
        text.setValue("middle", forKey: "truncationMode")
        text.setValue("center", forKey: "alignmentMode")
        text.setValue(true, forKey: "wrapped")
        XCTAssertEqual((text.value(forKey: "truncationMode") as? CATextLayerTruncationMode)?.rawValue, "middle")
        XCTAssertEqual((text.value(forKey: "alignmentMode") as? CATextLayerAlignmentMode)?.rawValue, "center")
        XCTAssertEqual(scalar(text.value(forKey: "wrapped")) ?? .nan, 1, accuracy: 1e-9)

        let scroll = CAScrollLayer()
        scroll.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        scroll.scroll(to: CGRect(x: 80, y: 20, width: 30, height: 30))
        assertEqual(scroll.bounds.origin, CGPoint(x: 10, y: 0),
                    "scroll(to rect:) moves only enough to reveal the rect")
        scroll.setValue("horizontally", forKey: "scrollMode")
        XCTAssertEqual((scroll.value(forKey: "scrollMode") as? CAScrollLayerScrollMode)?.rawValue, "horizontally")

        let metal = CAMetalLayer()
        metal.setValue(MTLPixelFormat.rgba8Unorm, forKey: "pixelFormat")
        metal.setValue(false, forKey: "framebufferOnly")
        metal.setValue(CGSize(width: 320, height: 180), forKey: "drawableSize")
        let metalCopy = CAMetalLayer(layer: metal)
        XCTAssertEqual(metalCopy.pixelFormat, .rgba8Unorm)
        XCTAssertFalse(metalCopy.framebufferOnly)
        assertEqual(metalCopy.drawableSize, CGSize(width: 320, height: 180))
    }

    func testEmitterCellConformsToMediaTiming() {
        let cell = CAEmitterCell()
        cell.beginTime = 1
        cell.duration = 2
        cell.speed = 0.5
        cell.timeOffset = 0.25
        cell.repeatCount = 3
        cell.repeatDuration = 4
        cell.autoreverses = true
        cell.fillMode = .forwards

        XCTAssertEqual(cell.beginTime, 1)
        XCTAssertEqual(cell.duration, 2)
        XCTAssertEqual(cell.speed, 0.5)
        XCTAssertEqual(cell.timeOffset, 0.25)
        XCTAssertEqual(cell.repeatCount, 3)
        XCTAssertEqual(cell.repeatDuration, 4)
        XCTAssertTrue(cell.autoreverses)
        XCTAssertEqual(cell.fillMode, .forwards)
    }
}

// MARK: - CATransform3D math tests

/// All 16 matrix fields, for whole-matrix comparisons.
private func transform3DFields() -> [(name: String, keyPath: KeyPath<CATransform3D, CGFloat>)] {
    [
        ("m11", \.m11), ("m12", \.m12), ("m13", \.m13), ("m14", \.m14),
        ("m21", \.m21), ("m22", \.m22), ("m23", \.m23), ("m24", \.m24),
        ("m31", \.m31), ("m32", \.m32), ("m33", \.m33), ("m34", \.m34),
        ("m41", \.m41), ("m42", \.m42), ("m43", \.m43), ("m44", \.m44),
    ]
}

private func assertTransformEqual(_ a: CATransform3D, _ b: CATransform3D, accuracy: CGFloat,
                                  file: StaticString = #filePath, line: UInt = #line) {
    for field in transform3DFields() {
        XCTAssertEqual(a[keyPath: field.keyPath], b[keyPath: field.keyPath],
                       accuracy: accuracy, field.name, file: file, line: line)
    }
}

final class CATransform3DTests: XCTestCase {

    /// Applies a transform to a point using the ROW-VECTOR convention Core
    /// Animation uses: v' = [x y z 1] * M, then perspective-divide by w.
    private func apply(_ t: CATransform3D, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat)
        -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let rx = x * t.m11 + y * t.m21 + z * t.m31 + t.m41
        let ry = x * t.m12 + y * t.m22 + z * t.m32 + t.m42
        let rz = x * t.m13 + y * t.m23 + z * t.m33 + t.m43
        let rw = x * t.m14 + y * t.m24 + z * t.m34 + t.m44
        return (rx / rw, ry / rw, rz / rw)
    }

    func testTranslationAndScaleComposeViaConcat() {
        let translate = CATransform3DMakeTranslation(1, 2, 3)
        let scale = CATransform3DMakeScale(2, 2, 2)

        // Concat(a, b) applies a FIRST (row-vector convention):
        // origin -> translate -> (1,2,3) -> scale -> (2,4,6)
        let translateThenScale = CATransform3DConcat(translate, scale)
        let p = apply(translateThenScale, 0, 0, 0)
        XCTAssertEqual(p.x, 2, accuracy: 1e-12)
        XCTAssertEqual(p.y, 4, accuracy: 1e-12)
        XCTAssertEqual(p.z, 6, accuracy: 1e-12)

        // Reversed order: (1,1,1) -> scale -> (2,2,2) -> translate -> (3,4,5)
        let scaleThenTranslate = CATransform3DConcat(scale, translate)
        let q = apply(scaleThenTranslate, 1, 1, 1)
        XCTAssertEqual(q.x, 3, accuracy: 1e-12)
        XCTAssertEqual(q.y, 4, accuracy: 1e-12)
        XCTAssertEqual(q.z, 5, accuracy: 1e-12)
    }

    func testRotationUsesRowVectorConvention() {
        // +90 degrees about z must take (1,0,0) to (0,1,0) for row vectors.
        let r = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
        let p = apply(r, 1, 0, 0)
        XCTAssertEqual(p.x, 0, accuracy: 1e-9)
        XCTAssertEqual(p.y, 1, accuracy: 1e-9)
        XCTAssertEqual(p.z, 0, accuracy: 1e-9)
    }

    func testInvertComposesToIdentity() {
        let m = CATransform3DConcat(CATransform3DMakeRotation(0.7, 0, 0, 1),
                                    CATransform3DMakeTranslation(3, -2, 5))
        let inv = CATransform3DInvert(m)
        assertTransformEqual(CATransform3DConcat(m, inv), CATransform3DIdentity, accuracy: 1e-9)
        assertTransformEqual(CATransform3DConcat(inv, m), CATransform3DIdentity, accuracy: 1e-9)
    }

    func testIsIdentityAndEqualToTransform() {
        XCTAssertTrue(CATransform3DIsIdentity(CATransform3DIdentity))
        XCTAssertFalse(CATransform3DIsIdentity(CATransform3DMakeTranslation(1, 0, 0)))

        XCTAssertTrue(CATransform3DEqualToTransform(CATransform3DMakeTranslation(1, 2, 3),
                                                    CATransform3DMakeTranslation(1, 2, 3)))
        XCTAssertFalse(CATransform3DEqualToTransform(CATransform3DMakeTranslation(1, 2, 3),
                                                     CATransform3DMakeTranslation(1, 2, 4)))
    }

    func testIsAffine() {
        XCTAssertTrue(CATransform3DIsAffine(CATransform3DMakeTranslation(1, 2, 0)))

        var withPerspective = CATransform3DMakeTranslation(1, 2, 0)
        withPerspective.m34 = -1.0 / 500.0
        XCTAssertFalse(CATransform3DIsAffine(withPerspective))
    }

    func testAffineTransformRoundTrip() {
        let affine = CGAffineTransform(a: 2, b: 0.5, c: -0.5, d: 2, tx: 10, ty: 20)

        let t = CATransform3DMakeAffineTransform(affine)
        XCTAssertTrue(CATransform3DIsAffine(t))

        let back = CATransform3DGetAffineTransform(t)
        XCTAssertEqual(back.a, affine.a, accuracy: 1e-12)
        XCTAssertEqual(back.b, affine.b, accuracy: 1e-12)
        XCTAssertEqual(back.c, affine.c, accuracy: 1e-12)
        XCTAssertEqual(back.d, affine.d, accuracy: 1e-12)
        XCTAssertEqual(back.tx, affine.tx, accuracy: 1e-12)
        XCTAssertEqual(back.ty, affine.ty, accuracy: 1e-12)
    }

    func testNSValueBoxingRoundTrip() {
        let t = CATransform3DConcat(CATransform3DMakeRotation(1.0, 1, 0, 0),
                                    CATransform3DMakeTranslation(7, 8, 9))
        let boxed = NSValue(caTransform3D: t)
        let unboxed = boxed.caTransform3DValue
        XCTAssertTrue(CATransform3DEqualToTransform(t, unboxed))
    }
}
