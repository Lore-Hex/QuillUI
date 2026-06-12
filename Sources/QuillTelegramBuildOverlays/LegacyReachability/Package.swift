// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "LegacyReachability",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "LegacyReachability", targets: ["LegacyReachability"]),
    ],
    targets: [
        .target(
            name: "LegacyReachability",
            path: "QuillLegacyReachabilitySources"
        ),
    ]
)
