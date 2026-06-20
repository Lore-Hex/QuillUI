// SceneKit shim for QuillOS — umbrella file.
//
// A functional model of macOS SceneKit's scene-graph API so real macOS
// SwiftUI+SceneKit apps compile and run on QuillOS Linux. The surface is split
// across this directory:
//   • SCNVector.swift      — SCNVector3/4, SCNQuaternion, SCNMatrix4
//   • SCNGeometry.swift     — SCNGeometry + parametric primitives + source/element
//   • SCNMaterial.swift     — SCNMaterial / SCNMaterialProperty + enums
//   • SCNLightCamera.swift  — SCNLight, SCNCamera
//   • SCNNode.swift         — the scene-graph node
//   • SCNAction.swift       — interpretable action tree
//   • SCNActionRuntime.swift — deterministic action stepping
//   • SCNScene.swift        — SCNScene, SCNSceneSource
//   • SCNSoftwareRenderer.swift — deterministic software render + hit-test pass
//   • SceneView.swift       — SwiftUI SceneView bridge to the software renderer
//
// Rendering starts as a deterministic CPU path over QuillFoundation BGRA
// CGImages. See docs/scenekit-conformance.md for the conformance ladder.
//
// Real SceneKit re-exports Foundation + CoreGraphics through its umbrella, so a
// file with only `import SceneKit` (Euclid's interop) resolves URL / Data /
// pow / CGPoint / CGSize. On QuillOS those all live in (swift-corelibs)
// Foundation, so re-export it for the same reach.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import AppKit
@_exported import UIKit
@_exported import enum QuillFoundation.objc_AssociationPolicy
@_exported import func QuillFoundation.objc_getAssociatedObject
@_exported import func QuillFoundation.objc_setAssociatedObject
