# Repository Boundaries

QuillUI is a compatibility project, an app-porting lab, and a conformance
matrix in one repository. That is useful while the project is young, but only if
each kind of code has a clear boundary.

The public project should be described as:

> QuillUI brings Apple Swift app source to Linux with source-level compatibility
> and macOS-quality rendering.

Avoid describing the project as an Apple platform clone, macOS clone, emulator,
or binary compatibility layer. QuillUI rebuilds source, maps API contracts, and
uses explicit Linux backends for platform behavior.

## Zones

| Zone | Paths | Purpose | Boundary Rule |
| --- | --- | --- | --- |
| Core compatibility libraries | `Sources/QuillUI`, `Sources/QuillData`, `Sources/QuillKit`, `Sources/QuillFoundation`, `Sources/QuillAppKit`, `Sources/QuillUIKit`, framework-named shim targets | Reusable API surface for many Apple Swift apps. | App-specific fixes must move here only when they are general and tested by at least one source-contract test. |
| Rendering and backend libraries | `Sources/QuillPaint*`, `Sources/BackendQt`, `Sources/QuillUIGtk`, `Sources/QuillUIQt`, C bridge targets | Linux rendering, native host integration, screenshotable behavior. | Backend details must not leak into app profiles or the SwiftUI facade unless expressed as a backend-neutral capability. |
| Source lowering and build tooling | `Sources/QuillSourceLowering`, `Sources/quill-*`, `scripts/build-swiftui-linux-app.sh`, `scripts/generate-swiftui-linux-package.sh`, `scripts/profiles/*` | Generated-copy conversion from Apple app source to Linux SwiftPM builds. | Generic lowering belongs in SwiftSyntax tooling; app profiles keep only app source-shape rules and tiny templates. |
| Target app ports | `Sources/QuillEnchanted*`, `Sources/QuillWireGuard*`, `Sources/QuillNetNewsWire*`, `Sources/QuillIceCubes*`, `Sources/QuillCodeEdit*`, `Sources/QuillSignal*`, `Sources/QuillTelegram*`, `Sources/QuillIINA*` | Real-app pressure tests and demos. | App targets are conformance clients. They should not become the place where framework behavior is implemented. |
| Upstream and vendored code | `.upstream/*`, `vendor/apps/*`, `third_party/*` | Real source inputs and pinned external compatibility runtimes. | Vendored code is either fetched or pinned intentionally. Changes need a clear upstreaming or patch-management story. |
| Tests and fixtures | `Tests/*`, `Tests/Fixtures/*` | Contract, fuzz, golden, and smoke evidence. | A compatibility claim is not complete until a test pins it. Prefer app-facing tests over broad unverified surface area. |
| Documentation | `README.md`, `docs/*`, `docs/site/*` | Public positioning, internal field guides, release plans, coverage ledgers. | Public docs use compatibility language; internal docs may be more direct but must mark incomplete/fallback behavior honestly. |
| Agent and workflow infrastructure | `.loom/*`, `.claude/*`, `.swarm/*` | Local automation and multi-agent workflow support. | This is not part of the QuillUI library surface. It must not be imported by products, referenced by package targets, or required for a consumer build. |

## Dependency Rules

- Core libraries may depend on Swift, Foundation, declared package dependencies,
  and backend-neutral Quill libraries.
- App ports may depend on core libraries, source-lowered upstream code, and
  app-specific fixture targets.
- Profiles may call shared scripts, but shared scripts must not know app names
  except through explicit profile arguments. New app investigations should start
  with `generic-swiftui`; create an app-named profile only for source-shape
  exceptions that cannot be expressed as reusable QuillUI/QuillKit/QuillData
  behavior.
- Backend targets may depend on C bridges and rendering libraries, but app code
  should see a QuillUI/QuillKit capability rather than raw GTK/Qt details.
- Agent infrastructure is operational tooling only. Treat it like CI/devops,
  not project source.

## Release Discipline

The repository can keep many app targets, but only one app should be the release
focus at a time. The current focus is Enchanted / Quill Chat:

1. Make Enchanted credible as an installable Linux app.
2. Move every generally useful Enchanted fix into reusable Quill libraries.
3. Keep WireGuard, NetNewsWire, IceCubes, CodeEdit, Signal, Telegram, and IINA
   as conformance clients unless they directly unblock the Enchanted release.
4. After Enchanted ships, promote NetNewsWire as the next public proof point.

## Packaging Direction

The public package should eventually separate into:

- `QuillUI`: reusable compatibility libraries, renderers, source lowering, and
  tests.
- `QuillUIApps`: demo and conformance app ports.
- `QuillUIAutomation`: optional agent/workflow infrastructure, or a separate
  development-only plugin.

For now, this document is the contract that keeps the monorepo legible while the
project is still discovering the right APIs.
