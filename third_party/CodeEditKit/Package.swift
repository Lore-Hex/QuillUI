// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "CodeEditKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CodeEditKit",
            type: .dynamic,
            targets: ["CodeEditKit"])
    ],
    dependencies: [
        .package(path: "../ConcurrencyPlus"),
        .package(path: "../AnyCodable")
    ],
    targets: [
        .target(
            name: "CodeEditKit",
            dependencies: ["AnyCodable", "ConcurrencyPlus"])]
)
