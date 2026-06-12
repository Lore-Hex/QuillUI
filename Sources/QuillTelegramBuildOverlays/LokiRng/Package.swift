// swift-tools-version:5.9

import PackageDescription

// Swift replacement for the upstream Objective-C LokiRng island (a tiny
// deterministic RNG used by the emoji spawn/call tooltip views); Linux Swift
// cannot import Objective-C modules.
let package = Package(
    name: "LokiRng",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "LokiRng", targets: ["LokiRng"])
    ],
    targets: [
        .target(name: "LokiRng", path: "QuillLokiRngSources")
    ]
)
