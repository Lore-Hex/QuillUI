# Linux App Build Tooling

QuillUI's app build entry point is `scripts/build-swiftui-linux-app.sh`.
It is the generic interface for building a SwiftUI-shaped app tree into a Linux
backend-selected executable without editing the app source.

Example:

```bash
scripts/build-swiftui-linux-app.sh \
  --profile enchanted-full-source \
  --source-dir /path/to/App/Sources \
  --app-type EnchantedApp \
  --product-name quill-chat-linux
```

The command intentionally separates the generic build contract from source
lowering profiles:

- `--source-dir` points at the app source tree.
- `--app-type` is the Swift `App` type launched through the generated
  QuillUI entry.
- `--product-name` controls the generated executable name.
- `--workdir` controls where generated source and SwiftPM build state go.
- `--backend-facade` optionally compiles the generated entry through
  `QuillUIGtk` or `QuillUIQt` instead of the backend-neutral `QuillUI`
  launcher.
- `--profile` selects a source-lowering script from `scripts/profiles/`.
- `--list-profiles` prints installed profiles.

The profile boundary matters. QuillUI should become a broadly reusable
compatibility library, but source lowering is not universal yet. Different
apps need different macro, platform, package, and service bridges. The generic
builder gives those future profiles one stable CLI contract instead of adding a
new app-specific build script for every target.

Profiles are plugin-style shell entry points. The builder passes them a stable
environment contract:

- `QUILLUI_PROFILE_SOURCE_DIR`
- `QUILLUI_PROFILE_WORKDIR`
- `QUILLUI_PROFILE_MODE`
- `QUILLUI_PROFILE_PRODUCT_NAME`
- `QUILLUI_PROFILE_PACKAGE_NAME`
- `QUILLUI_PROFILE_TARGET_NAME`
- `QUILLUI_PROFILE_ENTRY_TYPE`
- `QUILLUI_PROFILE_MAIN_TYPE`

Profiles that produce a lowered Swift source tree should delegate package
assembly to `scripts/generate-swiftui-linux-package.sh`. That helper owns the
reusable SwiftPM package shape: copying lowered sources, adding the QuillUI
compatibility products, optionally generating the backend-selected `@main`,
patching the pinned SwiftOpenUI checkout, and running `swift build`.

Profiles can also reuse the generic source-lowering helpers before package
assembly:

- `scripts/lower-swiftdata-for-quilldata.sh` copies an app tree and lowers
  SwiftData model syntax to QuillData-compatible source.
- `scripts/lower-swiftui-source-for-linux.sh` applies conservative in-place
  cleanup for generated SwiftUI source, including `@main`, previews,
  `@Observable`, `@MainActor`, and `os(macOS)` platform gates.
- `scripts/ensure-swift-imports.sh` lets profiles declare compatibility module
  imports for optional Swift files without open-coding one-off source rewrites.
- `scripts/install-profile-templates.sh` copies profile-owned replacement files
  into the lowered tree so large generated Swift files live as reviewable
  templates instead of shell heredocs.
- `scripts/apply-profile-rewrites.sh` applies reviewable profile rewrite rules:
  `__all__.pl` runs across every Swift file and `*.swift.pl` rules map to
  matching source paths.
- `scripts/truncate-profile-files.sh` blanks optional profile-listed files that
  are replaced by QuillKit/QuillUI compatibility implementations.
- `scripts/audit-profile-budget.sh` checks app-lowering profile shell glue
  against a small line-count budget; CI runs this before the heavier Linux
  build and backend smoke jobs.
- `scripts/generate-hashable-identity-shims.sh` emits small generated Swift
  extensions that make lowered model classes `Hashable`/`Equatable` by stable
  identity properties, with optional `Identifiable.id` aliases for models whose
  Apple macro originally synthesized the identity.

Profile-specific lowering phases should live next to the profile entry point
under `scripts/profiles/<profile-name>/`. That keeps app source-shape fixes
discoverable without growing the generic builder or the profile wrapper. The
current Enchanted/Quill Chat profile uses
`scripts/profiles/enchanted-full-source/lower-profile-source.sh` for those
rules.

