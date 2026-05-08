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
- `--app-type` is the Swift `App` type passed to `GTK4Backend().run(...)`.
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

The Linux visual smoke script can screenshot either root SwiftPM products or
the generated Quill Chat app product:

```bash
scripts/linux-gtk-visual-check.sh .qa/quill-chat-linux-generated-gtk.png quill-chat-linux
```

For `quill-chat-linux`, the script builds through the generic app builder,
resolves the generated package executable, captures an Xvfb screenshot, and
checks both brightness and pixel variation so blank white windows fail.
