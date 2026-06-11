// swift-tools-version:5.9

import PackageDescription

// Swift replacement for the upstream Objective-C TGGifConverter island: Linux Swift
// cannot import Objective-C modules, so Telegram-Mac sources that
// `import TGGifConverter` compile against this overlay. The API surface grows with
// the app-source ratchet (scripts/generated-telegram-app-source-check.sh).
let package = Package(
    name: "TGGifConverter",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "TGGifConverter", targets: ["TGGifConverter"])
    ],
    targets: [
        .target(name: "TGGifConverter", path: "QuillTGGifConverterSources")
    ]
)