The package helper takes this stable environment contract:

- `QUILLUI_GENERATED_SOURCES_DIR`
- `QUILLUI_GENERATED_SOURCE_COUNT_DIR`
- `QUILLUI_GENERATED_WORKDIR`
- `QUILLUI_GENERATED_PACKAGE_DIR`
- `QUILLUI_GENERATED_PACKAGE_NAME`
- `QUILLUI_GENERATED_PRODUCT_NAME`
- `QUILLUI_GENERATED_TARGET_NAME`
- `QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY`
- `QUILLUI_GENERATED_BACKEND_FACADE`
- `QUILLUI_GENERATED_APP_ENTRY_TYPE`
- `QUILLUI_GENERATED_APP_MAIN_TYPE`
- `QUILLUI_GENERATED_REPORT_LABEL`

`QUILLUI_GENERATED_INCLUDE_GTK_BACKEND` remains accepted by the package helper
as a compatibility alias for older profile callers, and
`QUILLUI_GENERATED_INCLUDE_QT_BACKEND` is accepted for backend-scoped Qt
profiles. New profiles should use the backend-neutral entry flag.
Use `QUILLUI_GENERATED_BACKEND_FACADE=gtk` or `qt` only when the generated
package should import and link the backend facade product directly; ordinary
backend smoke/profile parity should continue to request the runtime backend
with `QUILLUI_BACKEND`.

Reusable fallback behavior should live in library targets, not in profiles.
The current `enchanted-full-source` profile keeps only app/source-shape wiring
for accessibility, hotkeys, updater, panel, and USB launcher names; the Linux
fallback implementations live in `QuillKit` and `QuillUI`.

`scripts/build-quill-chat-linux.sh` is now only a convenience wrapper:

```bash
scripts/build-quill-chat-linux.sh
```

It supplies Quill Chat's source directory, app type, product name, and the
current `enchanted-full-source` profile to the generic builder.

The Linux backend visual smoke script can screenshot either root SwiftPM
products or generated app products. CI drives matrix jobs through
`scripts/run-linux-backend-smoke-matrix.sh`, which reads a
`PRODUCT<TAB>BACKEND` roster from `scripts/quillui-backend-products.sh` and
then calls the single-row visual or interaction runner with the requested
backend as an explicit positional argument. The output template must include
`{product}` and `{backend}` so GTK/Qt artifacts never overwrite each other.

Generated products use the same GTK/Qt requested-backend matrix as the root app
shells:

```bash
scripts/run-linux-backend-smoke-matrix.sh \
  --skip-repeated-products \
  visual \
  generated-app-matrix \
  '.qa/{product}-generated-{backend}.png'
```

Root SwiftPM app products use `app-matrix`. The executable is backend-neutral,
so CI builds each product once and uses `QUILLUI_BACKEND_SKIP_BUILD=1` for
later backend rows:

```bash
scripts/run-linux-backend-smoke-matrix.sh \
  --skip-repeated-products \
  visual \
  app-matrix \
  '.qa/{product}-{backend}.png'
```

For `quill-chat-linux`, the script builds through the generic app builder,
resolves the generated package executable, captures an Xvfb screenshot, checks
both brightness and pixel variation so blank white windows fail, and verifies
Quill Chat-specific layout landmarks such as the sidebar width, header divider,
prompt cards, and composer width.

There is also an opt-in strict reference pass for the large macOS Quill Chat
window screenshot. It resizes the Xvfb window to the same reference frame and
verifies the Mac-derived landmarks instead of the older compact smoke layout:

```bash
QUILLUI_BACKEND_MAC_REFERENCE=1 \
  scripts/linux-backend-visual-check.sh .qa/quill-chat-linux-mac-reference.png quill-chat-linux
```

