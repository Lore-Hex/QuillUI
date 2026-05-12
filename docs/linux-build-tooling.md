# Linux App Build Tooling

QuillUI's app build entry point is `scripts/build-swiftui-linux-app.sh`.
It is the generic interface for building a SwiftUI-shaped app tree into a Linux
GTK executable without editing the app source.

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
- `--app-type` is the Swift `App` type launched through `QuillApp.run(...)`.
- `--product-name` controls the generated executable name.
- `--workdir` controls where generated source and SwiftPM build state go.
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
compatibility products, optionally generating the GTK `@main`, patching the
pinned SwiftOpenUI checkout, and running `swift build`.

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
  build and GTK smoke jobs.
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
- `QUILLUI_GENERATED_INCLUDE_GTK_BACKEND`
- `QUILLUI_GENERATED_APP_ENTRY_TYPE`
- `QUILLUI_GENERATED_APP_MAIN_TYPE`
- `QUILLUI_GENERATED_REPORT_LABEL`

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

The Linux backend visual smoke script can screenshot either root SwiftPM products or
the generated Quill Chat app product:

```bash
scripts/linux-backend-visual-check.sh .qa/quill-chat-linux-generated-gtk.png quill-chat-linux
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
The strict path also sets `QUILLUI_GTK_DEFAULT_WINDOW_WIDTH` and
`QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT`; the SwiftOpenUI GTK checkout patch honors
those values for automatic window sizing. New GTK/Qt parity scripts should call
`scripts/linux-backend-visual-check.sh` and use the `QUILLUI_BACKEND_*` names
for visual checks. The runner maps them to the older `QUILLUI_GTK_*`
environment contract for compatibility, and `scripts/linux-gtk-visual-check.sh`
remains as a thin compatibility shim.

Native backend interaction smoke is separate from Playwright because these apps
are Linux desktop executables, not web pages. The interaction check builds a
small Linux-only QuillUI sample, starts it under Xvfb, clicks a native window
with `xdotool`, captures the opened window, and verifies that Swift state
changed and the view tree repainted. New GTK/Qt checks should use
`scripts/linux-backend-interaction-check.sh`; the older
`scripts/linux-gtk-interaction-check.sh` path is kept as a compatibility shim.

```bash
scripts/linux-backend-interaction-check.sh .qa/quill-gtk-interaction-smoke-open.png quill-gtk-interaction-smoke
```

The Qt launch target uses the same interaction surface through
`QuillInteractionSmokeSupport`, with `QuillUIQt` owning the backend-specific
launcher. Until the native Qt renderer is linked, the CI smoke executes through
the platform fallback runtime so the target graph and app scene stay buildable:

```bash
scripts/linux-backend-interaction-check.sh .qa/quill-qt-interaction-smoke-open.png quill-qt-interaction-smoke
```

It can also exercise the generated Quill Chat toolbar menu:

```bash
scripts/linux-backend-interaction-check.sh .qa/quill-chat-linux-toolbar-menu-gtk.png quill-chat-linux
```

That path builds through the same generic app builder as the visual smoke,
clicks the generated options menu in the top-right toolbar, and verifies that
the GTK menu surface appears below the toolbar.

The opt-in `ImageRenderer` offscreen path also runs under Xvfb. It is kept
separate from the normal test suite because it intentionally maps a temporary
GTK window to get a real render node:

```bash
GTK_A11Y=none GSK_RENDERER=cairo QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1 xvfb-run -a scripts/linux-swift-test.sh --scratch-path .build-linux-offscreen --filter imageRendererOffscreenPipelineProducesRealPNG
```

Use `scripts/linux-swift-test.sh` instead of calling `swift test` directly on
Linux. The wrapper applies the pinned SwiftOpenUI/OpenCombine checkout patch to
the selected scratch directory before invoking SwiftPM, which keeps fresh CI
scratch paths consistent with the GTK build scripts:

```bash
scripts/linux-swift-test.sh --scratch-path .build-linux
scripts/linux-swift-test.sh --scratch-path .build-linux --filter QuillDataSourceLoweringTests
```

GitHub Actions runs the public Linux path in `.github/workflows/linux-ci.yml`.
It uses a Swift Linux container, installs GTK/Xvfb/ImageMagick/xdotool
dependencies, fetches the upstream Enchanted fixture into `.upstream/enchanted`,
runs Swift tests, compiles the generated upstream app, and uploads GTK
screenshot/log artifacts from the visual and interaction smokes.
