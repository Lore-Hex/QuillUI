// QuillMoleculeViewer — in-repo SceneKit conformance fixture #2.
//
// Ball-and-stick molecule data. Geometries are computed (tetrahedral /
// hexagonal-ring trigonometry), not hardcoded tables, so the file stays
// small and auditable. CPK coloring.
import AppKit
import Foundation

enum Element: String, CaseIterable {
    case hydrogen = "H"
    case carbon = "C"
    case oxygen = "O"

    var color: NSColor {
        switch self {
        case .hydrogen: return NSColor(calibratedWhite: 0.92, alpha: 1)
        case .carbon: return NSColor(calibratedWhite: 0.25, alpha: 1)
        case .oxygen: return NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.12, alpha: 1)
        }
    }

    /// Display radius in scene units (not to physical scale).
    var radius: CGFloat {
        switch self {
        case .hydrogen: return 0.28
        case .carbon: return 0.42
        case .oxygen: return 0.44
        }
    }
}

struct Atom {
    let element: Element
    let position: (x: Double, y: Double, z: Double)
}

struct Bond {
    let from: Int
    let to: Int
}

struct Molecule: Identifiable {
    let name: String
    let atoms: [Atom]
    let bonds: [Bond]
    var id: String { name }
}

/// H2O: bent geometry, 104.5° H-O-H angle, O-H length 0.96 (scaled 2x for
/// display).
func makeWater() -> Molecule {
    let angle = 104.5 * Double.pi / 180
    let length = 1.92
    let half = angle / 2
    return Molecule(
        name: "Water",
        atoms: [
            Atom(element: .oxygen, position: (0, 0, 0)),
            Atom(element: .hydrogen, position: (length * sin(half), -length * cos(half), 0)),
            Atom(element: .hydrogen, position: (-length * sin(half), -length * cos(half), 0)),
        ],
        bonds: [Bond(from: 0, to: 1), Bond(from: 0, to: 2)]
    )
}

/// CH4: carbon at the origin, hydrogens at alternating cube corners — the
/// standard tetrahedral construction.
func makeMethane() -> Molecule {
    let d = 2.2 / sqrt(3.0)
    let corners: [(Double, Double, Double)] = [
        (d, d, d), (d, -d, -d), (-d, d, -d), (-d, -d, d),
    ]
    var atoms = [Atom(element: .carbon, position: (0, 0, 0))]
    var bonds: [Bond] = []
    for (i, corner) in corners.enumerated() {
        atoms.append(Atom(element: .hydrogen, position: corner))
        bonds.append(Bond(from: 0, to: i + 1))
    }
    return Molecule(name: "Methane", atoms: atoms, bonds: bonds)
}

/// C6H6: planar hexagonal ring, carbons at radius 1.39 (scaled 2x),
/// hydrogens radially outward.
func makeBenzene() -> Molecule {
    var atoms: [Atom] = []
    var bonds: [Bond] = []
    let carbonRadius = 2.78
    let hydrogenRadius = 4.94
    for i in 0..<6 {
        let theta = Double(i) * .pi / 3
        atoms.append(Atom(element: .carbon, position: (carbonRadius * cos(theta), carbonRadius * sin(theta), 0)))
    }
    for i in 0..<6 {
        let theta = Double(i) * .pi / 3
        atoms.append(Atom(element: .hydrogen, position: (hydrogenRadius * cos(theta), hydrogenRadius * sin(theta), 0)))
        bonds.append(Bond(from: i, to: (i + 1) % 6))  // ring C-C
        bonds.append(Bond(from: i, to: i + 6))  // C-H
    }
    return Molecule(name: "Benzene", atoms: atoms, bonds: bonds)
}

let molecules: [Molecule] = [makeWater(), makeMethane(), makeBenzene()]
