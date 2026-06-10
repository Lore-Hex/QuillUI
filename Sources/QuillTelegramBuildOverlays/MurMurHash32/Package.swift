// swift-tools-version:5.9

import PackageDescription

// Swift replacement for the upstream Objective-C MurMurHash32 island: Linux
// Swift cannot import Objective-C modules, so Telegram-Mac sources that
// `import MurMurHash32` compile against this overlay.
let package = Package(
    name: "MurMurHash32",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "MurMurHash32", targets: ["MurMurHash32"])
    ],
    targets: [
        .target(name: "MurMurHash32", path: "QuillMurMurHash32Sources")
    ]
)
