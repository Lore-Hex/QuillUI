import AppKit
import SceneKit

func makeMoleculeScene(_ molecule: Molecule) -> SCNScene {
    let scene = SCNScene()
    scene.background.contents = NSColor(calibratedWhite: 0.08, alpha: 1)

    let root = SCNNode()
    root.name = molecule.name
    scene.rootNode.addChildNode(root)

    for atom in molecule.atoms {
        let geometry = SCNSphere(radius: atom.element.radius)
        geometry.firstMaterial?.diffuse.contents = atom.element.color
        geometry.firstMaterial?.specular.contents = NSColor(calibratedWhite: 0.9, alpha: 1)
        let node = SCNNode(geometry: geometry)
        node.name = atom.element.rawValue
        node.position = SCNVector3(atom.position.x, atom.position.y, atom.position.z)
        root.addChildNode(node)
    }

    for bond in molecule.bonds {
        let from = molecule.atoms[bond.from].position
        let to = molecule.atoms[bond.to].position
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dz = to.z - from.z
        let length = (dx * dx + dy * dy + dz * dz).squareRoot()

        // SCNCylinder's long axis is local Y. Hang the cylinder off a pivot
        // node so its +Y runs along the pivot's -Z, then point the pivot's
        // -Z at the far atom with look(at:) — the classic bond-orientation
        // idiom, no quaternion math required.
        let cylinder = SCNCylinder(radius: 0.09, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.55, alpha: 1)
        let cylinderNode = SCNNode(geometry: cylinder)
        cylinderNode.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        cylinderNode.position = SCNVector3(0, 0, -length / 2)

        let pivot = SCNNode()
        pivot.position = SCNVector3(from.x, from.y, from.z)
        pivot.addChildNode(cylinderNode)
        root.addChildNode(pivot)
        pivot.look(at: SCNVector3(to.x, to.y, to.z))
    }

    // Slow tumble so depth reads even before camera control works.
    root.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 18)))

    let key = SCNLight()
    key.type = .directional
    let keyNode = SCNNode()
    keyNode.light = key
    keyNode.eulerAngles = SCNVector3(-CGFloat.pi / 4, CGFloat.pi / 6, 0)
    scene.rootNode.addChildNode(keyNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.color = NSColor(calibratedWhite: 0.35, alpha: 1)
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)

    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.position = SCNVector3(0, 0, 14)
    scene.rootNode.addChildNode(cameraNode)

    return scene
}
