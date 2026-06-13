# SceneKit conformance campaign

Goal: real SceneKit apps compile UNMODIFIED and render on QuillOS Linux,
following the SolderScope playbook (docs/solderscope-conformance.md). The
SceneKit shim today is inert (`Sources/AppleFrameworkShims/SceneKit` — one
`import Foundation`); this campaign grows it into a functional surface, with
each target app's compile errors as the work-list.

## Target apps

| Target | Source | License | What it proves |
| --- | --- | --- | --- |
| `Euclid` (lib) | [nicklockwood/Euclid](https://github.com/nicklockwood/Euclid) `.upstream/euclid` | MIT | Pure-Swift 3D geometry/CSG core. NOTE: in this package's shared scratch, upstream's canImport gates leak TRUE for every shim module in the graph, so Euclid's SceneKit/AppKit/UIKit/CG/CT interop files compile too — their gaps ARE the first census (and pin down the exact mesh-handoff surface). |
| `QuillSolarSystem` (fixture) | `Sources/QuillSceneKitFixtures/SolarSystem` (authored in-repo) | — | First SCN surface: SCNScene/SCNNode, SCNSphere, diffuse/emission materials, omni+ambient lights, SCNCamera, repeating SCNActions, `look(at:)`, SwiftUI `SceneView`, `scene.isPaused`. |
| `QuillMoleculeViewer` (fixture) | `Sources/QuillSceneKitFixtures/MoleculeViewer` (authored in-repo) | — | Adds SCNCylinder, specular materials, directional lights, pivot-oriented bonds, swapping a SceneView's scene from state. |
| `QuillEuclidExample` | `.upstream/euclid/Example` | MIT | Real UIKit + SceneKit demo app (SCNGeometry from raw mesh data, gesture-driven camera; one RealityKit screen against the inert RealityKit shim; one visionOS volumetric view). |
| `ShapeScript` (lib) + `QuillShapeScriptCLI` | [nicklockwood/ShapeScript](https://github.com/nicklockwood/ShapeScript) `.upstream/shapescript` | MIT | The 3D-modeling language core; supports Linux upstream — expected green early. Deps: `SVGPath` (MIT, path-based target) and `LRUCache`, which resolves to the existing in-repo stub `Sources/LRUCache` (no-op cache: correct, just uncached; rung 1 may repoint it at `.upstream/lrucache`). |
| `QuillShapeScriptViewer` | `.upstream/shapescript/Viewer` (Mac + Shared) | MIT | **Flagship**: a real shipped, NSDocument-based AppKit macOS app whose entire viewport is an SCNView. Doubles as an AppKit-reimplementation conformance driver (docs/appkit-reimplementation.md). |

Vetted and rejected: BioViewer (custom Metal engine, not SceneKit); the
GitHub solar-system/molecule corpus (ARKit-based, GPL, or unlicensed) —
which is why the two fixtures are authored in-repo instead, as faithful
macOS SwiftUI+SceneKit apps we fully control for later pixel comparison.

## Fetching

```sh
scripts/fetch-upstream.sh scenekit   # euclid + lrucache + svgpath + shapescript
```

Targets are presence-gated (inert on CI; fetch to enable). ShapeScript pins
Euclid 0.8.x via SwiftPM URL deps upstream; we compile it against
`.upstream/euclid` (HEAD == 0.8.14 today) as path-based targets so every
source stays unmodified and locally inspectable. If upstream Euclid moves to
0.9, pin the euclid fetch to the 0.8.x tag in fetch-upstream.sh.

The fixtures are additionally env-gated — they are RED until the SCN surface
exists, so they must not break whole-graph `swift build` for anyone who has
`.upstream` populated:

```sh
QUILLUI_SCENEKIT_FIXTURES=1 swift build --target QuillSolarSystem
```

## Ladder

1. **Euclid lib green, then ShapeScript lib/CLI green**. Because of the
   canImport leakage (table note), Euclid-green already requires the first
   sliver of SCN data types (SCNGeometry sources/elements, SCNVector3 et
   al.) plus small AppKit/UIKit/CG/CT member fills — a forced, well-scoped
   census of exactly the mesh-handoff surface. `shapescript` CLI rendering
   a .shape file to OBJ/STL on QuillOS is then a real, demoable win with
   zero rendering surface.
2. **SCN surface census, app tier**: enumerate compile errors of the two
   fixtures + QuillEuclidExample + QuillShapeScriptViewer (the SolderScope
   error-census pattern); author the SCNScene/SCNNode/material/light/
   camera/action types in the SceneKit shim, backed by nothing yet (inert
   render).
3. **Fixtures render on GTK**: software-render the scene graph (project the
   sphere/cylinder primitives via the existing Cairo CGContext path — flat
   shading first, the fixtures' scenes are deliberately simple) behind
   SwiftUI `SceneView`/AppKit `SCNView` hosts. Screenshot gates like
   SolderScope's.
4. **QuillEuclidExample renders**: real mesh data via SCNGeometry sources/
   elements (Euclid's `canImport(SceneKit)` interop lights up here and
   hands us triangle meshes directly).
5. **QuillShapeScriptViewer launches**: NSDocument chrome via QuillAppKit +
   SCNView viewport; ShapeScript's evaluator already supplies the meshes.
6. **Pixel parity** vs macOS references (QuillPaint pipeline), camera
   controls, hit-testing — driven by what the apps actually use.

GPU honesty: SceneKit on QuillOS starts as a software rasterizer over the
existing 2D paint layer. That is enough for these apps' scene scale; a GL/
Vulkan backend is a later, separate decision — do not promise GPU parity.

## Status

- [x] Targets wired, presence/env-gated; fetch arms + meta-arm added
- [x] Fixtures authored (faithful macOS SwiftUI+SceneKit source)
- [x] Inert RealityKit shim module (Euclid Example's RealityKitViewController)
- [ ] Rung 1: Euclid + ShapeScript lib/CLI green on Linux
- [ ] Rung 2: SCN surface census + shim types
- [ ] Rung 3: fixtures render (GTK screenshot gate)
- [ ] Rung 4: QuillEuclidExample renders
- [ ] Rung 5: QuillShapeScriptViewer launches
- [ ] Rung 6: pixel parity
