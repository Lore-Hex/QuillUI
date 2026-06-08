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
- `scripts/generated-telegram-package-check.sh` compiles the first SwiftPM
  package islands on Linux: `ApiCredentials`, `CAPortal`, `ColorPalette`
  (including its transitive `Colors` package), `CalendarUtils`, `CrashHandler`,
  `CurrencyFormat`, `DateUtils`, `DetectSpeech`,
  `EDSunriseSet`, `EmojiSuggestions`, `FastBlur`, `FoundationUtils`, `GZIP`,
  `HackUtils`, `HotKey`, `KeyboardKey`, `MergeLists`, `NumberPluralization`,
  `RingBuffer`, `Strings`, `Svg`, `TGCurrencyFormatter`, `TGPassportMRZ`, and
  `TelegramSystem`.
- `Sources/QuillTelegramBuildOverlays` provides generic generated build overlays
  for Swift-only ambient Apple symbols that cannot be supplied by C headers.
  `ApiCredentials` uses this for Security/CommonCrypto and app-group container
  fallbacks, `Strings` uses it for CoreText glyph-count and swift-corelibs
  word-enumeration fallbacks, and `TelegramSystem` uses it for a Linux
  `sysctlbyname` fallback, while leaving the upstream checkout untouched.
- The generated package check builds from a mirrored package tree and lowers
  package manifests to add local QuillUI Apple-module products when Swift source
  imports frameworks such as `AppKit`, `Cocoa`, `CoreGraphics`, or `Security`.

Current Linux blocker classes:

- Objective-C packages that need deeper runtime declarations and/or behavior
  beyond the current header overlay (image objects, CoreGraphics drawing,
  speech/media helpers, and similar surfaces).
- AppKit/CoreText/Cocoa UI packages that need QuillAppKit/QuillKit shims before
  they can compile (`TGUIKit`, `TelegramMedia`, and the main `Telegram-Mac`
  surface).
- Higher-level Telegram packages that depend on telegram-ios submodules not
  present in the shallow upstream checkout.

The port should stay in QuillUI like Enchanted: Telegram-specific lowering and
audit scripts may live under `scripts/`, but reusable fixes belong in QuillKit,
QuillAppKit, QuillFoundation, QuillUI, or backend renderers.
