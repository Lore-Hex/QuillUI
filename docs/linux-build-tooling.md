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
- `--profile` selects source lowering. Today the implemented profile is
  `enchanted-full-source`.

The profile boundary matters. QuillUI should become a broadly reusable
compatibility library, but source lowering is not universal yet. Different
apps need different macro, platform, package, and service bridges. The generic
builder gives those future profiles one stable CLI contract instead of adding a
new app-specific build script for every target.

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
