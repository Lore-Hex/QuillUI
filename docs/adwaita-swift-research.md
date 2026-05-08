# Adwaita For Swift / AparokshaUI Research Notes

Adwaita for Swift is a declarative Swift framework for native GNOME apps using GTK4 and libadwaita. It is highly relevant to QuillUI because it already provides the Linux-native UI backend we were approximating through SwiftOpenUI/GTK.

Primary references:

- https://www.swift.org/blog/adwaita-swift/
- https://www.aparoksha.dev/backends/adwaita/
- https://git.aparoksha.dev/aparoksha/adwaita-swift
- https://git.aparoksha.dev/aparoksha/adwaita-swift/src/branch/main/README.md
- https://git.aparoksha.dev/aparoksha/adwaita-swift/src/branch/main/Package.swift
- https://git.aparoksha.dev/aparoksha/adwaita-swift/src/branch/main/LICENSE.md
- https://david.aparoksha.dev/blog/nativecrossplatform/

## What It Is

- A SwiftUI-style declarative framework for GNOME apps.
- Renders through native GTK4 and libadwaita.
- Part of the broader Aparoksha project, which aims at native cross-platform Swift UI through independent backends.
- MIT licensed.
- Active as of 2026; the package manifest was updated in February 2026.
- Uses SwiftPM and a `CAdw` system library target with `pkg-config: libadwaita-1`.
- Depends on the Aparoksha `Meta` layer and `MetaSQLite`.
- Has code generation for GTK/libadwaita widget bindings from introspection data.

## Why It Matters

Adwaita for Swift is likely the strongest Linux desktop foundation for QuillUI. It gives us:

- Native GNOME/libadwaita visuals.
- Real GTK4 widgets.
- A declarative Swift view model.
- State and binding primitives.
- Window/dialog/menu/form primitives.
- Flatpak/Flathub-oriented distribution guidance.
- A mature enough widget generation system to avoid hand-writing every GTK binding.

This is better aligned with “beautiful Swift app on elementary/GNOME Linux” than a generic minimal SwiftUI clone.

## Fit With QuillUI

QuillUI should not simply become Adwaita for Swift. The API is similar to SwiftUI, but not source-compatible:

- Adwaita views use `var view: Body`, while SwiftUI uses `var body: some View`.
- Adwaita’s controls and modifiers are GNOME-shaped, not exact SwiftUI names.
- App/window setup differs.
- It targets GNOME/libadwaita conventions first, while QuillUI’s goal is SwiftUI source compatibility for existing apps.

The right layering is:

1. **QuillUI compatibility facade**
   - App code imports `QuillUI`.
   - QuillUI keeps SwiftUI-like names: `View`, `body`, `VStack`, `Button`, `Text`, modifiers, property wrappers.

2. **QuillUI Adwaita backend**
   - On Linux, QuillUI lowers supported SwiftUI-like constructs into Adwaita/Aparoksha widgets.
   - Unsupported constructs get explicit diagnostics or documented fallback paths.

3. **Adwaita escape hatch**
   - QuillUI exposes a way to embed raw Adwaita/GTK widgets for features SwiftUI does not model well.

## How Much Can We Use?

High value:

- The native GTK4/libadwaita backend.
- Generated widget bindings.
- Window, dialog, menu, form, header bar, list, toolbar, and toast widgets.
- Flatpak development/distribution patterns.
- The Meta declarative update layer and diff/update ideas.

Medium value:

- State/binding implementation ideas.
- Aparoksha’s cross-platform backend split.
- Platform-specific view extension patterns.

Low direct value:

- As a drop-in import replacement for SwiftUI. The API shape is close but not close enough for existing SwiftUI apps without a QuillUI compatibility facade.

## Recommended Next Step

Add an experimental QuillUI backend target:

- `QuillUIAdwaita`
- Linux-only dependency on `adwaita-swift`
- A small adapter for `Text`, `Button`, `VStack`, `HStack`, `ScrollView`, `List`, `TextField`, and window setup.
- A sample `quill-enchanted-adwaita` executable that uses the same Enchanted model but renders through Adwaita.

Keep the current SwiftOpenUI backend while this is evaluated. The migration should be measured by:

- How much Enchanted-specific UI code can be deleted.
- Visual quality compared with the current GTK screenshot.
- Whether dependency setup works cleanly inside the Lima Ubuntu VM.
- Whether elementary OS/GNOME styling looks materially better.

## Risks

- Adwaita for Swift is GNOME/libadwaita-first. elementary OS uses GTK but has its own design language; libadwaita apps can still look GNOME-ish rather than elementary-native.
- The package is active but relatively young and hosted on Gitea, not GitHub; supply-chain and CI assumptions need to be explicit.
- It uses branch dependencies for core Aparoksha packages in current `Package.swift`, which may make reproducible builds harder until we pin revisions.
- It does not solve SwiftData. QuillData remains necessary.
- It does not solve exact SwiftUI source compatibility by itself.

## Strategic Conclusion

Adwaita for Swift is probably the missing backend piece. QuillUI should become the SwiftUI compatibility layer on top of it, not compete with it at the GTK/libadwaita widget level.
