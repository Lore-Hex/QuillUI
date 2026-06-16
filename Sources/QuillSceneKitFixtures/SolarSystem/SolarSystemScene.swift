import AppKit
import SceneKit

struct Planet {
    let name: String
    let color: NSColor
    let radius: CGFloat
    let orbitRadius: CGFloat
    /// Seconds per revolution at 1x speed.
    let period: TimeInterval
    var hasMoon: Bool = false
}

let planets: [Planet] = [
    Planet(name: "Mercury", color: NSColor(calibratedRed: 0.66, green: 0.62, blue: 0.58, alpha: 1), radius: 0.25, orbitRadius: 3.2, period: 6),
    Planet(name: "Venus", color: NSColor(calibratedRed: 0.90, green: 0.75, blue: 0.45, alpha: 1), radius: 0.42, orbitRadius: 4.6, period: 10),
    Planet(name: "Earth", color: NSColor(calibratedRed: 0.25, green: 0.45, blue: 0.85, alpha: 1), radius: 0.45, orbitRadius: 6.2, period: 16, hasMoon: true),
    Planet(name: "Mars", color: NSColor(calibratedRed: 0.80, green: 0.35, blue: 0.20, alpha: 1), radius: 0.34, orbitRadius: 7.8, period: 26),
]

func makeSolarSystemScene() -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = NSColor.black

    // Sun: emissive sphere + an omni light at the same spot so planets are
    // lit from the center.
    let sunGeometry = SCNSphere(radius: 1.4)
    sunGeometry.firstMaterial?.emission.contents = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.35, alpha: 1)
    sunGeometry.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
    let sun = SCNNode(geometry: sunGeometry)
    sun.name = "Sun"
    scene.rootNode.addChildNode(sun)

    let sunLight = SCNLight()
    sunLight.type = .omni
    sunLight.color = NSColor(calibratedWhite: 1.0, alpha: 1)
    let sunLightNode = SCNNode()
    sunLightNode.light = sunLight
    scene.rootNode.addChildNode(sunLightNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.color = NSColor(calibratedWhite: 0.18, alpha: 1)
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)

    for planet in planets {
        // Orbit pivot at the origin; the planet hangs off it at orbitRadius
        // and the pivot spins, which is the classic SceneKit orbit idiom.
        let pivot = SCNNode()
        pivot.name = "\(planet.name)-orbit"
        scene.rootNode.addChildNode(pivot)

        let geometry = SCNSphere(radius: planet.radius)
        geometry.firstMaterial?.diffuse.contents = planet.color
        let node = SCNNode(geometry: geometry)
        node.name = planet.name
        node.position = SCNVector3(planet.orbitRadius, 0, 0)
        pivot.addChildNode(node)

        if planet.hasMoon {
            let moonGeometry = SCNSphere(radius: 0.12)
            moonGeometry.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.75, alpha: 1)
            let moonPivot = SCNNode()
            node.addChildNode(moonPivot)
            let moon = SCNNode(geometry: moonGeometry)
            moon.name = "Moon"
            moon.position = SCNVector3(0.9, 0, 0)
            moonPivot.addChildNode(moon)
            moonPivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3)))
        }

        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: planet.period)))
        // Spin the planet on its own axis too.
        node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4)))
    }

    // Camera looking down at a shallow angle.
    let camera = SCNCamera()
    camera.zFar = 100
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 9, 16)
    cameraNode.look(at: SCNVector3(0, 0, 0))
    scene.rootNode.addChildNode(cameraNode)

    return scene
}
