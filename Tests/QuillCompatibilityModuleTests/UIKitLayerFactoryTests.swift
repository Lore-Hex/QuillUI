import Testing
import UIKit
import QuartzCore

#if os(Linux)
private final class PlainOverrideLayer: CALayer, QuillUIKitLayerConstructible {
    var initializedWithPlainOverride = false

    override init() {
        initializedWithPlainOverride = true
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    static func quillUIKitMakeLayer() -> CALayer {
        PlainOverrideLayer()
    }
}

private final class PlainOverrideLayerView: UIView {
    override class var layerClass: AnyClass { PlainOverrideLayer.self }
}

private final class RegisteredLayer: CALayer {
    var source = "default"
}

private final class RegisteredLayerView: UIView {
    override class var layerClass: AnyClass { RegisteredLayer.self }
}

private final class UnconstructibleLayer: CALayer {}

private final class UnconstructibleLayerView: UIView {
    override class var layerClass: AnyClass { UnconstructibleLayer.self }
}

@Suite("UIKit layer factory compatibility")
@MainActor
struct UIKitLayerFactoryTests {
    @Test("CALayer subclasses compile with plain override init")
    func calayerSubclassCanUsePlainOverrideInit() {
        let layer = PlainOverrideLayer()

        #expect(layer is CALayer)
    }

    @Test("UIView layerClass creates constructible custom layer subclasses")
    func constructibleCustomLayerClassCreatesUIViewLayer() {
        let view = PlainOverrideLayerView()
        view.frame = CGRect(x: 0, y: 0, width: 42, height: 24)

        let layer = view.layer as? PlainOverrideLayer
        #expect(layer != nil)
        #expect(layer?.initializedWithPlainOverride == true)
        #expect(view.layer.frame.size.width == 42)
        #expect(view.layer.frame.size.height == 24)
    }

    @Test("UIView layerClass falls back when custom class has no factory")
    func unconstructibleCustomLayerClassFallsBackToCALayer() {
        let layer = UnconstructibleLayerView().layer

        #expect(type(of: layer) == CALayer.self)
    }

    @Test("UIView layerClass custom factory can override default construction")
    func registeredCustomLayerClassOverridesDefaultConstruction() {
        quillUIKitRegisterLayerClass(RegisteredLayer.self) {
            let layer = RegisteredLayer()
            layer.source = "registered"
            return layer
        }

        let view = RegisteredLayerView()

        #expect((view.layer as? RegisteredLayer)?.source == "registered")
    }

    @Test("UIView layerClass creates known system layer subclasses")
    func knownSystemLayerClassCreatesUIViewLayer() {
        final class ShapeLayerView: UIView {
            override class var layerClass: AnyClass { CAShapeLayer.self }
        }

        #expect(ShapeLayerView().layer is CAShapeLayer)
    }

    @Test("UIView layer is created once and keeps view-layer hierarchy in sync")
    func layerIdentityAndSubviewHierarchyStayStable() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 60))
        let child = PlainOverrideLayerView(frame: CGRect(x: 4, y: 5, width: 20, height: 10))

        let firstLayer = child.layer
        child.frame = CGRect(x: 9, y: 11, width: 30, height: 12)
        parent.addSubview(child)

        #expect(child.layer === firstLayer)
        #expect(child.layer.superlayer === parent.layer)
        #expect(parent.layer.sublayers?.contains { $0 === child.layer } == true)
        #expect(child.layer.frame == child.frame)

        child.removeFromSuperview()

        #expect(child.layer.superlayer == nil)
        #expect(parent.layer.sublayers == nil)
    }
}
#endif
