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
- `scripts/generated-telegram-package-check.sh` compiles the first unchanged
  SwiftPM package islands on Linux: `CAPortal`, `CurrencyFormat`,
  `FoundationUtils`, and `MergeLists`.

Current Linux blocker classes:

- Objective-C packages importing Apple `Foundation/Foundation.h` or
  `Cocoa/Cocoa.h` (`DateUtils`, `NumberPluralization`, `TGCurrencyFormatter`,
  `Svg`, `GZIP`, and similar packages).
- AppKit/CoreText/Cocoa UI packages that need QuillAppKit/QuillKit shims before
  they can compile (`Colors`, `Strings`, `TGUIKit`, `TelegramMedia`, and the
  main `Telegram-Mac` surface).
- Darwin-only system APIs such as `sysctlbyname` in `TelegramSystem`.
- Higher-level Telegram packages that depend on telegram-ios submodules not
  present in the shallow upstream checkout.

The port should stay in QuillUI like Enchanted: Telegram-specific lowering and
audit scripts may live under `scripts/`, but reusable fixes belong in QuillKit,
QuillAppKit, QuillFoundation, QuillUI, or backend renderers.
