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
//   • SCNScene.swift        — SCNScene, SCNSceneSource
//   • SceneView.swift       — SwiftUI SceneView (inert until the rung-3 renderer)
//
// Rendering is deliberately absent here: the types hold the scene graph
// faithfully so the rung-3 software rasteriser (over the Cairo CGContext path)
// can walk it. See docs/scenekit-conformance.md.
import Foundation
