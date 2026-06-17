# SceneKit conformance campaign

Goal: real SceneKit apps compile UNMODIFIED and render on QuillOS Linux,
following the SolderScope playbook (docs/solderscope-conformance.md). The
SceneKit now has a functional Linux software-renderer compatibility lane under
`Sources/AppleFrameworkShims/SceneKit`; this campaign keeps growing it with
each target app's compile, render, and interaction gaps as the work-list.

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
   models the scene-graph surface: `SCNVector3/4` value, zero, and make helpers, `SCNQuaternion`,
   `SCNMatrix4`, `SCNNode` (position/eulerAngles/scale/orientation/geometry/
   light/camera/parenting/traversal/replacement/cloning/local and world transforms/scale/orientation/SIMD vector and direction aliases/direction vectors/presentation/bounding boxes/runAction/`look(at:)`), `SCNGeometry` + the
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
   to the shared shim. The real app-tier compile moved to rung 2c because it
   wakes Euclid and ShapeScript interop beyond the fixture surface.
2b. **App-tier interop surface authored; Euclid interop verified** — the
   Mesh⇄SCNGeometry marshalling that Euclid's `Euclid+SceneKit` needs is now
   in the shim: `SCNGeometrySource(vertices:/normals:/textureCoordinates:)`,
   `SCNGeometryElement(indices:primitiveType:)`, `SCNGeometry.boundingBox`/
   `copy()`, `SCNText`/`SCNShape`, `SCNMatrix4Invert`/`IsIdentity`,
   `SCNMaterial: Hashable`, and `SCNScene.write`/`SCNSceneSource` for Quill's
   deterministic scene archive format. The CoreGraphics shim gained
   the long-missing `CGPoint`/`CGSize`/`CGRect`/`CGFloat` re-export (real
   gap — pure-geometry `import CoreGraphics` files expect them) plus
   `CGPathElement`/`CGPathElementType` + a functional `CGPath.applyWithBlock`
   (QuillFoundation) and the `CFTypeRef`/`CFGetTypeID`/`CGImage.typeID` sliver
   `defaultMaterialLookup` needs. With these, **`Euclid`'s full SceneKit/
   AppKit/CoreGraphics interop compiles 727 → 0 errors** (verified on a
   branch that declared the interop deps).
   The follow-up CoreGraphics quality pass now makes recorded `CGPath` data
   transform-aware (`CGPath(rect:transform:)`, `copy(using:)`, and
   `CGMutablePath.addPath(_:transform:)`) and records rounded rects/ellipses as
   cubic curve elements instead of plain rectangles. The path value surface now
   includes center/radius arcs, tangent arcs, emptiness/current-point accessors,
   point and tight path bounds, and winding/even-odd containment over flattened
   curves. The drawing shim now forwards `CGContext.addRects`,
   `CGContext.addPath`, direct quad/cubic curves, and fill-rule-aware fill/clip
   operations plus tangent-arc line/cubic expansions into the Cairo-backed GTK
   drawing host, while `CGContext` itself tracks `isPathEmpty`,
   `currentPointOfPath`, `pathBoundingBox`, and `copyPath()` without requiring
   a backend. The color surface also tracks `CGColorSpace` model/component
   metadata and `CGColor(colorSpace:components:)` RGB/gray component shapes.
   `CoreGraphicsTests` exercises the value surface through a direct
   `import CoreGraphics` path.

   This surface is now enabled by rung 2c. The key build gotcha remains:
   `canImport` state can look poisoned in a shared scratch, so use clean
   isolated volumes per concern when validating SceneKit/ShapeScript changes.
2c. **App-tier compile enablement** — ✅ DONE. Euclid now builds with
   `SceneKit`/`UIKit`/`AppKit`/`CoreGraphics` deps so its real
   `Euclid+SceneKit` and `Euclid+CoreGraphics` interop compiles. The Euclid
   example compiles after Linux-only fetch-time source lowering handles the
   selector/init glue and the inert RealityKit shim supplies its small
   RealityKit screen. ShapeScript's woken `Material+SceneKit`/
   `Scene+SceneKit`/CoreText importer surface compiles, and the shipped
   AppKit `QuillShapeScriptViewer` compiles against `SCNView`, `Cocoa`, and
   `CoreServices`. Verified on Linux Docker:
   `QuillFoundation`, `QuillUIKit`, `SceneKit`, `QuillSolarSystem`,
   `QuillMoleculeViewer`, `QuillEuclidExample`, `ShapeScript`,
   `QuillShapeScriptCLI`, and `QuillShapeScriptViewer`. Rendering is still
   inert; rung 3 is the first raster output gate.
3. **Fixtures render on GTK** — ✅ DONE. `SceneView` and `SCNView` now route
   the retained SceneKit graph through a deterministic software renderer,
   drawing BGRA `CGImage`s through the existing AppKit/GTK custom-draw path.
   The renderer covers the fixture surface (`SCNSphere`, `SCNCylinder`,
   `SCNBox`, basic node transforms/camera projection, materials, and scene
   background). Verified by `quill-scenekit-render-smoke` direct pixel checks
   and an Xvfb GTK `SceneView` smoke that differs from a solid-black reference.