The current Mac reference is `2228x1498` with a `602px` sidebar, `102px`
header, four prompt cards at `730-1057`, `1088-1415`, `1445-1772`, and
`1803-2129`, a `1524px` unreachable alert, and a `1510px` composer. This
strict pass is allowed to fail while renderer parity is still being closed; it
exists so the remaining gap is measured against the real app, not a prototype.
The strict path sets backend-neutral reference window values and exports both
`QUILLUI_GTK_*` and `QUILLUI_QT_*` compatibility aliases. The SwiftOpenUI GTK
checkout patch honors the GTK values for automatic window sizing. New GTK/Qt
parity scripts should use `scripts/run-linux-backend-smoke-matrix.sh` for
matrix jobs, call `scripts/linux-backend-visual-check.sh` for a single product
row, and use the `QUILLUI_BACKEND_*` names for visual checks. Matrix jobs pass
the requested backend as the runner's explicit positional backend argument so
the selected backend travels with each row. The runner canonicalizes supported
backend aliases such as `gtk4`, `qt6`, and `swift-ui` before mapping
backend-neutral values to the older `QUILLUI_GTK_*` environment contract and to
scoped `QUILLUI_QT_*` controls for compatibility, and
`scripts/linux-gtk-visual-check.sh` remains as a thin compatibility shim.

The backend visual and interaction runners both source
`scripts/quillui-linux-backend-smoke-lib.sh` for apt package setup, root
SwiftPM/generated Quill Chat executable resolution, and deterministic Quill
Chat reference-data seeding. Backend-specific checks should extend that helper
instead of copying GTK or Qt build glue into another smoke script.

Native backend interaction smoke is separate from Playwright because these apps
are Linux desktop executables, not web pages. The interaction check builds a
small Linux-only QuillUI sample, starts it under Xvfb, clicks a native window
with `xdotool`, captures the opened window, and verifies that Swift state
changed and the view tree repainted. New GTK/Qt checks should use
`scripts/linux-backend-interaction-check.sh`; the older
`scripts/linux-gtk-interaction-check.sh` path is kept as a compatibility shim.
Like the visual runner, the interaction runner accepts backend-neutral
`QUILLUI_BACKEND_*` controls, including `QUILLUI_BACKEND_MAC_REFERENCE`,
`QUILLUI_BACKEND_SCREEN_SIZE`, and `QUILLUI_BACKEND_INTERACTION_SCREEN_SIZE`,
then maps them to the legacy `QUILLUI_GTK_*` names and scoped `QUILLUI_QT_*`
names for compatibility.
Display controls such as `QUILLUI_BACKEND_VISUAL_DISPLAY`,
`QUILLUI_BACKEND_INTERACTION_DISPLAY`, and `QUILLUI_BACKEND_PROFILE_DISPLAY`
accept either an X display id (`:95`) or a numeric display (`95`); the runners
normalize both forms before starting Xvfb.
`QUILLUI_BACKEND_LAYOUT_DEBUG` is also backend-neutral: visual, interaction,
and profile launches forward it to both the legacy GTK and scoped Qt aliases so
layout diagnostics behave the same across every runner.
The visual, interaction, and profile runners also share the same Xvfb screen
selection helper, so Mac-reference Quill Chat runs use the same seeded state and
reference window dimensions across screenshot and performance checks.

```bash
scripts/linux-backend-interaction-check.sh .qa/quill-gtk-interaction-smoke-open.png quill-gtk-interaction-smoke
```

The Qt launch target uses the same interaction surface through
`QuillInteractionSmokeSupport`, with `QuillUIQt` owning the backend-specific
launcher. Until the native Qt renderer is linked, the CI smoke executes through
the platform fallback runtime so the target graph and app scene stay buildable:
when Qt becomes a native Linux runtime, it must add an explicit
`QuillLinuxRuntimeHost` case before the registry marks Qt as native, so CI
cannot silently report Qt while running the GTK host.

```bash
scripts/linux-backend-interaction-check.sh .qa/quill-qt-interaction-smoke-open.png quill-qt-interaction-smoke
```

