// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TrustedRouter",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "TrustedRouter",
            targets: ["TrustedRouter"]),
    ],
    dependencies: [
        // No dependencies, pure swift (we use URLSession and CryptoKit)
    ],
    targets: [
        .target(
            name: "TrustedRouter",
            dependencies: []),
        .testTarget(
            name: "TrustedRouterTests",
            dependencies: ["TrustedRouter"]),
    ]
)