4. **QuillEuclidExample renders** — ✅ DONE for the real mesh path. The
   software renderer decodes `SCNGeometrySource`/`SCNGeometryElement` buffers
   for triangles, strips, lines, points, and polygon fans, so Euclid's
   `SCNGeometry(mesh)` interop renders actual mesh data. Verified by
   `quill-euclid-render-smoke`, which builds a real `Euclid.Mesh`, converts it
   through `SCNGeometry(mesh)`, renders it, and asserts colored pixels.
5. **QuillShapeScriptViewer launches** — ✅ DONE. `QuillShapeScriptViewer` is
   now exposed as a SwiftPM executable product, rebuilds against the rendered
   `SCNView`, and launch-smokes under Xvfb by staying alive until timeout with
   no early crash.
6. **Pixel parity / controls / hit-testing** — ✅ DONE for the current
   CPU/software renderer scope. `SCNView.hitTest`
   now uses the same projected primitives as the software renderer and returns
   nearest-first `SCNHitTestResult`s, covering ShapeScript's geometry-selection
   path. Camera orientation is now respected by the software renderer, explicit
   `SCNCamera.zNear`/`zFar` clipping culls both rendered and hit-tested
   primitives, and deterministic `SCNView` camera-control movement is
   smoke-gated by creating a moved point-of-view camera for ShapeScript-style
   `cameraHasMoved` checks.
   The AppKit event pump now forwards pointer, scroll, magnify, cursor, and
   enter/exit events through `NSApplication.sendEvent`, with a SceneView backing
   view smoke proving application-dispatched orbit and magnify controls reach
   the camera. Hosted GTK `NSView` drawing areas now synthesize AppKit pointer
   enter/move/exit, cursor rect, left/right drag, scroll-wheel, and
   magnify/pinch events from native GTK controllers before routing them through
   `NSApplication` when a window/first-responder path exists, or directly to the
   hosted view when the SwiftUI representable has no synthetic `NSWindow`.
   `GtkGestureZoom` is installed in capture phase with a multitouch-safe CGTK
   shim helper and dispatches AppKit `.magnify` events with incremental
   `NSEvent.magnification` deltas.

   Pixel parity is intentionally scoped to deterministic software-renderer
   envelopes, not GPU SceneKit parity. Native macOS `SCNRenderer.snapshot`
   references for the canonical sphere, triangle, and side-camera scenes are
   pinned in `SceneKitRendererTests` and the runnable
   `quill-scenekit-render-smoke` executable. The software renderer now keeps a
   per-pixel depth buffer for opaque overlap, honors `SCNNode.renderingOrder`
   plus `SCNMaterial.readsFromDepthBuffer`/`writesToDepthBuffer`, and the
   source/smoke gates include an intersecting-triangle scene with sampled
   pixels on both sides of the depth crossover. The smoke gate checks rendered
   area, dominant color, screen bounds, explicit clipping, camera control,
   hit-test checks, and z-buffered overlap, plus `SCNAction`
   completion-handler delivery, then runs an Xvfb GTK `SceneView` render smoke.

GPU honesty: SceneKit on QuillOS starts as a software rasterizer over the
existing 2D paint layer. That is enough for these apps' scene scale; a GL/
Vulkan backend is a later, separate decision — do not promise GPU parity.

## Status

- [x] Targets wired, presence/env-gated; fetch arms + meta-arm added
- [x] Fixtures authored (faithful macOS SwiftUI+SceneKit source)
- [x] Inert RealityKit shim module (Euclid Example's RealityKitViewController)
- [x] Rung 1: Euclid + ShapeScript lib/CLI green on Linux (CLI renders .shape → .stl)
- [x] Rung 2 (fixtures): SceneKit scene-graph shim authored with vector value/zero/make helpers, node parenting/traversal/replacement/cloning/local and world transforms/scale/orientation/SIMD vector and direction aliases/direction vectors/presentation/bounding boxes; QuillSolarSystem + QuillMoleculeViewer compile
- [x] Rung 2b (interop surface): Mesh⇄SCNGeometry marshalling + CoreGraphics CGPoint/CGSize/CGPath/CF surface authored; Euclid's full interop verified 727→0; CGPath transform/curve recording, bounds/current-point accessors, containment, CGContext current-path introspection, and CGContext path forwarding now directly tested
- [x] Rung 2c (app-tier enablement): enable Euclid interop + fix ShapeScript interop + QuillEuclidExample + QuillShapeScriptViewer compile (all-at-once)
- [x] Rung 3: fixtures render (GTK screenshot gate)
- [x] Rung 4: QuillEuclidExample renders real Euclid mesh data
- [x] Rung 5: QuillShapeScriptViewer builds and launch-smokes
- [x] Rung 6: pixel parity / live camera controls (hit-testing, camera orientation, explicit camera clipping, per-pixel z-buffered intersecting geometry, deterministic camera movement, primitive/sequence/group/repeating action stepping, AppKit-pump-dispatched camera movement, GTK pointer/drag/scroll/magnify delivery, and Apple SceneKit software-renderer golden envelopes are smoke/source-gated)
