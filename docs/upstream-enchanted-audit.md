# Upstream Enchanted Port Audit

Audit source: <https://github.com/gluonfield/enchanted.git>  
Commit: `2f82ee2` (`2025-03-18`, `feat: colour adjustments (#194)`)  
Swift files: 87

## Current Answer

A direct `import SwiftUI` to `import QuillUI` replacement is not enough yet. The broad chat UI shape is close enough to reuse, but upstream Enchanted still has Apple-only service layers and SwiftData models that need adapters.

The lowest-change strategy is:

1. Keep upstream UI files structurally intact.
2. Compile the macOS desktop chat path on Linux by widening selected `#if os(macOS)` gates to `#if os(macOS) || os(Linux)`.
3. Replace SwiftData imports/models/service with QuillData where possible, using `EnchantedModelContext` only as the current app-specific bridge until the reusable layer covers the full surface.
4. Stub or hide Apple-only speech, hotkey, accessibility, menu-bar, and clipboard services on Linux.
5. Keep improving QuillUI shims only for UI APIs that can degrade cleanly.

## Covered By QuillUI

- `NavigationSplitView`, `NavigationSplitViewVisibility`
- `@FocusState`, `.focused(...)`
- `ScrollViewReader`
- `LazyVGrid`, `GridItem`
- `contextMenu`, `confirmationDialog`, `toolbar`, `ToolbarItem`
- `openURL`, `presentationMode`, `ColorScheme`
- `TextField(axis:)`, `Binding.animation(...)`, `Button(role:)`
- Image construction from `Data`
- `Color(rgba:)`, `Color(light:dark:)`
- symbolic image rendering fallbacks:
  - `.symbolRenderingMode(...)`
  - `.imageScale(...)` after generic view styling
- Third-party rendering modules now covered by Linux compatibility targets:
  - `OllamaKit` model listing, reachability checks, bearer-token requests, and newline-streaming chat responses used by Enchanted's Ollama service and prompt completions
  - `AsyncAlgorithms.AsyncTimerSequence` used by the prompt panel manager
  - `Carbon` import shell used by the prompt panel path
  - `MarkdownUI` theme/style builders, `Markdown`, `CodeBlockConfiguration`, relative spacing/padding/frame helpers, table styles, and code syntax highlighter hooks
  - `Splash` themes, token colors, `SyntaxHighlighter`, `OutputFormat`, and `OutputBuilder`
- Linux-safe file/drop compatibility shims for upstream Enchanted's composer surface:
  - `UTType` values for `.image`, `.png`, `.jpeg`, `.tiff`
  - `NSItemProvider.loadDataRepresentation(...)`
  - `.fileImporter(...)`
  - `.onDrop(of:isTargeted:perform:)`
  - `.allowsHitTesting(...)`
  - `.contentShape(...)`
  - `.foregroundStyle(...)` fallback for gradients and symbolic styles
  - `.symbolEffect(...)`
  - `.renderingMode(...)`
  - `ButtonStyle`, `PlainButtonStyle`
  - `.regularMaterial`

## Remaining Blockers

These are not good QuillUI shims because they are app behavior or Apple frameworks:

- `SwiftData`: 10 importing files, plus `@Model`, `ModelContainer`, `ModelContext`, `FetchDescriptor`, `SortDescriptor`, and `#Predicate`.
- Apple UI/framework services that still need native Linux behavior, even when imports compile through module shells:
  - `AppKit`: 4 importing files
  - `UIKit`: 3 importing files
  - `AVFoundation`: 4 importing files
  - `Speech`: 1 importing file
  - `KeyboardShortcuts`: 2 importing files
  - `Magnet`: 2 importing files
  - `PhotosUI`: 1 importing file

`ActivityIndicatorView`, `MarkdownUI`, `Splash`, `Vortex`, `WrappingHStack`, `OllamaKit`, `AsyncAlgorithms`, and `Carbon` are no longer compile blockers for Enchanted's currently audited usage. The UI/rendering shims intentionally render simplified native-looking Linux views instead of exact package visual parity.

## Reproduce

Run:

```sh
scripts/audit-upstream-enchanted.sh
```

The script keeps the upstream checkout in `.upstream/enchanted`, which is ignored by git.
