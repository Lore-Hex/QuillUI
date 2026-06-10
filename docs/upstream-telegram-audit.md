# Upstream Telegram Swift Port Audit

Telegram Swift is not a SwiftUI app. It is a large AppKit/Cocoa macOS
application with an Xcode workspace, 1,265 Swift files in the current upstream
checkout, 45 SwiftPM package manifests, Objective-C/C/C++ package islands, and
deep Telegram protocol/media dependencies.

The first QuillUI milestone is therefore not a full UI render. It is a
repeatable source checkout plus Linux compile ratchet:

- `scripts/fetch-upstream.sh telegram` fetches `overtake/TelegramSwift` into
  `.upstream/telegram-swift`.
- `scripts/quillui-telegram-source.sh` resolves an explicit
  `QUILLUI_APP_SOURCE_DIR`, `TELEGRAM_SWIFT_SOURCE_DIR`, `TELEGRAM_SOURCE_DIR`,
  or the default `.upstream/telegram-swift`.
- `QuillObjCCompatibility` provides Apple-style Objective-C include paths
  (`<Foundation/Foundation.h>`, `<AppKit/AppKit.h>`, `<Cocoa/Cocoa.h>`) so
  mixed Objective-C package islands can compile without Telegram source edits.
- `scripts/generated-telegram-package-check.sh` now compiles all 49 SwiftPM
  package manifests in the current Telegram checkout on Linux, including the
  central UI/media packages `TGUIKit`, `TelegramMedia`, `TextRecognizing`,
  `PrivateCallScreen`, `InputView`, and `TGVideoCameraMovie`, plus the
  telegram-ios submodule packages `MediaPlayer`, `TelegramAudio`,
  `YuvConversion`, and `libphonenumber` in the default compile set
  (53 packages total).
- `Sources/QuillTelegramBuildOverlays` provides generic generated build overlays
  for Swift-only ambient Apple symbols that cannot be supplied by C headers.
  `ApiCredentials` uses this for Security/CommonCrypto and app-group container
  fallbacks, `Strings` uses it for swift-corelibs word-enumeration fallbacks
  (its CoreText glyph-count path resolves to the shared CoreText shim product),
  and `TelegramSystem` uses it for a Linux `sysctlbyname` fallback, while
  leaving the upstream checkout untouched. AppKit/Cocoa-shaped source compiles
  against the QuillAppKit/QuillKit shims exported as Apple-named products.
- The generated package check builds from a mirrored package tree and lowers
  package manifests to add local QuillUI Apple-module products when Swift source
  imports frameworks such as `AppKit`, `Cocoa`, `CoreGraphics`, or `Security`.
  The mirror exposes upstream `submodules` at both relative depths used by
  Telegram package manifests (`../submodules` and `../../submodules`), so
  packages can build without editing their path dependencies — e.g. TGUIKit's
  transitive `Colors` package resolves from the mirrored sibling tree. Nested
  `telegram-ios/submodules` packages are also mirrored so Linux-only source
  lowering can happen in generated working copies instead of mutating upstream.
- `scripts/lower-telegram-linux-source.py` performs mirror-only lowering for
  Apple runtime idioms that do not exist in Linux Swift, including
  `os_unfair_lock` imports, Objective-C-only `@objc`, selector-based
  `Thread(target:selector:object:)`, `CFAbsoluteTimeGetCurrent`,
  `Thread.threadPriority`, and `autoreleasepool` blocks.
- Apple framework shim products are exported as generated upstream packages need
  them; `NaturalLanguage`, `CoreSpotlight`, `Vision`, media framework shims, and
  Objective-C compatibility headers are exposed for the Telegram packages that
  import them.
- Objective-C package islands compile through `QuillObjCCompatibility`, with
  mirror-only lowering for nullability and macOS xattr signatures. Current
  coverage includes the media packages that import ImageIO, AVFoundation,
  CoreVideo, CoreMedia, and macOS OpenGL/CGL headers.

The only telegram-ios submodule package still outside the compile set is
`OpenSSLEncryptionProvider`, blocked on the EncryptionProvider overlay
exporting the upstream Objective-C header that its public header imports
(and on an OpenSSL header surface for Linux).

Current Linux blocker classes:

- The SwiftPM package-island ratchet is compile-green, but this is not a full
  Telegram desktop app yet. The next blocker class is the Xcode workspace /
  main `Telegram-Mac` target graph, resource bundling, app entrypoint lowering,
  and runtime behavior.
- Several framework shims are compile-compatible but behavior-light. Examples:
  Vision returns no OCR observations until a Linux OCR backend is wired, media
  writer/OpenGL headers are inert, and Spotlight indexing is no-op.
- Visual and interactive parity still needs native GTK/Qt rendering for the
  Telegram window stack, event handling, media playback, text input, menus,
  settings, and account/session flows.

The port should stay in QuillUI like Enchanted: Telegram-specific lowering and
audit scripts may live under `scripts/`, but reusable fixes belong in QuillKit,
QuillAppKit, QuillFoundation, QuillUI, or backend renderers.