The GTK and Qt launch fixtures also run through the backend visual runner from
the shared smoke matrix, and through a mode-aware interaction matrix that drives
the root button, nested controls, and sheet presentations with one product build
per backend facade:

```bash
scripts/run-linux-backend-smoke-matrix.sh \
  visual \
  smoke-matrix \
  '.qa/{product}-visual-{backend}.png'

scripts/run-linux-backend-smoke-matrix.sh \
  --skip-repeated-products \
  interaction \
  smoke-interaction-matrix \
  '.qa/{product}-{mode}-{backend}.png'
```

The root app interaction matrix uses the same app roster as the visual smoke.
Run it after the visual matrix so the executables already built under
`.build-linux` can be reused:

```bash
QUILLUI_BACKEND_SKIP_BUILD=1 \
  scripts/run-linux-backend-smoke-matrix.sh \
    interaction \
    interaction-matrix \
    '.qa/{product}-interaction-{backend}.png'
```

The generated Quill Chat toolbar menu uses the generated app backend matrix:

```bash
QUILLUI_BACKEND_SKIP_BUILD=1 \
  scripts/run-linux-backend-smoke-matrix.sh \
    interaction \
    generated-app-matrix \
    '.qa/{product}-toolbar-menu-{backend}.png'
```

That path builds through the same generic app builder as the visual smoke,
clicks the generated options menu in the top-right toolbar, and verifies that
the menu surface appears below the toolbar.

Profile baselines use the composed `profile-matrix` roster so the same budget
check covers each user-facing app and generated external app under every
requested backend plus the backend launch fixtures. The roster emits
`PRODUCT<TAB>BACKEND` rows, and the CSV runner canonicalizes backend aliases
before it launches the profiler:

```bash
scripts/run-linux-backend-profile-csv.sh --matrix profile-matrix /tmp/quillui-profile.csv
```

The CSV schema stays product-first for the budget checker but includes explicit
`requested_backend` and `runtime_backend` columns. This keeps GTK and Qt rows
comparable while making it clear that Qt-requested Linux rows currently execute
through the GTK fallback runtime until the native Qt renderer is linked.
When consecutive rows reuse the same executable product, the CSV runner sets
`QUILLUI_BACKEND_SKIP_BUILD=1` after the first successful profile pass so GTK
and Qt budget rows do not repeat the same SwiftPM build work.

The opt-in `ImageRenderer` offscreen path also runs under Xvfb. It is kept
separate from the normal test suite because it intentionally maps a temporary
GTK window to get a real render node:

```bash
GTK_A11Y=none GSK_RENDERER=cairo QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1 xvfb-run -a scripts/linux-swift-test.sh --scratch-path .build-linux-offscreen --filter imageRendererOffscreenPipelineProducesRealPNG
```

Use `scripts/linux-swift-test.sh` instead of calling `swift test` directly on
Linux. The wrapper applies the pinned SwiftOpenUI/OpenCombine checkout patch to
the selected scratch directory before invoking SwiftPM, which keeps fresh CI
scratch paths consistent with the backend build scripts:

```bash
scripts/linux-swift-test.sh --scratch-path .build-linux
scripts/linux-swift-test.sh --scratch-path .build-linux --filter QuillDataSourceLoweringTests
```

GitHub Actions runs the public Linux path in `.github/workflows/linux-ci.yml`.
It uses a Swift Linux container, installs GTK/Xvfb/ImageMagick/xdotool
dependencies, fetches the upstream Enchanted fixture into `.upstream/enchanted`,
runs Swift tests, compiles the generated upstream app, and uploads backend
screenshot/log artifacts from the visual and interaction smokes.

For a full local Linux validation pass, run:

```bash
scripts/linux-backend-check.sh
```

That script builds each backend app executable once, then smoke-launches the
full app/backend matrix plus the GTK and Qt backend launch fixtures under Xvfb.

The legacy `scripts/linux-gtk-check.sh` path remains as a compatibility shim.
