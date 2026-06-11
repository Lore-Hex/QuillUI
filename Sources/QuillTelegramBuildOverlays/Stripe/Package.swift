// swift-tools-version:5.9

import PackageDescription

// Swift replacement for the upstream Objective-C Stripe island: Linux Swift
// cannot import Objective-C modules, so Telegram-Mac sources that
// `import Stripe` compile against this overlay. The API surface grows with
// the app-source ratchet (scripts/generated-telegram-app-source-check.sh).
let package = Package(
    name: "Stripe",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "Stripe", targets: ["Stripe"])
    ],
    targets: [
        .target(name: "Stripe", path: "QuillStripeSources")
    ]
)
