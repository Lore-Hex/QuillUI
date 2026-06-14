# SceneKit conformance campaign

Goal: real SceneKit apps compile UNMODIFIED and render on QuillOS Linux,
following the SolderScope playbook (docs/solderscope-conformance.md). The
SceneKit shim today is inert (`Sources/AppleFrameworkShims/SceneKit` — one
`import Foundation`); this campaign grows it into a functional surface, with
each target app's compile errors as the work-list.

## Target apps

| Target | Source | License | What it proves |
| --- | --- | --- | --- |
| `Euclid` (lib) | [nicklockwood/Euclid](https://github.com/nicklockwood/Euclid) `.upstream/euclid` | MIT | Pure-Swift 3D geometry/CSG core. Compiles **green at rung 1** with no Apple deps: its `Euclid+SceneKit/AppKit/UIKit/CG/CT/SIMD` files are `#if canImport(...)` gated and drop out when those modules aren't pulled into the dep graph. Built `.swiftLanguageMode(.v5)` (its global statics + `@Sendable` permutation closures trip Swift 6 strict-concurrency). The SceneKit interop lights up at rung 2 once the SceneKit shim is authored and added as a dep. |
| `QuillSolarSystem` (fixture) | `Sources/QuillSceneKitFixtures/SolarSystem` (authored in-repo) | — | First SCN surface: SCNScene/SCNNode, SCNSphere, diffuse/emission materials, omni+ambient lights, SCNCamera, repeating SCNActions, `look(at:)`, SwiftUI `SceneView`, `scene.isPaused`. |
| `QuillMoleculeViewer` (fixture) | `Sources/QuillSceneKitFixtures/MoleculeViewer` (authored in-repo) | — | Adds SCNCylinder, specular materials, directional lights, pivot-oriented bonds, swapping a SceneView's scene from state. |
| `QuillEuclidExample` | `.upstream/euclid/Example` | MIT | Real UIKit + SceneKit demo app (SCNGeometry from raw mesh data, gesture-driven camera; one RealityKit screen against the inert RealityKit shim; one visionOS volumetric view). |
| `ShapeScript` (lib) + `QuillShapeScriptCLI` | [nicklockwood/ShapeScript](https://github.com/nicklockwood/ShapeScript) `.upstream/shapescript` | MIT | The 3D-modeling language core; **green at rung 1**. Deps: `Euclid`, `SVGPath` (MIT, path-based), and the REAL `.upstream/lrucache` compiled as `ShapeScriptLRUCache` + `-module-alias LRUCache=ShapeScriptLRUCache` (its `GeometryCache` needs the full LRUCache API the in-repo no-op stub lacks). |
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

1. **Euclid lib green, then ShapeScript lib/CLI green** — ✅ DONE. No SCN
   surface needed: Euclid's interop files are `canImport`-gated and drop
   out with no Apple deps; both targets just need `.swiftLanguageMode(.v5)`
   (Swift-5 upstream code vs the default Swift 6 strict-concurrency mode).
   ShapeScript's `GeometryCache` needs the REAL nicklockwood/LRUCache API
   (the repo's in-repo `LRUCache` stub is a no-op), supplied via a distinct
   `ShapeScriptLRUCache` target + `-module-alias LRUCache=ShapeScriptLRUCache`.
   The `shapescript` CLI renders `.shape` → `.stl` on QuillOS Linux through
   the full evaluate→Euclid-geometry→export pipeline (verified: Ball 66 KB,
   Spring 413 KB, Cog 13 KB, Icosahedron 1 KB) — a real 3D win with zero
   rendering surface.
2. **SCN scene-graph shim authored; fixtures compile** — ✅ DONE for the
   fixtures. The SceneKit shim (`Sources/AppleFrameworkShims/SceneKit`) now
   models the scene-graph surface: `SCNVector3/4`, `SCNQuaternion`,
   `SCNMatrix4`, `SCNNode` (position/eulerAngles/scale/orientation/geometry/
   light/camera/addChildNode/runAction/`look(at:)`), `SCNGeometry` + the
   parametric primitives (`SCNSphere`/`SCNCylinder`/`SCNBox`/`SCNCone`/…) +
   `SCNGeometrySource`/`SCNGeometryElement`, `SCNMaterial`/
   `SCNMaterialProperty` (diffuse/emission/specular + wrap/filter enums),
   `SCNLight`, `SCNCamera`, `SCNScene`/`SCNSceneSource`, an interpretable
   `SCNAction` tree, and SwiftUI's `SceneView`. `QuillSolarSystem` and
   `QuillMoleculeViewer` compile unmodified against it
   (`QUILLUI_SCENEKIT_FIXTURES=1`). Render is still inert (black `SceneView`);
   the graph is held faithfully for the rung-3 rasteriser. The SceneKit shim
   gains a `SwiftUI` dep (for `SceneView`) — acyclic, and the
   `Color(nsColor:)`/`Color(uiColor:)` bridges real source uses were added
   to the shared shim. STILL TODO at this rung: census + compile
   `QuillEuclidExample` and `QuillShapeScriptViewer` (they need Euclid's
   `canImport(SceneKit)` interop + the `SCNGeometrySource` data marshalling
   to light up — a deeper surface than the fixtures).
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
- [x] Rung 1: Euclid + ShapeScript lib/CLI green on Linux (CLI renders .shape → .stl)
- [x] Rung 2 (fixtures): SceneKit scene-graph shim authored; QuillSolarSystem + QuillMoleculeViewer compile
- [ ] Rung 3: fixtures render (GTK screenshot gate)
- [ ] Rung 4: QuillEuclidExample renders
- [ ] Rung 5: QuillShapeScriptViewer launches
- [ ] Rung 6: pixel parity
