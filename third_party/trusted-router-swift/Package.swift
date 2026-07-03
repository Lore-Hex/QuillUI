// swift-tools-version: 6.0

import PackageDescription

var packageDependencies: [Package.Dependency] = []
var trustedRouterDependencies: [Target.Dependency] = []
var trustedRouterSwiftSettings: [SwiftSetting] = []

#if os(Linux)
packageDependencies.append(.package(name: "QuillUI", path: "../.."))
trustedRouterDependencies += [
    .product(name: "AuthenticationServices", package: "QuillUI"),
    .product(name: "CryptoKit", package: "QuillUI"),
    .product(name: "Security", package: "QuillUI"),
]
trustedRouterSwiftSettings += [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-strict-concurrency=minimal"]),
]
#endif

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
    dependencies: packageDependencies + [
        // No dependencies, pure swift (we use URLSession and CryptoKit)
    ],
    targets: [
        .target(
            name: "TrustedRouter",
            dependencies: trustedRouterDependencies,
            swiftSettings: trustedRouterSwiftSettings),
        .testTarget(
            name: "TrustedRouterTests",
            dependencies: ["TrustedRouter"]),
    ]
)
